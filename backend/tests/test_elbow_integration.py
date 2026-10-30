import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import pytest
import torch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from backend.app.services.exercise_factory import create_assessment
from backend.app.services.assessment_service import AssessmentService
from src.features.elbow_features_v3 import build_live_features
from src.models.assisted_elbow_v2 import BalancedSVMDeploymentAdapter
from src.exercises.assisted_elbow_v2_assessment import AssistedElbowV2Assessment
from src.exercises.elbow_flexion_assessment import ElbowFlexionAssessment
from src.models.elbow_lstm_v3 import ElbowLSTM


def archived_v3():
    model = ElbowLSTM(input_size=14, hidden_size=128, num_layers=2)
    model.load_state_dict(torch.load(ROOT / 'models/elbow_lstm_v3.pth', map_location='cpu', weights_only=True))
    model.eval()
    return ElbowFlexionAssessment(model, torch.device('cpu'), save_artifacts=False)


def archived_v2():
    return AssistedElbowV2Assessment(BalancedSVMDeploymentAdapter(), save_artifacts=False)


def landmarks(angle=160, visibility=1):
    a = np.zeros((33, 4)); a[:, 3] = visibility
    for shoulder, elbow, wrist, sign in [(11, 13, 15, -1), (12, 14, 16, 1)]:
        a[shoulder, :3] = [sign * .2, .5, 0]
        a[elbow, :3] = [sign * .2, .2, 0]
        rad = np.radians(angle)
        a[wrist, :3] = [sign * (.2 + .3 * np.sin(rad)), .2 + .3 * np.cos(rad), 0]
    a[23, :3] = [-.2, -.2, 0]; a[24, :3] = [.2, -.2, 0]
    return SimpleNamespace(landmark=[SimpleNamespace(x=x,y=y,z=z,visibility=v) for x,y,z,v in a])


def test_all_four_exercises_load():
    for e in ['assisted_elbow_flexion','elbow_flexion','shoulder_rotation','assisted_shoulder_flexion']:
        a = create_assessment(e, save_artifacts=False)
        assert not a.save_artifacts
    with pytest.raises(ValueError):
        create_assessment('unknown')


@pytest.mark.parametrize('n', [15, 25, 80])
def test_v3_features_match_upstream(n):
    source = (ROOT/'src/inference/elbow_v3_reference.py').read_text(encoding='utf-8')
    source = source[source.index('def build_live_features'):source.index('\n\nclass RepDetector:')]
    ns = dict(np=np, SEQUENCE_LENGTH=25, INPUT_SIZE=14)
    exec(source, ns)
    angles = 120 + 40*np.cos(np.linspace(0, 2*np.pi, n))
    features = build_live_features(angles)
    assert features.shape == (25,14)
    np.testing.assert_array_equal(features, ns['build_live_features'](angles))


def test_v3_checkpoint_contract_and_prediction():
    a = archived_v3()
    assert a.model.lstm.input_size == 14
    angles = list(120 + 40*np.cos(np.linspace(0,2*np.pi,60)))
    a.rep_count = 1
    result = a._finalize_rep(angles, [], [[0,0,0]] * 60)
    assert result['model_identity'] == 'ElbowFlexionExtension_LSTM_V3'
    assert result['form'] in ('Correct','Incorrect')
    assert 0 <= result['confidence'] <= 100
    assert np.isfinite(result['range_of_motion'])


def test_v3_cycle_counts_once_and_visibility_loss_discards_partial():
    a = archived_v3()
    completed = []
    angles = np.r_[np.full(20,160), np.linspace(160,65,35),np.linspace(65,160,35),np.full(25,160)]
    for i, angle in enumerate(angles):
        result = a.process_frame(None, landmarks(angle), i)
        if result: completed.append(result)
    assert len(completed) == 1
    a.process_frame(None, landmarks(100,0),len(angles))
    assert not a.rep_active


def test_svm_margin_math_and_feature_order():
    a = BalancedSVMDeploymentAdapter()
    x = a.imputer_statistics.copy()
    result = a.predict_from_scalars(x)
    scaled = (x-a.scaler_mean)/a.scaler_scale
    expected = np.exp(-a.gamma*np.sum((a.support_vectors-scaled)**2, axis=1)) @ a.dual_coefficients + a.intercept
    assert result.decision_score == pytest.approx(float(expected), abs=1e-12)
    assert result.is_incorrect == (expected > 0)
    assert len(result.raw_features) == 34


def test_assisted_v2_bilateral_cycle_counts_once():
    a = archived_v2()
    angles = np.r_[np.full(25,160),np.linspace(160,65,40),np.linspace(65,160,40),np.full(40,160)]
    completed = []
    for i, angle in enumerate(angles):
        lm = landmarks(angle)
        result = a.process_frame(None,lm,i,world_landmarks=lm,timestamp_sec=i/20)
        if result: completed.append(result)
    assert len(completed) == 1
    assert completed[0]['score'] is None
    assert completed[0]['confidence'] is None
    assert completed[0]['range_of_motion'] > 80


def test_assisted_v2_missing_pose_never_counts():
    a = archived_v2()
    for i in range(60):
        assert a.process_frame(None,None,i,timestamp_sec=i/20) is None
    assert a.rep_count == 0


def test_invalid_upload_releases_capture():
    with patch('backend.app.services.assessment_service.cv2.VideoCapture') as capture:
        capture.return_value.isOpened.return_value = False
        with pytest.raises(ValueError, match='open'):
            AssessmentService().assess_video('missing.mp4','elbow_flexion')
        capture.return_value.release.assert_called_once()


def test_batch_uses_world_landmarks_and_actual_fps():
    lm = landmarks()
    with patch('backend.app.services.assessment_service.cv2.VideoCapture') as capture, patch('backend.app.services.exercise_factory.create_assessment') as factory, patch('backend.app.services.assessment_service.mp_pose.Pose') as pose:
        capture.return_value.isOpened.return_value = True
        capture.return_value.get.return_value = 30
        capture.return_value.read.side_effect = [(True,np.zeros((32,32,3),np.uint8)), (False,None)]
        pose.return_value.__enter__.return_value.process.return_value = SimpleNamespace(pose_landmarks=lm,pose_world_landmarks=lm)
        factory.return_value.uses_world_landmarks = True
        factory.return_value.process_frame.return_value = {'form':'Correct','model_identity':'test','smoothness':1.2}
        response = AssessmentService().assess_video('test.mp4','assisted_elbow_flexion')
        assert response['rep_count'] == 1
        assert response['reps'][0]['measurements']['smoothness'] == 1.2
        assert factory.call_args.kwargs['fps'] == 30
        assert factory.return_value.process_frame.call_args.kwargs['world_landmarks'] is lm
        capture.return_value.release.assert_called_once()

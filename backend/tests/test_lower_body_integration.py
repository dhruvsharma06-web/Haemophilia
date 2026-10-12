import sys
from pathlib import Path
import pytest
import numpy as np
import cv2
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from backend.app.main import app
from backend.app.api.routes.live import _create_assessment
from src.exercises.lower_body import (
    LowerBodyAssessment,
    SUPPORTED_LOWER_BODY_EXERCISES,
    canonicalize_lower_body_id,
)
from src.exercises.lower_body.model_evaluator import model_evaluator


client = TestClient(app)


# ---------------------------------------------------------------------------
# SYNTHETIC POSE GENERATION HELPERS
# ---------------------------------------------------------------------------
class MockLM:
    def __init__(self, x=0.5, y=0.5, z=0.0, visibility=0.99):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)
        self.visibility = float(visibility)


def make_pose_base(
    sh_l=(0.3, 0.3, 0.0),
    sh_r=(0.3, 0.3, 0.2),  # shoulder z diff > 0.12 triggers SIDE view detection
    hip_l=(0.4, 0.5, 0.0),
    hip_r=(0.4, 0.5, 0.2),
    knee_l=(0.5, 0.7, 0.0),
    knee_r=(0.5, 0.7, 0.2),
    ankle_l=(0.5, 0.9, 0.0),
    ankle_r=(0.5, 0.9, 0.2),
    heel_l=(0.5, 0.92, 0.0),
    foot_l=(0.55, 0.92, 0.0),
    ear_l=(0.3, 0.2, 0.0),
):
    lms = [MockLM() for _ in range(33)]
    lms[7] = MockLM(*ear_l)
    lms[11] = MockLM(*sh_l)
    lms[12] = MockLM(*sh_r)
    lms[23] = MockLM(*hip_l)
    lms[24] = MockLM(*hip_r)
    lms[25] = MockLM(*knee_l)
    lms[26] = MockLM(*knee_r)
    lms[27] = MockLM(*ankle_l)
    lms[28] = MockLM(*ankle_r)
    lms[29] = MockLM(*heel_l)
    lms[31] = MockLM(*foot_l)
    return type("MockPose", (), {"landmark": lms})()


# 1. heel_slide (supine horizontal: hip=(0.25, 0.7), knee=(0.5, 0.7), ankle=(ax, ay))
def pose_heel_slide(knee_deg: float):
    rad = np.radians(180.0 - knee_deg)
    ax = 0.5 + 0.3 * np.cos(rad)
    ay = 0.7 - 0.3 * np.sin(rad)
    return make_pose_base(
        sh_l=(0.05, 0.7, 0.0),
        hip_l=(0.25, 0.7, 0.0),
        knee_l=(0.5, 0.7, 0.0),
        ankle_l=(ax, ay, 0.0),
        heel_l=(ax, ay + 0.02, 0.0),
    )


# 2. mini_squat (standing: hip=(0.45, 0.45), knee=(0.45, 0.65), ankle=(ax, ay))
def pose_mini_squat(knee_deg: float, knee_dx: float = 0.0):
    rad = np.radians(180.0 - knee_deg)
    ax = 0.45 + 0.25 * np.sin(rad)
    ay = 0.65 + 0.25 * np.cos(rad)
    return make_pose_base(
        sh_l=(0.4, 0.2, 0.0),
        hip_l=(0.45, 0.45, 0.0),
        knee_l=(0.45 + knee_dx, 0.65, 0.0),
        ankle_l=(ax, ay, 0.0),
        heel_l=(ax, ay + 0.02, 0.0),
    )


# 3. seated_knee_extension (seated: hip=(0.4, 0.4), knee=(0.6, 0.4), ankle=(ax, ay))
def pose_seated_ext(knee_deg: float):
    rad = np.radians(180.0 - knee_deg)
    ax = 0.6 + 0.2 * np.cos(rad)
    ay = 0.4 + 0.2 * np.sin(rad)
    return make_pose_base(
        sh_l=(0.4, 0.15, 0.0),
        hip_l=(0.4, 0.4, 0.0),
        knee_l=(0.6, 0.4, 0.0),
        ankle_l=(ax, ay, 0.0),
        heel_l=(ax, ay + 0.02, 0.0),
    )


# 4. straight_leg_raise (supine: shoulder=(0.1, 0.7), hip=(0.4, 0.7), knee=(kx, ky))
def pose_slr(hip_deg: float, knee_deg: float = 178.0):
    rad = np.radians(180.0 - hip_deg)
    kx = 0.4 + 0.3 * np.cos(rad)
    ky = 0.7 - 0.3 * np.sin(rad)
    k_rad = np.radians(180.0 - knee_deg)
    ax = kx + 0.3 * np.cos(rad + k_rad)
    ay = ky - 0.3 * np.sin(rad + k_rad)
    return make_pose_base(
        sh_l=(0.1, 0.7, 0.0),
        hip_l=(0.4, 0.7, 0.0),
        knee_l=(kx, ky, 0.0),
        ankle_l=(ax, ay, 0.0),
        heel_l=(ax, ay + 0.02, 0.0),
    )


# 5. terminal_knee_extension (supine with bolster: hip=(0.25, 0.7), knee=(0.5, 0.7))
def pose_tke(knee_deg: float):
    rad = np.radians(180.0 - knee_deg)
    ax = 0.5 + 0.3 * np.cos(rad)
    ay = 0.7 + 0.3 * np.sin(rad)
    return make_pose_base(
        sh_l=(0.05, 0.7, 0.0),
        hip_l=(0.25, 0.7, 0.0),
        knee_l=(0.5, 0.7, 0.0),
        ankle_l=(ax, ay, 0.0),
        heel_l=(ax, ay + 0.02, 0.0),
    )


# 6. squat (standing: hip=(0.45, 0.45), knee=(0.45, 0.65))
def pose_squat(knee_deg: float):
    rad = np.radians(180.0 - knee_deg)
    ax = 0.45 + 0.25 * np.sin(rad)
    ay = 0.65 + 0.25 * np.cos(rad)
    return make_pose_base(
        sh_l=(0.4, 0.2, 0.0),
        hip_l=(0.45, 0.45, 0.0),
        knee_l=(0.45, 0.65, 0.0),
        ankle_l=(ax, ay, 0.0),
        heel_l=(ax, ay + 0.02, 0.0),
    )


# ---------------------------------------------------------------------------
# 1. CATALOGUE AND ROUTING AUDIT
# ---------------------------------------------------------------------------
def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["status"] == "running"


def test_exercise_catalogue():
    response = client.get("/v1/exercises")
    assert response.status_code == 200
    data = response.json()
    assert "exercises" in data
    exercises = {ex["id"]: ex for ex in data["exercises"]}

    expected_lower = [
        "heel_slide",
        "mini_squat",
        "seated_knee_extension",
        "straight_leg_raise",
        "terminal_knee_extension",
        "squat",
    ]
    for ex_id in expected_lower:
        assert ex_id in exercises, f"Missing lower-body exercise: {ex_id}"
        ex = exercises[ex_id]
        assert ex["available"] is True
        assert ex["status"] == "ready"
        assert len(ex["description"]) > 10

    expected_upper = [
        "assisted_shoulder_flexion",
        "shoulder_rotation",
        "assisted_elbow_flexion",
        "elbow_flexion_extension",
    ]
    for ex_id in expected_upper:
        assert ex_id in exercises, f"Preserved upper-body exercise missing: {ex_id}"


def test_lower_body_routing():
    for ex_id in SUPPORTED_LOWER_BODY_EXERCISES:
        assessment = _create_assessment(ex_id)
        assert isinstance(assessment, LowerBodyAssessment)
        assert assessment.canonical_name == ex_id

        live_state = assessment.get_live_state()
        assert live_state["exercise_id"] == ex_id
        assert live_state["state"] == "UP"
        assert live_state["rep_count"] == 0
        assert "feedback" in live_state
        assert "angle" in live_state


def test_unsupported_exercise_fails_explicitly():
    with pytest.raises(ValueError, match="Unsupported exercise"):
        _create_assessment("non_existent_exercise_xyz")


# ---------------------------------------------------------------------------
# 2. INDIVIDUAL EXERCISE VERIFICATION (ALL 6 MOVEMENTS)
# ---------------------------------------------------------------------------
@pytest.mark.parametrize(
    "ex_id,pose_fn,start_angle,enter_angle,depth_angle,exit_angle,expected_dir",
    [
        ("heel_slide", pose_heel_slide, 175.0, 140.0, 80.0, 175.0, "decrease"),
        ("mini_squat", pose_mini_squat, 175.0, 140.0, 120.0, 172.0, "decrease"),
        ("seated_knee_extension", pose_seated_ext, 90.0, 115.0, 168.0, 90.0, "increase"),
        ("straight_leg_raise", pose_slr, 178.0, 155.0, 130.0, 176.0, "decrease"),
        ("terminal_knee_extension", pose_tke, 140.0, 160.0, 175.0, 140.0, "increase"),
        ("squat", pose_squat, 175.0, 100.0, 95.0, 165.0, "decrease"),
    ],
)
def test_all_six_exercises_clean_rep_cycle(
    ex_id, pose_fn, start_angle, enter_angle, depth_angle, exit_angle, expected_dir
):
    """Verify each exercise's rep trigger, depth target, exit transition, and result structure."""
    assessment = LowerBodyAssessment(ex_id)
    assert assessment.rep_trigger["direction"] == expected_dir

    # Phase 1: Start position -> State UP, rep_count 0
    f1 = assessment.process_frame(None, pose_fn(start_angle), frame_number=1)
    assert f1 is None
    assert assessment.state == "UP"
    assert assessment.rep_count == 0

    # Phase 2: Enter movement -> State transitions to DOWN
    f2 = assessment.process_frame(None, pose_fn(enter_angle), frame_number=2)
    assert f2 is None
    assert assessment.state == "DOWN"
    assert assessment.rep_count == 0

    # Phase 3: Reach depth target -> Remains in DOWN
    f3 = assessment.process_frame(None, pose_fn(depth_angle), frame_number=3)
    assert f3 is None
    assert assessment.state == "DOWN"

    # Phase 4: Return transition -> State transitions back to UP and completes rep
    f4 = assessment.process_frame(None, pose_fn(exit_angle), frame_number=4)
    assert f4 is not None
    assert f4["rep_index"] == 1
    assert f4["exercise"] == ex_id
    assert assessment.state == "UP"
    assert assessment.rep_count == 1
    assert "biomechanical_evaluation" in f4
    assert f4["biomechanical_evaluation"]["depth_reached"] is True


@pytest.mark.parametrize(
    "ex_id,pose_fn,start_angle,enter_angle,shallow_depth,exit_angle",
    [
        ("heel_slide", pose_heel_slide, 175.0, 140.0, 115.0, 175.0),
        ("mini_squat", pose_mini_squat, 175.0, 148.0, 142.0, 172.0),
        ("seated_knee_extension", pose_seated_ext, 90.0, 115.0, 130.0, 90.0),
        ("straight_leg_raise", pose_slr, 178.0, 155.0, 150.0, 176.0),
        ("terminal_knee_extension", pose_tke, 140.0, 160.0, 162.0, 140.0),
    ],
)
def test_exercises_insufficient_depth_alert(
    ex_id, pose_fn, start_angle, enter_angle, shallow_depth, exit_angle
):
    """Verify that failing to reach depth target flags depth_reached=False and raises configured alert."""
    assessment = LowerBodyAssessment(ex_id)
    assessment.process_frame(None, pose_fn(start_angle), frame_number=1)
    assessment.process_frame(None, pose_fn(enter_angle), frame_number=2)
    assessment.process_frame(None, pose_fn(shallow_depth), frame_number=3)
    rep = assessment.process_frame(None, pose_fn(exit_angle), frame_number=4)

    assert rep is not None
    assert rep["biomechanical_evaluation"]["depth_reached"] is False
    assert rep["form"] == "incorrect"
    assert len(rep["biomechanical_evaluation"]["errors"]) > 0


def test_straight_leg_raise_knee_flexion_check():
    """Verify SLR raises knee_flexion_high check when patient bends knee during raise."""
    assessment = LowerBodyAssessment("straight_leg_raise")
    assessment.process_frame(None, pose_slr(178.0, knee_deg=178.0), frame_number=1)
    assessment.process_frame(None, pose_slr(155.0, knee_deg=178.0), frame_number=2)
    rep3 = assessment.process_frame(None, pose_slr(130.0, knee_deg=150.0), frame_number=3)
    assert rep3 is None
    rep4 = assessment.process_frame(None, pose_slr(176.0, knee_deg=178.0), frame_number=4)
    assert rep4 is not None
    assert any("Knee bending" in err or "straight" in err for err in rep4["biomechanical_evaluation"]["errors"])


# ---------------------------------------------------------------------------
# 3. MODEL INFERENCE AUDIT & ERROR HANDLING
# ---------------------------------------------------------------------------
def test_model_bundles_metadata_and_features():
    """Audit the 3 Random Forest bundles against their metadata and schema."""
    expected_models = {
        "mini_squat": {
            "labels": ["heel_lifting", "knee_varus", "knee_past_toes", "ankles_close_together", "back_slouching"],
            "min_features": 900,
        },
        "seated_knee_extension": {
            "labels": ["hip_lifting", "back_slouching", "back_rocking"],
            "min_features": 1000,
        },
        "straight_leg_raise": {
            "labels": ["hip_lifting", "knee_flexion_high", "head_lifting"],
            "min_features": 900,
        },
    }

    for ex_id, meta in expected_models.items():
        assert model_evaluator.has_model(ex_id) is True
        labels = model_evaluator.get_labels(ex_id)
        assert labels == meta["labels"]
        n_feats = model_evaluator.get_feature_count(ex_id)
        assert n_feats >= meta["min_features"]

    for ex_id in ["heel_slide", "terminal_knee_extension", "squat"]:
        assert model_evaluator.has_model(ex_id) is False
        res = model_evaluator.evaluate_repetition(ex_id, [], [])
        assert res["status"] == "rule_based_only"
        assert res["has_trained_model"] is False


def test_model_successful_inference():
    """Test successful ML inference on mini_squat, seated_knee_extension, straight_leg_raise."""
    for ex_id in ["mini_squat", "seated_knee_extension", "straight_leg_raise"]:
        kinematics = [
            {"frame": 1, "angle": 175.0, "left_angle": 175.0, "right_angle": 175.0},
            {"frame": 2, "angle": 130.0, "left_angle": 130.0, "right_angle": 130.0},
            {"frame": 3, "angle": 170.0, "left_angle": 170.0, "right_angle": 170.0},
        ]
        res = model_evaluator.evaluate_repetition(ex_id, kinematics, [])
        assert res["status"] == "model_evaluated"
        assert res["has_trained_model"] is True
        assert len(res["label_predictions"]) == len(model_evaluator.get_labels(ex_id))
        for lbl in model_evaluator.get_labels(ex_id):
            assert isinstance(res["label_predictions"][lbl], bool)
            prob = res["label_probabilities"][lbl]
            assert 0.0 <= prob <= 1.0


def test_model_inference_exception_preservation_and_separation():
    """
    Audit non-silent error handling:
    If an inference exception occurs, do NOT silently convert it into False
    predictions and zero probabilities. Report prediction_failed and keep
    the deterministic biomechanical evaluation completely intact.
    """
    simulated_exc = RuntimeError("CUDA/CPU tensor allocation failure during inference")
    res = model_evaluator.evaluate_repetition(
        "mini_squat",
        [],
        [],
        simulated_error=simulated_exc,
    )
    assert res["status"] == "prediction_failed"
    assert res["has_trained_model"] is True
    assert "CUDA/CPU tensor allocation failure" in res["error"]
    assert res["label_predictions"] == {}
    assert res["label_probabilities"] == {}
    assert res["predicted_errors"] == []

    assessment = LowerBodyAssessment("mini_squat")
    assessment.process_frame(None, pose_mini_squat(175.0), frame_number=1)
    assessment.process_frame(None, pose_mini_squat(140.0), frame_number=2)
    assessment.process_frame(None, pose_mini_squat(120.0), frame_number=3)
    completed_rep = assessment.process_frame(None, pose_mini_squat(172.0), frame_number=4)

    assert completed_rep is not None
    bio = completed_rep["biomechanical_evaluation"]
    assert bio["depth_reached"] is True
    assert bio["best_angle"] <= 130.0


# ---------------------------------------------------------------------------
# 4. WEBSOCKET PROTOCOL & MOBILE FLOW AUDIT
# ---------------------------------------------------------------------------
def test_websocket_live_assessment_lower_body_switch():
    with client.websocket_connect("/v1/assessments/live?exercise=mini_squat") as websocket:
        websocket.send_json({
            "type": "switch_exercise",
            "exercise": "heel_slide",
        })
        resp = websocket.receive_json()
        assert resp["type"] == "exercise_switched"
        assert resp["exercise"] == "heel_slide"


def test_websocket_binary_frame_processing():
    """Verify that JPEG bytes sent over WebSocket are decoded, processed, and return live_state."""
    with client.websocket_connect("/v1/assessments/live?exercise=mini_squat") as websocket:
        test_img = np.zeros((480, 640, 3), dtype=np.uint8)
        _, jpeg_bytes = cv2.imencode(".jpg", test_img)

        websocket.send_bytes(jpeg_bytes.tobytes())
        resp = websocket.receive_json()

        assert resp["type"] == "live_state"
        assert resp.get("exercise_id") == "mini_squat" or resp.get("exercise") in {"mini_squat", "Mini Squat"}
        assert "landmarks" in resp
        assert "state" in resp
        assert "angle" in resp
        assert "feedback" in resp


def test_websocket_live_assessment_upper_body_regression():
    with client.websocket_connect("/v1/assessments/live?exercise=assisted_elbow_flexion") as websocket:
        test_img = np.zeros((480, 640, 3), dtype=np.uint8)
        _, jpeg_bytes = cv2.imencode(".jpg", test_img)
        websocket.send_bytes(jpeg_bytes.tobytes())
        resp = websocket.receive_json()
        assert resp["type"] == "live_state"


def test_websocket_unsupported_exercise():
    with client.websocket_connect("/v1/assessments/live?exercise=unknown_movement_xyz") as websocket:
        msg = websocket.receive_json()
        assert msg["type"] == "error"
        assert "Unsupported exercise" in msg["message"]

import unittest
from types import SimpleNamespace
import numpy as np
import torch

from backend.app.services.exercise_factory import create_assessment
from src.features.elbow_features_v4 import build_features, normalized_features, extract_angles
from src.exercises.elbow_v4_assessment import FullRepDetector, MODEL_VERSION
from src.feedback.elbow_telemetry import movement_metrics


class ElbowV4Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        torch.set_num_threads(1)

    def test_feature_contract_padding_then_normalization(self):
        seq = np.ones((10, 10), dtype=np.float32)
        seq[:, 0] = np.linspace(50, 160, 10)
        features = build_features(seq)
        self.assertEqual(features.shape, (30, 22))
        np.testing.assert_array_equal(features[10:], 0)
        self.assertAlmostEqual(float(features[0, 0]), 50 / 180, places=6)
        self.assertAlmostEqual(float(features[0, 6]), 110, places=4)
        normalized = normalized_features(seq, np.ones((1, 1, 22)), np.ones((1, 1, 22)) * 2)
        np.testing.assert_array_equal(normalized[0, 10:], -.5)
        self.assertEqual(build_features(np.ones((4, 10))), None)

    def test_checkpoint_and_all_legacy_routes_use_new_models(self):
        assessment = create_assessment('elbow_flexion_extension', save_artifacts=False)
        seq = np.ones((40, 10), dtype=np.float32)
        seq[:, 0] = np.linspace(160, 50, 40)
        tensor = torch.from_numpy(normalized_features(seq, assessment.mean, assessment.std))
        with torch.inference_mode():
            output = assessment.model(tensor.to(assessment.device))
        self.assertEqual(tuple(output.shape), (1, 1))
        self.assertTrue(torch.isfinite(output).all())
        self.assertEqual(assessment.get_live_state()['model_version'], MODEL_VERSION)
        self.assertEqual(type(create_assessment('assisted_elbow_flexion', save_artifacts=False)).__name__, 'AssistedElbowV5Assessment')

    def test_full_cycle_counts_once_and_partial_cycle_never_counts(self):
        detector = FullRepDetector()
        detector.reset(160.)
        angles = np.r_[np.linspace(160, 50, 40), np.linspace(50, 160, 40), np.full(10, 160)]
        events = []
        previous = angles[0]
        for i, angle in enumerate(angles):
            event = detector.update(float(angle), float(angle - previous), i / 20.)
            previous = angle
            if event:
                events.append(event)
        self.assertEqual(len(events), 1)
        detector = FullRepDetector()
        detector.reset(160.)
        self.assertTrue(all(detector.update(float(angle), -2., i / 20.) is None for i, angle in enumerate(np.linspace(160, 50, 40))))

    def test_tracking_loss_discards_partial_cycle(self):
        assessment = create_assessment('elbow_flexion_extension', save_artifacts=False)
        assessment.calibrated = True
        assessment.detector.reset(160.)
        assessment.detector.update(130., -3., 1.)
        assessment.process_frame(np.zeros((240, 320, 3), np.uint8), None, timestamp_sec=2.)
        self.assertFalse(assessment.calibrated)
        self.assertEqual(assessment.detector.state, 'READY')
        self.assertEqual(assessment.rep_count, 0)

    def test_descriptive_metrics_allow_both_movement_directions_without_fake_confidence(self):
        times = np.arange(81) / 20.
        bend = np.r_[np.linspace(160, 60, 41), np.linspace(60, 160, 41)[1:]]
        for angles in (bend, 220 - bend):
            result = movement_metrics(angles, times)
            self.assertEqual(result['return_completion'], 100.)
            self.assertAlmostEqual(result['range_of_motion'], 100.)
            self.assertNotIn('confidence', result)
            self.assertEqual(result['score_kind'], 'descriptive_movement_control')
            slow_sampling = movement_metrics(angles[::2], times[::2])
            self.assertLess(abs(result['smoothness'] - slow_sampling['smoothness']), 1.)


if __name__ == '__main__':
    unittest.main()

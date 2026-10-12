import unittest
import numpy as np
from src.feedback.rotation_cycle_detector import RotationCycleDetector
from tests.test_shoulder_rotation_timing import Collector, feature


class DetectorTests(unittest.TestCase):
    def run_zones(self, zones, detector=None):
        detector = detector or RotationCycleDetector(centre=0, min_frames=1)
        bounds = []
        for frame, value in enumerate(np.repeat(zones, 8)):
            result = detector.update(float(value), frame)
            if result: bounds.append(result)
        return detector, bounds

    def test_both_start_directions_count_at_opposite_extreme(self):
        for direction in [-1, 1]:
            detector, bounds = self.run_zones([0, direction * 25, 0, -direction * 25])
            self.assertEqual(len(bounds), 1)
            self.assertEqual(detector.state, 'WAIT_FOR_CENTRE')

    def test_starting_at_extreme_waits_for_centre(self):
        detector, bounds = self.run_zones([25, 0, -25])
        self.assertEqual(bounds, [])
        self.assertEqual(detector.state, 'RETURN_TO_CENTRE')

    def test_stationary_extreme_cannot_calibrate_centre(self):
        detector, bounds = self.run_zones([25] * 5, RotationCycleDetector())
        self.assertIsNone(detector.centre)
        self.assertEqual(bounds, [])

    def test_geometric_centre_calibrates_individual_grip_offsets(self):
        detector = RotationCycleDetector(min_frames=1)
        offsets = (12, -2)
        completed = []
        for frame, value in enumerate(np.repeat([0, 25, 0, -25], 15)):
            result = detector.update(tuple(x + value for x in offsets), frame)
            if result: completed.append(result)
        self.assertEqual(len(completed), 1)
        self.assertEqual(detector.hand_centres, [12, -2])
        detector.reset()
        self.assertEqual(detector.hand_centres, [12, -2])

    def test_partial_and_repeated_same_side_movements_do_not_count(self):
        _, bounds = self.run_zones([0, 25, 0, 25, 0, 25, 0])
        self.assertEqual(bounds, [])

    def test_reset_return_and_multiple_reps(self):
        _, bounds = self.run_zones([0, 25, 0, -25, -25, 0, -25, 0, 25, 0])
        self.assertEqual(len(bounds), 2)

    def test_uncoordinated_arms_cannot_complete(self):
        detector, bounds = self.run_zones([0, 25, 0])
        for frame in range(24, 50):
            self.assertIsNone(detector.update((-25, 0), frame))
        self.assertEqual(bounds, [])

    def test_jitter_and_single_frame_extremes(self):
        detector = RotationCycleDetector(centre=0)
        signal = np.concatenate([np.zeros(20), [25], np.zeros(20), [-25], np.zeros(20)])
        self.assertTrue(all(detector.update(x, i) is None for i, x in enumerate(signal)))

    def test_pauses_are_allowed_but_timeout_requires_new_centre(self):
        _, bounds = self.run_zones([0, 25, 25, 25, 0, -25])
        self.assertEqual(len(bounds), 1)
        _, bounds = self.run_zones([0, 25, 25, 25, 0, -25],
                                  RotationCycleDetector(centre=0, min_frames=1, max_frames=16))
        self.assertEqual(bounds, [])

    def test_tracking_loss_cannot_join_segments(self):
        detector, _ = self.run_zones([0, 25, 0])
        detector.update(float('nan'), 24)
        for frame in range(25, 45):
            self.assertIsNone(detector.update(-25, frame))
        self.assertEqual(detector.state, 'WAIT_FOR_CENTRE')

    def test_missing_frame_cannot_join_segments(self):
        detector, _ = self.run_zones([0, 25, 0])
        self.assertIsNone(detector.update(-25, 30))
        self.assertEqual(detector.state, 'WAIT_FOR_CENTRE')

    def test_completed_bad_form_rep_still_counts(self):
        engine = Collector(None, 'cpu', fps=20, save_artifacts=False)
        result = None
        for i, value in enumerate(np.repeat([0, 25, 0, -25], 20), 1):
            f = feature(value)
            f[4:6] = 150
            engine._extract_feature = lambda landmarks, f=f: f
            result = engine.process_frame(None, object(), frame_number=i) or result
        self.assertEqual(engine.rep_count, 1)
        self.assertEqual(result['form'], 'Incorrect')
        self.assertEqual(result['model_prediction'], 0)
        self.assertIn('ELBOW_ANGLE', result['form_errors'])
        self.assertNotEqual(result['score'], result['correct_probability'])

    def test_live_sequence_bounds_match_classifier_input(self):
        engine = Collector(None, 'cpu', fps=20, save_artifacts=False)
        completed = []
        signal = np.concatenate([np.zeros(20), 25 * np.sin(np.linspace(0, 4 * np.pi, 201)), np.zeros(20)])
        for i, value in enumerate(signal, 1):
            engine._extract_feature = lambda landmarks, value=value: feature(value)
            result = engine.process_frame(None, object(), frame_number=i)
            if result:
                completed.append(result)
                self.assertEqual(len(engine.captured), result['rep_end_frame'] - result['rep_start_frame'] + 1)
        self.assertEqual(len(completed), 2)


if __name__ == '__main__': unittest.main()

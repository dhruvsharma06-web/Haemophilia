import unittest

import numpy as np

from src.feedback.rotation_cycle_detector import RotationCycleDetector


class DetectorTests(unittest.TestCase):
    def test_each_side_excursion_counts_separately(self):
        detector = RotationCycleDetector(centre=0)
        signal = np.concatenate([np.zeros(20), 25 * np.sin(np.linspace(0, 4 * np.pi, 201)), np.zeros(10)])
        bounds = [result for i, value in enumerate(signal) if (result := detector.update(value, i))]
        self.assertEqual(len(bounds), 4)
        self.assertTrue(all(40 <= end - start <= 55 for start, end in bounds))

    def test_same_side_repetitions(self):
        detector = RotationCycleDetector(centre=0)
        one = np.concatenate([np.zeros(10), 25 * np.sin(np.linspace(0, np.pi, 51)), np.zeros(10)])
        signal = np.concatenate([one, one, one])
        bounds = [result for i, value in enumerate(signal) if (result := detector.update(value, i))]
        self.assertEqual(len(bounds), 3)

    def test_calibration_uses_initial_neutral_position(self):
        detector = RotationCycleDetector()
        signal = np.concatenate([np.full(20, 12), 12 + 25 * np.sin(np.linspace(0, np.pi, 51)), np.full(10, 12)])
        bounds = [result for i, value in enumerate(signal) if (result := detector.update(value, i))]
        self.assertEqual(detector.centre, 12)
        self.assertEqual(len(bounds), 1)

    def test_outward_motion_without_return_is_incomplete(self):
        detector = RotationCycleDetector(centre=0)
        signal = np.concatenate([np.zeros(20), np.linspace(0, 25, 40), np.full(20, 25)])
        self.assertTrue(all(detector.update(value, i) is None for i, value in enumerate(signal)))

    def test_jitter_is_not_a_rep(self):
        detector = RotationCycleDetector(centre=0)
        self.assertTrue(all(detector.update(value, i) is None
                            for i, value in enumerate(2 * np.sin(np.arange(300)))))

    def test_single_direction_is_not_a_rep(self):
        detector = RotationCycleDetector(centre=0)
        self.assertTrue(all(detector.update(value, i) is None
                            for i, value in enumerate(np.linspace(0, 40, 200))))

    def test_live_engine_returns_one_cycle_per_sequence(self):
        try:
            from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment
        except ModuleNotFoundError:
            self.skipTest("Video dependencies are unavailable")

        class Collector(ShoulderRotationAssessment):
            def _classify_rep(self, features):
                self.captured = np.asarray(features)
                return 0, 0.5, np.asarray([0.5, 0.5])

        engine = Collector(model=None, device="cpu", fps=20, save_artifacts=False)
        completed = []
        signal = np.concatenate([np.zeros(20), 25 * np.sin(np.linspace(0, 4 * np.pi, 201)), np.zeros(20)])
        for frame, value in enumerate(signal, 1):
            feature = np.asarray([value, value, 0, 0, 90, 90, 1, 1, 0, 0])
            engine._extract_feature = lambda landmarks, feature=feature: feature
            result = engine.process_frame(None, object(), frame)
            if result:
                completed.append(result)
                self.assertEqual(len(engine.captured), result["rep_end_frame"] - result["rep_start_frame"] + 1)
        self.assertEqual(len(completed), 4)
        self.assertTrue(all(2 <= result["duration"] <= 3 for result in completed))


if __name__ == "__main__":
    unittest.main()

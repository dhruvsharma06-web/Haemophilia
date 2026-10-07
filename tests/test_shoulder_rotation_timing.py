"""Live frame timing and tracking interruptions must preserve exercise semantics."""
import unittest

import numpy as np

from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment


class Collector(ShoulderRotationAssessment):
    def _classify_rep(self, features):
        self.captured = np.asarray(features)
        return 0, 0.9, np.array([0.9, 0.1])


def feature(value):
    return np.array([value, value, 0, 0, 90, 90, 1, 1, 0, 0], dtype=np.float32)


class TimingTests(unittest.TestCase):
    def test_irregular_live_frames_keep_four_reps_and_real_duration(self):
        for camera_fps in [10, 20, 30]:
            engine = Collector(None, "cpu", fps=20, save_artifacts=False)
            reps = []
            for time in np.arange(0, 12, 1 / camera_fps):
                value = 0 if time < 1 or time > 11 else 25 * np.sin((time - 1) * 2 * np.pi / 5)
                engine._extract_feature = lambda landmarks, value=value: feature(value)
                result = engine.process_frame(None, object(), timestamp_ms=time * 1000)
                if result:
                    reps.append(result)
            self.assertEqual(len(reps), 4, f"Camera FPS: {camera_fps}")
            self.assertTrue(all(2 <= rep["duration"] <= 3 for rep in reps))
            self.assertGreater(reps[-1]["speed_deg_per_sec"], 0)
            self.assertEqual(engine.get_live_state()["score"], 90)
            self.assertGreater(engine.get_live_state()["range_of_motion"], 0)

    def test_missing_pose_drops_incomplete_rep_but_preserves_completed_count(self):
        engine = Collector(None, "cpu", fps=20, save_artifacts=False)
        one = np.concatenate([np.zeros(20), 25 * np.sin(np.linspace(0, np.pi, 51)), np.zeros(20)])
        for frame, value in enumerate(one, 1):
            engine._extract_feature = lambda landmarks, value=value: feature(value)
            engine.process_frame(None, object(), frame_number=frame)
        self.assertEqual(engine.rep_count, 1)
        centre = engine.cycle_detector.centre
        engine.process_frame(None, None)
        self.assertEqual(engine.rep_count, 1)
        self.assertEqual(engine.cycle_detector.centre, centre)
        self.assertEqual(len(engine.rep_features), 0)
        for frame, value in enumerate(one, 100):
            engine._extract_feature = lambda landmarks, value=value: feature(value)
            engine.process_frame(None, object(), frame_number=frame)
        self.assertEqual(engine.rep_count, 2)

    def test_duplicate_timestamps_and_long_gaps_do_not_join_movements(self):
        engine = Collector(None, "cpu", fps=20, save_artifacts=False)
        engine._extract_feature = lambda landmarks: feature(0)
        engine.process_frame(None, object(), timestamp_ms=0)
        engine.process_frame(None, object(), timestamp_ms=0)
        self.assertEqual(engine.frame_number, 1)
        engine.process_frame(None, object(), timestamp_ms=2000)
        self.assertEqual(engine.frame_number, 41)
        self.assertEqual(len(engine.rep_features), 1)
        self.assertEqual(engine.rep_count, 0)
        with self.assertRaisesRegex(ValueError, "finite"):
            engine.process_frame(None, object(), timestamp_ms=float("nan"))


if __name__ == "__main__":
    unittest.main()

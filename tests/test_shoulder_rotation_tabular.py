"""Check subject isolation, balanced training, and training/live inference parity."""
import unittest
from unittest.mock import patch

import numpy as np
import torch

from scripts import improve_shoulder_rotation as improve
from src.models.shoulder_rotation_tabular import summary_features, ShoulderRotationTabular
from src.models.shoulder_rotation_loader import load_shoulder_rotation_model
from src.models.lstm_model import ExerciseLSTM


class TabularTests(unittest.TestCase):
    def test_each_subject_and_class_has_equal_weight(self):
        y = np.array([0, 0, 0, 1, 0, 1, 1])
        groups = np.array(["A"] * 4 + ["B"] * 3)
        weights = improve.balanced_subject_weights(y, groups)
        totals = [weights[(groups == subject) & (y == label)].sum()
                  for subject in ["A", "B"] for label in [0, 1]]
        np.testing.assert_allclose(totals, np.repeat(len(y) / 4, 4))
        with self.assertRaisesRegex(ValueError, "lacks class"):
            improve.balanced_subject_weights(np.array([0, 0]), np.array(["A", "B"]))

    def test_relative_features_remove_camera_offsets_and_ignore_visibility(self):
        rng = np.random.default_rng(42)
        sequence = rng.normal(size=(128, 10)).astype(np.float32)
        shifted = sequence.copy()
        shifted[:, [0, 1, 8, 9]] += [2, -3, 4, -5]
        shifted[:, 6:8] = 0
        np.testing.assert_allclose(summary_features(sequence, True),
                                   summary_features(shifted, True), atol=2e-6)
        self.assertEqual(summary_features(sequence).shape, (33,))
        sequence[0, 0] = np.nan
        with self.assertRaises(ValueError):
            summary_features(sequence)

    def test_inner_selection_never_reads_held_out_subject(self):
        groups = np.repeat(["A", "B", "C", "D"], 2)
        y = np.tile([0, 1], 4)
        x = np.column_stack([np.repeat([1, 2, 3, 999], 2), y]).astype(float)
        calls = []

        class RecordingEstimator:
            def fit(self, features, labels, **kwargs):
                calls.append(features.copy())
                return self

            def predict(self, features):
                calls.append(features.copy())
                return features[:, 1].astype(int)

        candidate = {"family": "logistic", "parameter": 1, "relative": False}
        with patch.object(improve, "candidates", return_value=[candidate]), \
             patch.object(improve, "estimator", side_effect=lambda *args: RecordingEstimator()):
            _, ranking = improve.select_candidate({False: x}, y, groups, ["A", "B", "C"], 42)
        self.assertEqual(ranking[0]["mean_subject_balanced_accuracy"], 1)
        self.assertEqual(len(calls), 6)
        self.assertTrue(all(not np.any(values[:, 0] == 999) for values in calls))

    def test_live_adapter_matches_all_classifier_families(self):
        rng = np.random.default_rng(7)
        sequences = rng.normal(size=(8, 128, 10)).astype(np.float32)
        y = np.tile([0, 1], 4)
        x = np.stack([summary_features(row) for row in sequences])
        for family, parameter in [("logistic", 1), ("svm", 2), ("extra_trees", 3)]:
            candidate = {"family": family, "parameter": parameter, "relative": False}
            fitted = improve.estimator(candidate, 42).fit(x, y)
            adapter = ShoulderRotationTabular(fitted)
            logits = adapter(torch.from_numpy(sequences))
            self.assertTrue(torch.isfinite(logits).all())
            np.testing.assert_array_equal(logits.argmax(dim=1).numpy(), fitted.predict(x))

    def test_loader_preserves_wrapped_lstm_checkpoints(self):
        original = ExerciseLSTM(10, 64, 2, 2, 0.3).eval()
        with patch("pathlib.Path.is_file", return_value=True), \
             patch("torch.cuda.is_available", return_value=False), \
             patch("torch.load", return_value={"model_state_dict": original.state_dict()}):
            loaded, device = load_shoulder_rotation_model("previous.pth")
        sequence = torch.zeros(1, 128, 10)
        with torch.no_grad():
            torch.testing.assert_close(loaded(sequence), original(sequence))
        self.assertEqual(str(device), "cpu")

    def test_registry_uses_configured_model_and_caches_it(self):
        from backend.app.services.model_registry import ModelRegistry
        registry = ModelRegistry()
        model, device = object(), torch.device("cpu")
        with patch.dict("os.environ", {"SHOULDER_ROTATION_MODEL": "models/new.joblib"}), \
             patch("src.models.shoulder_rotation_loader.load_shoulder_rotation_model",
                   return_value=(model, device)) as loader:
            self.assertEqual(registry.get_shoulder_rotation(), (model, device))
            self.assertEqual(registry.get_shoulder_rotation(), (model, device))
        self.assertEqual(loader.call_count, 1)
        self.assertTrue(loader.call_args.args[0].is_absolute())
        self.assertEqual(loader.call_args.args[0].as_posix().split("/")[-2:], ["models", "new.joblib"])


if __name__ == "__main__":
    unittest.main()

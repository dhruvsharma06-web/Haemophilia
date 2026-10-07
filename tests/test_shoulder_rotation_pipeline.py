"""CPU smoke checks; synthetic data is not evidence of exercise accuracy."""
import importlib.util
import json
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pipeline", ROOT / "scripts/shoulder_rotation_pipeline.py")
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class PipelineTests(unittest.TestCase):
    def test_confusion_matrix(self):
        report = pipeline.metrics([0, 0, 1, 1], np.array([0, 1, 0, 1]))
        self.assertEqual(report["confusion_matrix_rows_actual"], [[1, 1], [1, 1]])
        self.assertEqual(report["balanced_accuracy"], 0.5)

    def test_subject_overlap_rejected(self):
        args = Namespace(annotations=ROOT / "docs/shoulder_rotation_subjects.example.csv",
                         train_subjects="S01", val_subjects="S01", test_subjects="S03",
                         output="unused.json")
        # Supply actual accepted annotation schema via a temporary file.
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "annotations.csv"
            pipeline.write_csv(path, [{"subject_id": "S01", "label": "correct",
                                       "review_status": "accepted"}],
                               ["subject_id", "label", "review_status"])
            args.annotations = path
            with self.assertRaisesRegex(ValueError, "multiple partitions"):
                pipeline.split_subjects(args)

    def test_train_evaluate_and_frozen_inputs(self):
        # Keep sequence paths relative to the repository as the extraction CLI does.
        scratch = ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            folder = Path(folder)
            rng = np.random.default_rng(42)
            rows = []
            for subject in ["S01", "S02", "S03"]:
                for label in ["correct", "incorrect"]:
                    path = folder / f"{subject}_{label}.npy"
                    np.save(path, rng.normal(size=(128, 10)).astype(np.float32))
                    rows.append({"subject_id": subject, "label": label, "review_status": "accepted",
                                 "sequence_path": path.relative_to(ROOT).as_posix(),
                                 "video_id": subject, "rep_number": len(rows) + 1})
            annotations = folder / "annotations.csv"
            pipeline.write_csv(annotations, rows, list(rows[0]))
            split_path = folder / "split.json"
            pipeline.split_subjects(Namespace(annotations=annotations, train_subjects="S01",
                val_subjects="S02", test_subjects="S03", output=split_path))
            output = folder / "model"
            pipeline.train(Namespace(annotations=annotations, split=split_path, seed=42, threads=1,
                output=output, epochs=1, patience=2, batch_size=2, lr=0.001))
            args = Namespace(annotations=annotations, split=split_path,
                model=output / "shoulder_rotation_lstm.pth", output=folder / "report")
            pipeline.evaluate(args)
            report = json.loads((folder / "report/test_metrics.json").read_text())
            self.assertEqual(report["samples"], 2)
            self.assertEqual(set(report["per_subject"]), {"S03"})
            final = folder / "final"
            pipeline.train_final(Namespace(annotations=annotations, experiment=output,
                evaluation_report=folder / "report/test_metrics.json", output=final))
            final_config = json.loads((final / "config.json").read_text())
            self.assertEqual(final_config["training_samples"], 6)
            self.assertEqual(final_config["epochs_trained"], 1)
            self.assertEqual(final_config["training_subjects"], ["S01", "S02", "S03"])
            self.assertTrue((final / "shoulder_rotation_lstm.pth").exists())
            loso_output = folder / "loso"
            pipeline.loso(Namespace(annotations=annotations, output=loso_output,
                epochs=1, patience=1, batch_size=2, lr=0.001, seed=42, threads=1, fit_final=True))
            loso_summary = json.loads((loso_output / "summary.json").read_text())
            self.assertEqual(loso_summary["overall"]["samples"], 6)
            self.assertEqual(set(loso_summary["per_subject"]), {"S01", "S02", "S03"})
            for held_out, fold in loso_summary["per_subject"].items():
                self.assertNotIn(held_out, fold["training_subjects"])
                self.assertNotEqual(held_out, fold["inner_validation_subject"])
            loso_predictions = pipeline.read_csv(loso_output / "predictions.csv")
            self.assertEqual(len({r["sequence_path"] for r in loso_predictions}), 6)
            self.assertTrue((loso_output / "final/shoulder_rotation_lstm.pth").exists())
            with self.assertRaisesRegex(ValueError, "original E partition"):
                pipeline.evaluate(Namespace(annotations=annotations, split=split_path,
                    model=final / "shoulder_rotation_lstm.pth", output=folder / "invalid_report"))
            with annotations.open("a") as f:
                f.write("\n")
            with self.assertRaisesRegex(ValueError, "changed since training"):
                pipeline.evaluate(args)


if __name__ == "__main__":
    unittest.main()

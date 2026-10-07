"""Shoulder rotation CLI. Run from the repository root; see docs runbook."""
import argparse
import csv
import hashlib
import json
import random
import re
import sys
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from src.models.lstm_model import ExerciseLSTM
from src.exercises.shoulder_rotation import FEATURE_NAMES, REP_DEFINITION


def read_csv(path):
    with Path(path).open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def write_csv(path, rows, fields):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def save_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def new_model():
    return ExerciseLSTM(10, 64, 2, 2, 0.3)


def metrics(y, p):
    cm = np.zeros((2, 2), dtype=int)
    for actual, predicted in zip(y, p):
        cm[int(actual), int(predicted)] += 1
    recall = np.divide(cm.diagonal(), cm.sum(1), out=np.zeros(2), where=cm.sum(1) != 0)
    precision = np.divide(cm.diagonal(), cm.sum(0), out=np.zeros(2), where=cm.sum(0) != 0)
    f1 = np.divide(2 * precision * recall, precision + recall,
                   out=np.zeros(2), where=(precision + recall) != 0)
    return {"samples": len(y), "accuracy": float(np.mean(np.asarray(y) == p)),
            "balanced_accuracy": float(recall.mean()), "macro_f1": float(f1.mean()),
            "incorrect_precision": float(precision[1]), "incorrect_recall": float(recall[1]),
            "confusion_matrix_rows_actual": cm.tolist(), "class_order": ["correct", "incorrect"]}


def extract(args):
    # Import video dependencies only for video commands.
    import cv2
    import mediapipe as mp
    from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment
    if not hasattr(mp, "solutions"):
        raise ValueError("This project requires a MediaPipe version exposing mp.solutions.pose.")
    manifest = read_csv(args.manifest)
    if not manifest:
        raise ValueError("Manifest is empty.")
    if getattr(args, "videos", None):
        requested = set(args.videos)
        if requested - {item["video_id"] for item in manifest}:
            raise ValueError("Unknown video IDs supplied to --videos.")
        manifest = [item for item in manifest if item["video_id"] in requested]
    output = Path(args.output)
    if output.exists():
        raise ValueError("Output already exists. Choose a new output directory to preserve reviewed labels.")
    output.mkdir(parents=True)
    candidates, seen, diagnostics = [], set(), []

    class Collector(ShoulderRotationAssessment):
        def _classify_rep(self, features):
            data = np.asarray(features, dtype=np.float32)
            self.captured = self._normalize_sequence(np.column_stack([
                self._resize_signal(data[:, j]) for j in range(10)]))
            self.raw_capture = data.copy()
            # Placeholder only: candidate labels always require human review.
            return 0, 0.5, np.array([0.5, 0.5])

    for item in manifest:
        video_id = item["video_id"]
        if not re.fullmatch(r"[A-Za-z0-9_-]+", video_id) or video_id in seen:
            raise ValueError(f"Invalid or duplicate video_id: {video_id}")
        seen.add(video_id)
        if item["label"] not in {"correct", "incorrect"} or not item["subject_id"]:
            raise ValueError(f"Invalid manifest label/subject: {video_id}")
        path = Path(args.dataset) / item["relative_path"]
        cap = cv2.VideoCapture(str(path))
        source_fps = cap.get(cv2.CAP_PROP_FPS)
        if not cap.isOpened() or not np.isfinite(source_fps) or source_fps <= 0:
            cap.release()
            raise ValueError(f"Cannot open video or determine FPS: {path}")
        if source_fps < 19.5:
            cap.release()
            raise ValueError(f"{video_id}: source must be at least 20 FPS for this pipeline.")
        engine = Collector(new_model(), torch.device("cpu"), fps=20, save_artifacts=False)
        valid, number, source_number, next_time = [], 0, 0, 0.0
        count, quality_rejections = 0, 0
        try:
            with mp.solutions.pose.Pose(model_complexity=1, smooth_landmarks=True,
                                        min_detection_confidence=0.5,
                                        min_tracking_confidence=0.5) as pose:
                while cap.grab():
                    source_time = source_number / source_fps
                    source_number += 1
                    if source_time + 1e-6 < next_time:
                        continue
                    next_time += 1 / 20
                    ok, frame = cap.retrieve()
                    if not ok:
                        break
                    number += 1
                    if number % 200 == 0:
                        print(f"{video_id}: processed {number / 20:.0f}s of video", flush=True)
                    landmarks = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).pose_landmarks
                    good = landmarks is not None and min(
                        landmarks.landmark[i].visibility for i in [11, 12, 13, 14, 15, 16, 23, 24]) >= 0.5
                    if not good:
                        quality_rejections += 1
                        # Never bridge a tracking gap into a training repetition.
                        centre_reference = engine.cycle_detector.centre
                        engine = Collector(new_model(), torch.device("cpu"), fps=20, save_artifacts=False)
                        engine.cycle_detector.centre = centre_reference
                        valid = []
                        continue
                    valid.append(number)
                    result = engine.process_frame(frame, landmarks, frame_number=number)
                    if result:
                        count += 1
                        sequence_path = output / "sequences" / f"{video_id}_rep_{count:03d}.npy"
                        sequence_path.parent.mkdir(exist_ok=True)
                        np.save(sequence_path, engine.captured)
                        raw_path = sequence_path.with_name(sequence_path.stem + "_raw.npy")
                        np.save(raw_path, engine.raw_capture)
                        start = result["rep_start_frame"]
                        end = result["rep_end_frame"]
                        candidates.append({"video_id": video_id, "subject_id": item["subject_id"],
                            "rep_number": count, "start_sec": (start - 1) / 20,
                            "end_sec": (end - 1) / 20,
                            "sequence_path": sequence_path.resolve().relative_to(ROOT).as_posix(),
                            "label": item["label"], "error_type": item.get("error_type", ""),
                            "review_status": "pending"})
        finally:
            cap.release()
        diagnostics.append({"video_id": video_id, "sampled_frames": number,
                            "quality_rejections": quality_rejections, "candidate_count": count,
                            "centre_angle": engine.cycle_detector.centre})
        print(f"{video_id}: {count} candidates, {quality_rejections}/{number} frames rejected", flush=True)
    fields = ["video_id", "subject_id", "rep_number", "start_sec", "end_sec", "sequence_path",
              "label", "error_type", "review_status"]
    write_csv(output / "annotations.csv", candidates, fields)
    save_json(output / "extraction_config.json", {"fps": 20, "min_visibility": 0.5,
              "feature_names": FEATURE_NAMES, "sequence_shape": [128, 10],
              "rep_definition": REP_DEFINITION,
              "centre_calibration_seconds": 0.5,
              "centre_to_side_excursion_degrees": 10.0,
              "centre_return_band_degrees": 3.0,
              "manifest": manifest, "candidate_count": len(candidates)})
    save_json(output / "detection_diagnostics.json", diagnostics)
    print(f"Review {output / 'annotations.csv'}; no candidate is automatically accepted.")


def split_subjects(args):
    rows = [r for r in read_csv(args.annotations) if r["review_status"] == "accepted"]
    groups = {"train": args.train_subjects.split(","),
              "validation": args.val_subjects.split(","), "test": args.test_subjects.split(",")}
    groups = {k: [s.strip() for s in v if s.strip()] for k, v in groups.items()}
    subjects = [s for group in groups.values() for s in group]
    if len(subjects) != len(set(subjects)):
        raise ValueError("A subject appears in multiple partitions.")
    if set(subjects) != {r["subject_id"] for r in rows}:
        raise ValueError("Partition lists must cover exactly the subjects with accepted repetitions.")
    for name, group in groups.items():
        selected = [r for r in rows if r["subject_id"] in group]
        if {r["label"] for r in selected} != {"correct", "incorrect"}:
            raise ValueError(f"{name} needs accepted repetitions from both classes.")
        print(name, len(selected), "repetitions", group)
    save_json(args.output, groups)


def load_partition(annotations, split, name):
    rows = [r for r in read_csv(annotations)
            if r["review_status"] == "accepted" and r["subject_id"] in split[name]]
    if not rows or {r["label"] for r in rows} != {"correct", "incorrect"}:
        raise ValueError(f"{name} must contain both reviewed classes.")
    sequences = []
    for row in rows:
        sequence = np.load(ROOT / row["sequence_path"], allow_pickle=False)
        if sequence.shape != (128, 10) or not np.isfinite(sequence).all():
            raise ValueError(f"Invalid sequence: {row['sequence_path']}")
        sequences.append(sequence)
    x = torch.from_numpy(np.stack(sequences).astype(np.float32))
    y = torch.tensor([0 if r["label"] == "correct" else 1 for r in rows])
    return x, y, rows


def predict(model, x, device):
    model.eval()
    with torch.no_grad():
        return torch.cat([torch.softmax(model(batch.to(device)), 1).cpu()
                          for batch in x.split(32)]).numpy()


def train(args):
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    split = json.loads(Path(args.split).read_text())
    flat = [s for group in split.values() for s in group]
    if len(flat) != len(set(flat)):
        raise ValueError("Subject leakage in split.")
    x, y, _ = load_partition(args.annotations, split, "train")
    vx, vy, _ = load_partition(args.annotations, split, "validation")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = new_model().to(device)
    counts = torch.bincount(y, minlength=2).float()
    criterion = torch.nn.CrossEntropyLoss(weight=(len(y) / (2 * counts)).to(device))
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    loader = torch.utils.data.DataLoader(torch.utils.data.TensorDataset(x, y),
                                        batch_size=args.batch_size, shuffle=True)
    output = Path(args.output)
    if output.exists():
        raise ValueError("Training output already exists; choose a new experiment directory.")
    output.mkdir(parents=True)
    history, best, stale = [], -1.0, 0
    for epoch in range(1, args.epochs + 1):
        model.train()
        loss_sum = 0.0
        for bx, by in loader:
            optimizer.zero_grad()
            loss = criterion(model(bx.to(device)), by.to(device))
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            loss_sum += loss.item() * len(by)
        probabilities = predict(model, vx, device)
        report = metrics(vy.numpy(), probabilities.argmax(1))
        history.append({"epoch": epoch, "train_loss": loss_sum / len(y), **report})
        print(f"Epoch {epoch}: loss={loss_sum / len(y):.4f}, val balanced accuracy={report['balanced_accuracy']:.3f}")
        if report["balanced_accuracy"] > best:
            best, stale = report["balanced_accuracy"], 0
            torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()},
                       output / "shoulder_rotation_lstm.pth")
            save_json(output / "best_validation.json", {"epoch": epoch, **report})
        else:
            stale += 1
        if stale >= args.patience:
            break
    save_json(output / "history.json", history)
    save_json(output / "config.json", {"architecture": {"input_size": 10, "hidden_size": 64,
        "num_layers": 2, "num_classes": 2, "dropout": 0.3}, "feature_names": FEATURE_NAMES,
        "rep_definition": REP_DEFINITION,
        "sequence_length": 128, "fps": 20, "seed": args.seed, "split": split,
        "annotations_sha256": hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest(),
        "torch_version": torch.__version__, "numpy_version": np.__version__,
        "normalization": {"angle": 180, "velocity": 360, "torso_tilt": 90},
        "epochs_requested": args.epochs, "lr": args.lr, "batch_size": args.batch_size})


def evaluate(args):
    split = json.loads(Path(args.split).read_text())
    config_path = Path(args.model).parent / "config.json"
    config = json.loads(config_path.read_text())
    if config.get("training_mode") == "all_subjects_after_evaluation":
        raise ValueError("This final model trained on all original subjects. Test it on new subjects; the original E partition is no longer held out.")
    if split != config["split"] or hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest() != config["annotations_sha256"]:
        raise ValueError("Split or annotations changed since training. Use the frozen experiment inputs.")
    x, y, rows = load_partition(args.annotations, split, "test")
    model = new_model()
    model.load_state_dict(torch.load(args.model, map_location="cpu", weights_only=True))
    probs = predict(model, x, torch.device("cpu"))
    predictions = probs.argmax(1)
    report = metrics(y.numpy(), predictions)
    report["per_subject"] = {}
    for subject in split["test"]:
        indices = [i for i, row in enumerate(rows) if row["subject_id"] == subject]
        if indices:
            report["per_subject"][subject] = metrics(y.numpy()[indices], predictions[indices])
    save_json(Path(args.output) / "test_metrics.json", report)
    output_rows = [{"video_id": row["video_id"], "subject_id": row["subject_id"],
                   "rep_number": row["rep_number"], "actual": row["label"],
                   "predicted": ["correct", "incorrect"][int(predictions[i])],
                   "incorrect_probability": float(probs[i, 1])} for i, row in enumerate(rows)]
    write_csv(Path(args.output) / "test_predictions.csv", output_rows, list(output_rows[0]))
    print(json.dumps(report, indent=2))


def train_final(args):
    """Refit from scratch on all accepted data using validation-selected epochs."""
    experiment = Path(args.experiment)
    config = json.loads((experiment / "config.json").read_text())
    validation = json.loads((experiment / "best_validation.json").read_text())
    evaluation = json.loads(Path(args.evaluation_report).read_text())
    fingerprint = hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest()
    if fingerprint != config["annotations_sha256"]:
        raise ValueError("Annotations differ from the evaluated experiment; preserve its frozen dataset.")
    if config.get("training_mode") == "all_subjects_after_evaluation":
        raise ValueError("Use the original train/validation experiment, not a final model.")
    _, test_y, _ = load_partition(args.annotations, config["split"], "test")
    if evaluation.get("samples") != len(test_y) or set(evaluation.get("per_subject", {})) != set(config["split"]["test"]):
        raise ValueError("Evaluation report does not match the experiment's held-out subjects.")
    subjects = sorted({r["subject_id"] for r in read_csv(args.annotations) if r["review_status"] == "accepted"})
    x, y, _ = load_partition(args.annotations, {"all": subjects}, "all")
    epochs = int(validation["epoch"])
    if epochs < 1:
        raise ValueError("Invalid validation-selected epoch.")
    seed = int(config["seed"])
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.set_num_threads(2)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = new_model().to(device)
    counts = torch.bincount(y, minlength=2).float()
    criterion = torch.nn.CrossEntropyLoss(weight=(len(y) / (2 * counts)).to(device))
    optimizer = torch.optim.Adam(model.parameters(), lr=float(config["lr"]))
    loader = torch.utils.data.DataLoader(torch.utils.data.TensorDataset(x, y),
                                        batch_size=int(config["batch_size"]), shuffle=True)
    output = Path(args.output)
    if output.exists():
        raise ValueError("Final training output already exists; choose a new directory.")
    output.mkdir(parents=True)
    history = []
    print(f"Final fit: {len(y)} repetitions, subjects {subjects}, {epochs} epochs, {device}", flush=True)
    for epoch in range(1, epochs + 1):
        model.train()
        loss_sum = 0.0
        for bx, by in loader:
            optimizer.zero_grad()
            loss = criterion(model(bx.to(device)), by.to(device))
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            loss_sum += loss.item() * len(by)
        history.append({"epoch": epoch, "train_loss": loss_sum / len(y)})
        print(f"Epoch {epoch}/{epochs}: loss={loss_sum / len(y):.4f}", flush=True)
    torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()},
               output / "shoulder_rotation_lstm.pth")
    final_config = {k: v for k, v in config.items() if k != "split"}
    final_config.update({"training_mode": "all_subjects_after_evaluation", "training_subjects": subjects,
        "training_samples": len(y), "epochs_trained": epochs, "source_experiment": str(experiment),
        "benchmark_report": str(args.evaluation_report),
        "evaluation_note": "The source experiment's accuracy belongs to its checkpoint. This refit has no held-out result on original subjects."})
    save_json(output / "config.json", final_config)
    save_json(output / "history.json", history)
    print(f"Saved {output / 'shoulder_rotation_lstm.pth'}", flush=True)


def fit_fixed_epochs(x, y, epochs, args, prefix):
    """Refit without inspecting any validation or test labels."""
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = new_model().to(device)
    counts = torch.bincount(y, minlength=2).float()
    if torch.any(counts == 0):
        raise ValueError("Training requires both classes.")
    criterion = torch.nn.CrossEntropyLoss(weight=(len(y) / (2 * counts)).to(device))
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
    loader = torch.utils.data.DataLoader(torch.utils.data.TensorDataset(x, y),
                                        batch_size=args.batch_size, shuffle=True)
    history = []
    for epoch in range(1, epochs + 1):
        model.train()
        total = 0.0
        for bx, by in loader:
            optimizer.zero_grad()
            loss = criterion(model(bx.to(device)), by.to(device))
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            total += loss.item() * len(by)
        history.append({"epoch": epoch, "train_loss": total / len(y)})
        print(f"{prefix} epoch {epoch}/{epochs}: loss={total / len(y):.4f}", flush=True)
    return model, history, device


def loso(args):
    """Test every person out of sample, then optionally fit all subjects."""
    rows = [r for r in read_csv(args.annotations) if r["review_status"] == "accepted"]
    subjects = sorted({r["subject_id"] for r in rows})
    if len(subjects) < 3:
        raise ValueError("At least three subjects are needed for separate inner validation and outer testing.")
    # Preflight all arrays and class coverage before creating an experiment.
    for subject in subjects:
        load_partition(args.annotations, {"subject": [subject]}, "subject")
    output = Path(args.output)
    if output.exists():
        raise ValueError("LOSO output already exists; use a new output directory.")
    output.mkdir(parents=True)
    fingerprint = hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest()
    predictions, per_subject, selected_epochs = [], {}, []
    for index, held_out in enumerate(subjects):
        remaining = [s for s in subjects if s != held_out]
        validation_subject = subjects[(index + 1) % len(subjects)]
        inner_train = [s for s in remaining if s != validation_subject]
        fold = output / f"fold_{held_out}"
        split = {"train": inner_train, "validation": [validation_subject], "test": [held_out]}
        save_json(fold / "inner_split.json", split)
        print(f"\nFold {held_out}: inner train {inner_train}, validation {validation_subject}, outer test {held_out}", flush=True)
        inner_args = argparse.Namespace(annotations=args.annotations, split=fold / "inner_split.json",
            output=fold / "selection", epochs=args.epochs, patience=args.patience,
            batch_size=args.batch_size, lr=args.lr, seed=args.seed, threads=args.threads)
        train(inner_args)
        epoch = int(json.loads((fold / "selection/best_validation.json").read_text())["epoch"])
        selected_epochs.append(epoch)
        x, y, _ = load_partition(args.annotations, {"train": remaining}, "train")
        model, history, device = fit_fixed_epochs(x, y, epoch, args, f"Fold {held_out} refit")
        tx, ty, test_rows = load_partition(args.annotations, {"test": [held_out]}, "test")
        probabilities = predict(model, tx, device)
        predicted = probabilities.argmax(1)
        report = metrics(ty.numpy(), predicted)
        report.update({"held_out_subject": held_out, "training_subjects": remaining,
                       "inner_validation_subject": validation_subject, "selected_epoch": epoch})
        per_subject[held_out] = report
        save_json(fold / "test_metrics.json", report)
        save_json(fold / "refit_history.json", history)
        refit_split = {"train": remaining, "validation": [], "test": [held_out]}
        refit_config = json.loads((fold / "selection/config.json").read_text())
        refit_config.update({"training_mode": "loso_fold_refit", "split": refit_split,
                             "epochs_trained": epoch, "inner_validation_subject": validation_subject})
        save_json(fold / "config.json", refit_config)
        save_json(fold / "refit_split.json", refit_split)
        torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()},
                   fold / "shoulder_rotation_lstm.pth")
        for i, row in enumerate(test_rows):
            predictions.append({"held_out_subject": held_out, "video_id": row["video_id"],
                "subject_id": row["subject_id"], "rep_number": row["rep_number"],
                "sequence_path": row["sequence_path"], "actual": row["label"],
                "predicted": ["correct", "incorrect"][int(predicted[i])],
                "incorrect_probability": float(probabilities[i, 1])})
        print(f"Fold {held_out}: held-out accuracy={report['accuracy']:.3f}, balanced accuracy={report['balanced_accuracy']:.3f}", flush=True)
    if len(predictions) != len(rows):
        raise ValueError("Every accepted repetition must be tested exactly once.")
    if hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest() != fingerprint:
        raise ValueError("Annotations changed during LOSO; keep experiment inputs frozen.")
    actual = [0 if r["actual"] == "correct" else 1 for r in predictions]
    predicted = np.asarray([0 if r["predicted"] == "correct" else 1 for r in predictions])
    final_epochs = max(1, int(np.median(selected_epochs)))
    summary = {"method": "LOSO with separate inner-subject epoch selection and outer-fold refit",
        "subjects": subjects, "per_subject": per_subject, "overall": metrics(actual, predicted),
        "mean_subject_balanced_accuracy": float(np.mean([r["balanced_accuracy"] for r in per_subject.values()])),
        "selected_epochs": selected_epochs, "final_epochs": final_epochs,
        "annotations_sha256": fingerprint, "rep_definition": REP_DEFINITION,
        "interpretation": "Each held-out subject was excluded from its fold's training and validation. Settings and pose pipeline were developed on this dataset, so results remain exploratory."}
    save_json(output / "summary.json", summary)
    write_csv(output / "predictions.csv", predictions, list(predictions[0]))
    if args.fit_final:
        x, y, _ = load_partition(args.annotations, {"all": subjects}, "all")
        model, history, _ = fit_fixed_epochs(x, y, final_epochs, args, "All-subject final model")
        final = output / "final"
        final.mkdir()
        torch.save({k: v.detach().cpu() for k, v in model.state_dict().items()},
                   final / "shoulder_rotation_lstm.pth")
        save_json(final / "history.json", history)
        save_json(final / "config.json", {"training_mode": "all_subjects_after_evaluation",
            "training_subjects": subjects, "training_samples": len(y), "epochs_trained": final_epochs,
            "architecture": {"input_size": 10, "hidden_size": 64, "num_layers": 2, "num_classes": 2, "dropout": 0.3},
            "feature_names": FEATURE_NAMES, "sequence_length": 128, "rep_definition": REP_DEFINITION,
            "fps": 20, "seed": args.seed, "batch_size": args.batch_size, "lr": args.lr,
            "torch_version": torch.__version__, "numpy_version": np.__version__,
            "annotations_sha256": fingerprint, "benchmark_report": str(output / "summary.json"),
            "evaluation_note": "LOSO metrics describe the fold models. This all-subject refit requires new subjects for independent testing."})
    print(f"\nLOSO report: {output / 'summary.json'}", flush=True)


def video(args):
    import cv2
    import mediapipe as mp
    from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment
    from src.models.shoulder_rotation_loader import load_shoulder_rotation_model
    model, device = load_shoulder_rotation_model(args.model)
    engine = ShoulderRotationAssessment(model, device, fps=20, save_artifacts=False)
    cap = cv2.VideoCapture(args.video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not cap.isOpened() or not np.isfinite(fps) or fps < 19.5:
        cap.release()
        raise ValueError("Provide a readable video of at least 20 FPS.")
    number, source_number, next_time, reps = 0, 0, 0.0, []
    try:
        with mp.solutions.pose.Pose(model_complexity=1, smooth_landmarks=True,
                                    min_detection_confidence=0.5, min_tracking_confidence=0.5) as pose:
            while True:
                ok, frame = cap.read()
                if not ok:
                    break
                time = source_number / fps
                source_number += 1
                if time + 1e-6 < next_time:
                    continue
                next_time += 1 / 20
                number += 1
                landmarks = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).pose_landmarks
                good = landmarks is not None and min(landmarks.landmark[i].visibility
                    for i in [11, 12, 13, 14, 15, 16, 23, 24]) >= 0.5
                if not good:
                    centre_reference = engine.cycle_detector.centre
                    engine = ShoulderRotationAssessment(model, device, fps=20, save_artifacts=False)
                    engine.cycle_detector.centre = centre_reference
                    continue
                result = engine.process_frame(frame, landmarks, frame_number=number)
                if result:
                    result["rep_number"] = len(reps) + 1
                    reps.append(result)
                    print(f"Rep {len(reps)}: {result['form']} ({result['confidence']}%)")
    finally:
        cap.release()
    save_json(args.output, {"video": args.video, "rep_definition": REP_DEFINITION,
                           "rep_count": len(reps), "reps": reps})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("extract")
    p.add_argument("--manifest", default="dataset/shoulder_rotation/subjects.csv")
    p.add_argument("--dataset", default="dataset/shoulder_rotation")
    p.add_argument("--output", default="processed_data/shoulder_rotation/run01")
    p.add_argument("--videos", nargs="+", help="Process just these manifest video IDs first")
    p.set_defaults(func=extract)
    p = sub.add_parser("split")
    p.add_argument("--annotations", required=True)
    p.add_argument("--train-subjects", required=True)
    p.add_argument("--val-subjects", required=True)
    p.add_argument("--test-subjects", required=True)
    p.add_argument("--output", default="models/shoulder_rotation_split.json")
    p.set_defaults(func=split_subjects)
    p = sub.add_parser("train")
    p.add_argument("--annotations", required=True)
    p.add_argument("--split", default="models/shoulder_rotation_split.json")
    p.add_argument("--output", default="models/shoulder_rotation_run01")
    p.add_argument("--epochs", type=int, default=50)
    p.add_argument("--patience", type=int, default=10)
    p.add_argument("--batch-size", type=int, default=8)
    p.add_argument("--lr", type=float, default=0.001)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--threads", type=int, default=2)
    p.set_defaults(func=train)
    p = sub.add_parser("evaluate")
    p.add_argument("--annotations", required=True)
    p.add_argument("--split", default="models/shoulder_rotation_split.json")
    p.add_argument("--model", default="models/shoulder_rotation_run01/shoulder_rotation_lstm.pth")
    p.add_argument("--output", default="reports/shoulder_rotation_run01")
    p.set_defaults(func=evaluate)
    p = sub.add_parser("train-final", help="Refit all accepted subjects after held-out evaluation")
    p.add_argument("--annotations", required=True)
    p.add_argument("--experiment", default="models/shoulder_rotation_run01")
    p.add_argument("--evaluation-report", default="reports/shoulder_rotation_run01/test_metrics.json")
    p.add_argument("--output", default="models/shoulder_rotation_final01")
    p.set_defaults(func=train_final)
    p = sub.add_parser("loso", help="Test each subject using other subjects, then optionally train all")
    p.add_argument("--annotations", required=True)
    p.add_argument("--output", default="models/shoulder_rotation_loso01")
    p.add_argument("--epochs", type=int, default=50)
    p.add_argument("--patience", type=int, default=10)
    p.add_argument("--batch-size", type=int, default=8)
    p.add_argument("--lr", type=float, default=0.001)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--threads", type=int, default=2)
    p.add_argument("--fit-final", action="store_true", help="Also refit all subjects after fold evaluation")
    p.set_defaults(func=loso)
    p = sub.add_parser("video")
    p.add_argument("--video", required=True)
    p.add_argument("--model", default="models/shoulder_rotation_run01/shoulder_rotation_lstm.pth")
    p.add_argument("--output", default="reports/shoulder_rotation_run01/video_result.json")
    p.set_defaults(func=video)
    args = parser.parse_args()
    try:
        args.func(args)
    except (ValueError, FileNotFoundError, KeyError, ImportError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()

"""Nested subject-wise comparison of compact shoulder rotation classifiers."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import sklearn
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import RobustScaler
from sklearn.svm import SVC

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.shoulder_rotation_pipeline import read_csv, write_csv, save_json, metrics
from src.models.shoulder_rotation_tabular import summary_features


def balanced_subject_weights(y, groups):
    weights = np.empty(len(y), dtype=float)
    subjects = np.unique(groups)
    for subject in subjects:
        for label in [0, 1]:
            mask = (groups == subject) & (y == label)
            if not mask.any():
                raise ValueError(f"Subject {subject} lacks class {label}.")
            weights[mask] = len(y) / (2 * len(subjects) * mask.sum())
    return weights


def candidates():
    return [{"family": family, "parameter": parameter, "relative": relative}
            for relative in [False, True]
            for family, parameters in [("logistic", [0.1, 1.0]), ("svm", [0.5, 2.0]), ("extra_trees", [3, 8])]
            for parameter in parameters]


def estimator(candidate, seed):
    family, parameter = candidate["family"], candidate["parameter"]
    if family == "logistic":
        classifier = LogisticRegression(C=parameter, max_iter=2000, random_state=seed)
    elif family == "svm":
        classifier = SVC(C=parameter, kernel="rbf", gamma="scale", random_state=seed)
    else:
        classifier = ExtraTreesClassifier(n_estimators=200, min_samples_leaf=parameter,
                                          max_features=0.7, random_state=seed, n_jobs=1)
    return Pipeline([("scale", RobustScaler()), ("classifier", classifier)])


def select_candidate(matrices, y, groups, allowed, seed):
    """Inner validation sees only allowed subjects; no outer held-out labels."""
    scores = []
    for candidate in candidates():
        x = matrices[candidate["relative"]]
        reports = []
        for validation in allowed:
            train_mask = np.isin(groups, [s for s in allowed if s != validation])
            validation_mask = groups == validation
            model = estimator(candidate, seed)
            weights = balanced_subject_weights(y[train_mask], groups[train_mask])
            model.fit(x[train_mask], y[train_mask], classifier__sample_weight=weights)
            reports.append(metrics(y[validation_mask], model.predict(x[validation_mask])))
        scores.append({"candidate": candidate,
            "mean_subject_balanced_accuracy": float(np.mean([r["balanced_accuracy"] for r in reports])),
            "mean_subject_macro_f1": float(np.mean([r["macro_f1"] for r in reports]))})
    ranked = sorted(scores, key=lambda r: (r["mean_subject_balanced_accuracy"], r["mean_subject_macro_f1"]), reverse=True)
    return ranked[0]["candidate"], ranked


def run(args):
    output = Path(args.output)
    if output.exists():
        raise ValueError("Output exists; use a new experiment directory.")
    rows = [r for r in read_csv(args.annotations) if r["review_status"] == "accepted"]
    if not rows or any(r["label"] not in {"correct", "incorrect"} for r in rows):
        raise ValueError("Accepted rows must have correct or incorrect labels.")
    if len({r["sequence_path"] for r in rows}) != len(rows):
        raise ValueError("Duplicate sequence paths in accepted annotations.")
    y = np.asarray([0 if r["label"] == "correct" else 1 for r in rows])
    groups = np.asarray([r["subject_id"] for r in rows])
    subjects = sorted(set(groups))
    if len(subjects) < 3:
        raise ValueError("At least three subjects are required.")
    balanced_subject_weights(y, groups)
    sequences = [np.load(ROOT / r["sequence_path"], allow_pickle=False) for r in rows]
    matrices = {relative: np.stack([summary_features(x, relative) for x in sequences])
                for relative in [False, True]}
    fingerprint = hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest()
    output.mkdir(parents=True)
    per_subject, predictions = {}, []
    for held_out in subjects:
        allowed = [s for s in subjects if s != held_out]
        print(f"Selecting model for held-out {held_out} using inner subjects {allowed}", flush=True)
        selected, ranking = select_candidate(matrices, y, groups, allowed, args.seed)
        train_mask, test_mask = groups != held_out, groups == held_out
        x = matrices[selected["relative"]]
        model = estimator(selected, args.seed)
        model.fit(x[train_mask], y[train_mask], classifier__sample_weight=balanced_subject_weights(y[train_mask], groups[train_mask]))
        predicted = model.predict(x[test_mask])
        report = metrics(y[test_mask], predicted)
        report.update({"selected_candidate": selected, "training_subjects": allowed})
        per_subject[held_out] = report
        save_json(output / f"fold_{held_out}_selection.json", ranking)
        indices = np.flatnonzero(test_mask)
        for i, index in enumerate(indices):
            row = rows[index]
            predictions.append({"subject_id": held_out, "video_id": row["video_id"],
                "rep_number": row["rep_number"], "sequence_path": row["sequence_path"],
                "actual": row["label"], "predicted": ["correct", "incorrect"][int(predicted[i])]})
        print(f"{held_out}: selected {selected}, accuracy={report['accuracy']:.3f}, balanced={report['balanced_accuracy']:.3f}", flush=True)
    actual = [0 if r["actual"] == "correct" else 1 for r in predictions]
    predicted = np.asarray([0 if r["predicted"] == "correct" else 1 for r in predictions])
    report = {"method": "Nested LOSO: candidate selection uses all inner subjects; training weights balance subject and class",
        "per_subject": per_subject, "overall": metrics(actual, predicted),
        "mean_subject_balanced_accuracy": float(np.mean([r["balanced_accuracy"] for r in per_subject.values()])),
        "annotations_sha256": fingerprint,
        "interpretation": "Development results on an already inspected cohort. New subjects are required for independent confirmation."}
    save_json(output / "summary.json", report)
    write_csv(output / "predictions.csv", predictions, list(predictions[0]))
    selected, ranking = select_candidate(matrices, y, groups, subjects, args.seed)
    final = estimator(selected, args.seed)
    final.fit(matrices[selected["relative"]], y, classifier__sample_weight=balanced_subject_weights(y, groups))
    artifact = output / "shoulder_rotation_classifier.joblib"
    joblib.dump({"estimator": final, "relative": selected["relative"]}, artifact)
    save_json(output / "checkpoint_sha256.json", {artifact.name: hashlib.sha256(artifact.read_bytes()).hexdigest()})
    save_json(output / "final_selection.json", ranking)
    save_json(output / "config.json", {"model_type": "shoulder_rotation_tabular",
        "selected_candidate": selected, "training_subjects": subjects, "training_samples": len(rows),
        "summary_features": matrices[False].shape[1], "sequence_shape": [128, 10],
        "rep_definition": "centre -> one side -> centre", "seed": args.seed,
        "annotations_sha256": fingerprint, "sklearn_version": sklearn.__version__,
        "confidence": "uncalibrated model estimate; SVM uses decision margin", "training_mode": "all_subjects_after_evaluation"})
    if hashlib.sha256(Path(args.annotations).read_bytes()).hexdigest() != fingerprint:
        raise ValueError("Annotations changed during comparison.")
    print(json.dumps(report["overall"], indent=2), flush=True)
    print(f"Final candidate: {selected}; artifact in {output}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--annotations", default="processed_data/shoulder_rotation/run04/annotations.csv")
    parser.add_argument("--output", default="models/shoulder_rotation_improved01")
    parser.add_argument("--seed", type=int, default=42)
    try:
        run(parser.parse_args())
    except (ValueError, FileNotFoundError, KeyError) as error:
        parser.exit(1, f"Error: {error}\n")

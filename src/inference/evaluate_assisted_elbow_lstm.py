"""Evaluation script for Assisted Elbow Flexion LSTM.

Evaluates the saved model checkpoint on the untouched Person 3 test set and
computes 3-fold Leave-One-Subject-Out Cross-Validation (LOSO-CV).
Handles single-class / unavailable subgroups transparently.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd
import torch
from sklearn.metrics import classification_report, confusion_matrix, f1_score, precision_score, recall_score
from torch.utils.data import DataLoader, Dataset

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.models.lstm_model import ExerciseLSTM
from src.features.assisted_elbow_features import FEATURE_NAMES

DATA_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion"
SEQUENCE_DIR = DATA_DIR / "sequences"
MANIFEST_FILE = DATA_DIR / "dataset_manifest.csv"
MODEL_PATH = BASE_DIR / "models" / "assisted_elbow_lstm.pth"
CONFIG_PATH = BASE_DIR / "models" / "assisted_elbow_config.json"


class SequenceEvalDataset(Dataset):
    def __init__(self, records: List[Dict], sequence_dir: Path):
        self.records = records
        self.sequence_dir = sequence_dir

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx: int):
        rec = self.records[idx]
        x = np.load(self.sequence_dir / rec["sequence_file"]).astype(np.float32)
        y = int(rec["numeric_label"])
        return torch.tensor(x, dtype=torch.float32), torch.tensor(y, dtype=torch.long)


def load_model(checkpoint_path: Path, device: torch.device) -> ExerciseLSTM:
    model = ExerciseLSTM(
        input_size=len(FEATURE_NAMES),
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3,
    )
    state = torch.load(checkpoint_path, map_location=device, weights_only=True)
    model.load_state_dict(state)
    model.to(device)
    model.eval()
    return model


def evaluate_records(
    model: ExerciseLSTM,
    records: List[Dict],
    sequence_dir: Path,
    device: torch.device,
) -> Dict:
    if not records:
        return {"samples": 0}

    loader = DataLoader(
        SequenceEvalDataset(records, sequence_dir),
        batch_size=8,
        shuffle=False,
    )

    all_preds = []
    all_targets = []
    all_probs = []

    with torch.no_grad():
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            out = model(x)
            probs = torch.softmax(out, dim=1)
            preds = torch.argmax(probs, dim=1)

            all_preds.extend(preds.cpu().numpy())
            all_targets.extend(y.cpu().numpy())
            all_probs.extend(probs.cpu().numpy())

    preds_arr = np.array(all_preds)
    targets_arr = np.array(all_targets)

    total = len(targets_arr)
    n_correct = int((preds_arr == targets_arr).sum())
    accuracy = (n_correct / total) * 100.0 if total > 0 else 0.0

    # Handle cases where only 1 class is present
    unique_targets = np.unique(targets_arr)
    has_both_classes = len(unique_targets) > 1

    if has_both_classes:
        prec = precision_score(targets_arr, preds_arr, zero_division=0) * 100.0
        rec = recall_score(targets_arr, preds_arr, zero_division=0) * 100.0
        f1 = f1_score(targets_arr, preds_arr, zero_division=0) * 100.0
        cm = confusion_matrix(targets_arr, preds_arr, labels=[0, 1]).tolist()
    else:
        prec = None
        rec = None
        f1 = None
        cm = None

    return {
        "samples": total,
        "correct_predictions": n_correct,
        "incorrect_predictions": total - n_correct,
        "accuracy": accuracy,
        "precision": prec,
        "recall": rec,
        "f1": f1,
        "confusion_matrix": cm,
        "predictions": all_preds,
        "targets": all_targets,
    }


def evaluate_person3_test(manifest: pd.DataFrame, device: torch.device):
    """Main evaluation on the completely untouched Person 3 final test set."""
    p3_records = manifest[manifest["subject_id"] == "person3"].to_dict("records")

    print("\n" + "=" * 70)
    print("FINAL EVALUATION ON UNTOUCHED TEST SET (PERSON 3)")
    print("=" * 70)
    print(f"Total test sequences : {len(p3_records)}")
    if not p3_records:
        print("No Person 3 sequences found in manifest.")
        return

    model = load_model(MODEL_PATH, device)
    results = evaluate_records(model, p3_records, SEQUENCE_DIR, device)

    print(f"Correct predictions  : {results['correct_predictions']}/{results['samples']}")
    print(f"Accuracy             : {results['accuracy']:.2f}%")
    print(f"Precision            : {results['precision']:.2f}%")
    print(f"Recall               : {results['recall']:.2f}%")
    print(f"F1 Score             : {results['f1']:.2f}%\n")

    cm = results["confusion_matrix"]
    print("Confusion Matrix:")
    print("                 Pred Correct   Pred Incorrect")
    print(f"True Correct        {cm[0][0]:^12}   {cm[0][1]:^14}")
    print(f"True Incorrect      {cm[1][0]:^12}   {cm[1][1]:^14}\n")

    # Assistance Subgroup Breakdown
    print("-" * 70)
    print("PER-ASSISTANCE SUBGROUP BREAKDOWN (PERSON 3 TEST SET)")
    print("-" * 70)

    p3_df = manifest[manifest["subject_id"] == "person3"]

    for asst in ["left_hand_assisted", "right_hand_assisted", "both_hand_assisted"]:
        subset = p3_df[p3_df["assistance_type"] == asst]
        sub_records = subset.to_dict("records")
        n_samples = len(sub_records)

        print(f"\nSubgroup: [{asst}]")
        if n_samples == 0:
            print("  Status: No recordings present for this subgroup in the Person 3 test set.")
            print("  (Both-hand recordings exist in Persons 1 & 2 only; mixed recordings excluded).")
            continue

        n_corr = (subset["label"] == "correct").sum()
        n_inc = (subset["label"] == "incorrect").sum()
        print(f"  Samples: {n_samples} (Correct: {n_corr}, Incorrect: {n_inc})")

        sub_res = evaluate_records(model, sub_records, SEQUENCE_DIR, device)
        print(f"  Accuracy: {sub_res['accuracy']:.2f}% ({sub_res['correct_predictions']}/{sub_res['samples']})")

        if sub_res["f1"] is not None:
            print(f"  Precision: {sub_res['precision']:.2f}% | Recall: {sub_res['recall']:.2f}% | F1: {sub_res['f1']:.2f}%")
        else:
            print("  Binary metrics (F1/prec/rec) not applicable: only one ground-truth class present.")


def run_loso_cross_validation(manifest: pd.DataFrame, device: torch.device):
    """Run true 3-fold Leave-One-Subject-Out Cross-Validation (LOSO-CV).
    
    Each fold holds one subject completely out as the untouched test set,
    uses only the other two subjects for training and inner validation-based
    checkpoint selection, and evaluates exactly once on the held-out subject.
    """
    import copy
    from sklearn.metrics import balanced_accuracy_score

    subjects = ["person1", "person2", "person3"]

    print("\n" + "=" * 80)
    print("3-FOLD LEAVE-ONE-SUBJECT-OUT CROSS-VALIDATION (TRUE LOSO-CV)")
    print("=" * 80)

    # Inner validation videos for each fold: selected strictly from training subjects
    inner_val_videos = {
        "person3": {"20260825_135701", "20260825_135545"},      # from Person 2 (1 incorrect, 1 correct)
        "person1": {"VID20260825125333", "VID20260825125720"},  # from Person 3 (1 correct, 1 incorrect)
        "person2": {"VID20260825125257", "VID20260825125647"},  # from Person 3 (1 correct, 1 incorrect)
    }

    all_test_preds = []
    all_test_targets = []
    total_samples = 0
    total_correct = 0

    for held_out in subjects:
        print("\n" + "-" * 80)
        print(f"FOLD: Held-Out Subject = [{held_out}]")
        print("-" * 80)

        test_df = manifest[manifest["subject_id"] == held_out].reset_index(drop=True)
        train_pool_df = manifest[manifest["subject_id"] != held_out].reset_index(drop=True)

        val_vids = inner_val_videos[held_out]
        val_df = train_pool_df[train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)
        train_df = train_pool_df[~train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)

        train_records = train_df.to_dict("records")
        val_records = val_df.to_dict("records")
        test_records = test_df.to_dict("records")

        train_dist = train_df["label"].value_counts().to_dict()
        val_dist = val_df["label"].value_counts().to_dict()
        test_dist = test_df["label"].value_counts().to_dict()

        print(f"Train samples       : {len(train_records):2d}  (Class dist: {train_dist})")
        print(f"Validation samples  : {len(val_records):2d}  (Class dist: {val_dist}) [Videos: {val_vids}]")
        print(f"Test samples        : {len(test_records):2d}  (Class dist: {test_dist})")

        train_dataset = SequenceEvalDataset(train_records, SEQUENCE_DIR)
        train_loader = DataLoader(train_dataset, batch_size=8, shuffle=True)

        model = ExerciseLSTM(
            input_size=len(FEATURE_NAMES),
            hidden_size=64,
            num_layers=2,
            num_classes=2,
            dropout=0.3,
        ).to(device)

        labels = [r["numeric_label"] for r in train_records]
        class_counts = np.bincount(labels)
        class_weights = torch.tensor(
            [len(labels) / (2.0 * count) for count in class_counts],
            dtype=torch.float32,
        ).to(device)

        criterion = torch.nn.CrossEntropyLoss(weight=class_weights)
        optimizer = torch.optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-4)

        best_val_macro_f1 = -1.0
        best_val_loss = float("inf")
        best_state = None
        best_epoch = 0

        # Train and select checkpoint on training-subject validation data
        for epoch in range(1, 41):
            model.train()
            for x, y in train_loader:
                x, y = x.to(device), y.to(device)
                optimizer.zero_grad()
                loss = criterion(model(x), y)
                loss.backward()
                optimizer.step()

            # Evaluate on internal validation records
            val_res = evaluate_records(model, val_records, SEQUENCE_DIR, device)
            val_f1_score = val_res["f1"] if val_res["f1"] is not None else 0.0

            if epoch >= 4 and val_f1_score > best_val_macro_f1:
                best_val_macro_f1 = val_f1_score
                best_state = copy.deepcopy(model.state_dict())
                best_epoch = epoch

        if best_state is not None:
            model.load_state_dict(best_state)
            print(f"Selected Checkpoint : Epoch {best_epoch} (Validation F1: {best_val_macro_f1:.1f}%)")
        else:
            print("Warning: Defaulting to final epoch weights (no validation improvement found).")

        # Evaluate once on the held-out subject
        fold_res = evaluate_records(model, test_records, SEQUENCE_DIR, device)
        total_samples += fold_res["samples"]
        total_correct += fold_res["correct_predictions"]
        all_test_preds.extend(fold_res["predictions"])
        all_test_targets.extend(fold_res["targets"])

        bal_acc = balanced_accuracy_score(fold_res["targets"], fold_res["predictions"]) * 100.0
        macro_f1 = f1_score(fold_res["targets"], fold_res["predictions"], average="macro", zero_division=0) * 100.0

        print(f"\nHeld-Out Results [{held_out}]:")
        print(f"  Accuracy          : {fold_res['accuracy']:.2f}% ({fold_res['correct_predictions']}/{fold_res['samples']})")
        print(f"  Balanced Accuracy : {bal_acc:.2f}%")
        print(f"  Macro-F1          : {macro_f1:.2f}%")
        print(f"  Precision         : {fold_res['precision']:.2f}%" if fold_res['precision'] is not None else "  Precision         : N/A")
        print(f"  Recall            : {fold_res['recall']:.2f}%" if fold_res['recall'] is not None else "  Recall            : N/A")
        print(f"  F1 Score          : {fold_res['f1']:.2f}%" if fold_res['f1'] is not None else "  F1 Score          : N/A")
        
        cm = fold_res["confusion_matrix"]
        print("  Confusion Matrix  :")
        print("                      Pred Correct   Pred Incorrect")
        print(f"    True Correct         {cm[0][0]:^12}   {cm[0][1]:^14}")
        print(f"    True Incorrect       {cm[1][0]:^12}   {cm[1][1]:^14}")

    # Aggregate LOSO Results
    agg_acc = (total_correct / total_samples) * 100.0 if total_samples > 0 else 0.0
    agg_bal_acc = balanced_accuracy_score(all_test_targets, all_test_preds) * 100.0
    agg_macro_f1 = f1_score(all_test_targets, all_test_preds, average="macro", zero_division=0) * 100.0
    agg_cm = confusion_matrix(all_test_targets, all_test_preds, labels=[0, 1])

    print("\n" + "=" * 80)
    print("OVERALL AGGREGATE LOSO-CV RESULTS")
    print("=" * 80)
    print(f"Total Evaluated Samples : {total_samples}")
    print(f"Aggregate Accuracy      : {agg_acc:.2f}% ({total_correct}/{total_samples})")
    print(f"Aggregate Balanced Acc  : {agg_bal_acc:.2f}%")
    print(f"Aggregate Macro-F1      : {agg_macro_f1:.2f}%")
    print("Aggregate Confusion Matrix:")
    print("                    Pred Correct   Pred Incorrect")
    print(f"  True Correct         {agg_cm[0][0]:^12}   {agg_cm[0][1]:^14}")
    print(f"  True Incorrect       {agg_cm[1][0]:^12}   {agg_cm[1][1]:^14}")


def main():
    parser = argparse.ArgumentParser(description="Evaluate Assisted Elbow Flexion LSTM")
    parser.add_argument("--loso", action="store_true", help="Run full LOSO cross-validation")
    args = parser.parse_args()

    if not MANIFEST_FILE.exists():
        print(f"Error: Manifest file not found: {MANIFEST_FILE}")
        return

    manifest = pd.read_csv(MANIFEST_FILE)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Evaluation Device: {device}")

    evaluate_person3_test(manifest, device)

    if args.loso:
        run_loso_cross_validation(manifest, device)


if __name__ == "__main__":
    main()

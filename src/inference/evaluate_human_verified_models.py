"""Authoritative Evaluation of Assisted Elbow Flexion Models on Human-Verified Dataset.

Executes:
1. Untouched Person 3 Final Test Evaluation for LSTM checkpoint (models/assisted_elbow_lstm_human_verified.pth).
2. True 3-fold Leave-One-Subject-Out Cross-Validation (LOSO-CV) for:
   - Deterministic Biomechanical Rules
   - Logistic Regression
   - Random Forest
   - 2-layer ExerciseLSTM
3. Full Comparative Analysis and Problem Shift Audit (Folder Labels vs. Human Labels).
"""

import copy
import json
import os
import random
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from torch.utils.data import DataLoader, Dataset

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.features.assisted_elbow_features import FEATURE_NAMES
from src.models.lstm_model import ExerciseLSTM

DATA_PATH = BASE_DIR / "data" / "clean_elbow_train.csv"
RAW_ANNOTATIONS_PATH = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "repetition_annotations.csv"
SEQUENCE_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
MODEL_PATH = BASE_DIR / "models" / "assisted_elbow_lstm_human_verified.pth"
CONFIG_PATH = BASE_DIR / "models" / "assisted_elbow_config_human_verified.json"

RANDOM_SEED = 42


def set_seed(seed: int = RANDOM_SEED):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


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


def extract_summary_features(df: pd.DataFrame, sequence_dir: Path = SEQUENCE_DIR) -> pd.DataFrame:
    """Extract standard summary kinematic features for tabular ML baselines."""
    rows = []
    for _, row in df.iterrows():
        seq = np.load(sequence_dir / row["sequence_file"])
        # seq columns:
        # 0: act_ang, 1: asst_ang, 2: act_vel, 3: asst_vel, 4: tilt, 5: rot, 6: act_flare, 7: asst_flare
        act_ang = seq[:, 0]
        act_vel = seq[:, 2]
        tilt = seq[:, 4]
        rot = seq[:, 5]
        act_flare = seq[:, 6]

        feats = {
            "ang_min": float(np.min(act_ang)),
            "ang_max": float(np.max(act_ang)),
            "ang_mean": float(np.mean(act_ang)),
            "ang_std": float(np.std(act_ang)),
            "ang_rom": float(np.max(act_ang) - np.min(act_ang)),
            "vel_max": float(np.max(np.abs(act_vel))),
            "vel_mean": float(np.mean(np.abs(act_vel))),
            "vel_std": float(np.std(act_vel)),
            "tilt_mean": float(np.mean(tilt)),
            "tilt_max": float(np.max(tilt)),
            "rot_mean": float(np.mean(rot)),
            "rot_std": float(np.std(rot)),
            "flare_mean": float(np.mean(act_flare)),
            "flare_max": float(np.max(act_flare)),
            "duration": float(row["duration_sec"]),
            "label": int(row["numeric_label"]),
        }
        rows.append(feats)
    return pd.DataFrame(rows)


def evaluate_biomechanical_rule_row(row: pd.Series) -> int:
    """Deterministic rule evaluator derived from calibrated training fold thresholds:
    - min_elbow_angle <= 101.0 deg
    - elbow_flare <= 0.30
    - rom >= 25.0 deg
    Returns: 0 for Correct, 1 for Incorrect.
    """
    min_ang = float(row["min_elbow_angle"])
    flare = float(row["elbow_flare"])
    rom = float(row["rom"])

    if min_ang > 101.0:
        return 1
    if flare > 0.30:
        return 1
    if rom < 25.0:
        return 1
    return 0


def evaluate_records(model: nn.Module, records: List[Dict], sequence_dir: Path, device: torch.device) -> Dict:
    loader = DataLoader(SequenceEvalDataset(records, sequence_dir), batch_size=8, shuffle=False)
    model.eval()
    all_preds, all_targets = [], []
    with torch.no_grad():
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            out = model(x)
            preds = torch.argmax(out, dim=1)
            all_preds.extend(preds.cpu().numpy())
            all_targets.extend(y.cpu().numpy())

    preds_arr = np.array(all_preds)
    targets_arr = np.array(all_targets)

    acc = accuracy_score(targets_arr, preds_arr) * 100.0
    bal_acc = balanced_accuracy_score(targets_arr, preds_arr) * 100.0
    macro_f1 = f1_score(targets_arr, preds_arr, average="macro", zero_division=0) * 100.0
    prec = precision_score(targets_arr, preds_arr, zero_division=0) * 100.0
    rec = recall_score(targets_arr, preds_arr, zero_division=0) * 100.0
    cm = confusion_matrix(targets_arr, preds_arr, labels=[0, 1])

    # Per-class recall
    corr_rec = (cm[0, 0] / (cm[0, 0] + cm[0, 1]) * 100.0) if (cm[0, 0] + cm[0, 1]) > 0 else 0.0
    inc_rec = (cm[1, 1] / (cm[1, 0] + cm[1, 1]) * 100.0) if (cm[1, 0] + cm[1, 1]) > 0 else 0.0

    return {
        "samples": len(targets_arr),
        "correct_predictions": int((preds_arr == targets_arr).sum()),
        "accuracy": acc,
        "balanced_accuracy": bal_acc,
        "macro_f1": macro_f1,
        "precision": prec,
        "recall": rec,
        "correct_recall": corr_rec,
        "incorrect_recall": inc_rec,
        "confusion_matrix": cm,
        "predictions": all_preds,
        "targets": all_targets,
    }


def step6_evaluate_person3(df: pd.DataFrame, device: torch.device):
    """Step 6: Evaluate exactly once on the untouched human-verified Person 3 repetitions."""
    p3_df = df[df["subject_id"] == "person3"].reset_index(drop=True)
    p3_records = p3_df.to_dict("records")

    print("\n" + "=" * 80)
    print("STEP 6: FINAL EVALUATION ON UNTOUCHED PERSON 3 TEST SET (HUMAN-VERIFIED)")
    print("=" * 80)
    n_p3 = len(p3_records)
    n_corr = int((p3_df["numeric_label"] == 0).sum())
    n_inc = int((p3_df["numeric_label"] == 1).sum())

    print(f"Number of Person 3 repetitions       : {n_p3}")
    print(f"Correct / Incorrect distribution     : Correct={n_corr}, Incorrect={n_inc}")

    model = ExerciseLSTM(input_size=len(FEATURE_NAMES), hidden_size=64, num_layers=2, num_classes=2, dropout=0.3)
    state = torch.load(MODEL_PATH, map_location=device, weights_only=True)
    model.load_state_dict(state)
    model.to(device)

    res = evaluate_records(model, p3_records, SEQUENCE_DIR, device)

    print(f"Accuracy                             : {res['accuracy']:.2f}% ({res['correct_predictions']}/{res['samples']})")
    print(f"Balanced Accuracy                    : {res['balanced_accuracy']:.2f}%")
    print(f"Precision (Incorrect class)          : {res['precision']:.2f}%")
    print(f"Recall (Incorrect class)             : {res['recall']:.2f}%")
    print(f"Macro-F1                             : {res['macro_f1']:.2f}%")
    print(f"Correct Recall (Specificity)         : {res['correct_recall']:.2f}%")
    print(f"Incorrect Recall (Sensitivity)       : {res['incorrect_recall']:.2f}%")
    cm = res["confusion_matrix"]
    print("Confusion Matrix:")
    print("                      Pred Correct   Pred Incorrect")
    print(f"  True Correct (0)        {cm[0, 0]:^12}   {cm[0, 1]:^14}")
    print(f"  True Incorrect (1)      {cm[1, 0]:^12}   {cm[1, 1]:^14}")
    print("=" * 80)

    return res


def step7_and_8_loso_benchmark(df: pd.DataFrame, device: torch.device):
    """Steps 7 & 8: True 3-fold Leave-One-Subject-Out Cross-Validation across models."""
    set_seed(RANDOM_SEED)

    subjects = ["person1", "person2", "person3"]
    # Internal validation videos (isolated from test subject, selected strictly from training subjects)
    inner_val_videos = {
        "person3": {"20260825_135701", "20260825_135545"},      # from Person 2
        "person1": {"VID20260825125333", "VID20260825125720"},  # from Person 3
        "person2": {"VID20260825125257", "VID20260825125647"},  # from Person 3
    }

    if "video_id" not in df.columns:
        df["video_id"] = df["video_name"].apply(lambda v: Path(v).stem)

    summary_cols = [
        "ang_min", "ang_max", "ang_mean", "ang_std", "ang_rom",
        "vel_max", "vel_mean", "vel_std",
        "tilt_mean", "tilt_max", "rot_mean", "rot_std",
        "flare_mean", "flare_max", "duration",
    ]

    all_results = {
        "Rule": {"preds": [], "targets": []},
        "LR": {"preds": [], "targets": []},
        "RF": {"preds": [], "targets": []},
        "LSTM": {"preds": [], "targets": []},
    }

    fold_metrics = {"LSTM": []}

    print("\n" + "=" * 80)
    print("STEPS 7 & 8: TRUE 3-FOLD LEAVE-ONE-SUBJECT-OUT (LOSO) BENCHMARK")
    print("=" * 80)

    for held_out in subjects:
        train_pool = df[df["subject_id"] != held_out].reset_index(drop=True)
        test_df = df[df["subject_id"] == held_out].reset_index(drop=True)

        val_vids = inner_val_videos[held_out]
        val_df = train_pool[train_pool["video_id"].isin(val_vids)].reset_index(drop=True)
        train_df = train_pool[~train_pool["video_id"].isin(val_vids)].reset_index(drop=True)

        tr_records = train_df.to_dict("records")
        vl_records = val_df.to_dict("records")
        ts_records = test_df.to_dict("records")

        tr_subjs = sorted(list(train_pool["subject_id"].unique()))
        y_ts = test_df["numeric_label"].values

        print("\n" + "-" * 75)
        print(f"FOLD: Held-Out Subject: {held_out}")
        print(f"Training Subjects     : {tr_subjs}")
        print(f"Training Count        : {len(tr_records)} (Correct: {(train_df['numeric_label']==0).sum()}, Incorrect: {(train_df['numeric_label']==1).sum()})")
        print(f"Validation Count      : {len(vl_records)} (Correct: {(val_df['numeric_label']==0).sum()}, Incorrect: {(val_df['numeric_label']==1).sum()})")
        print(f"Test Count            : {len(ts_records)} (Correct: {(test_df['numeric_label']==0).sum()}, Incorrect: {(test_df['numeric_label']==1).sum()})")

        # 1. Biomechanical Rules
        preds_rule = [evaluate_biomechanical_rule_row(row) for _, row in test_df.iterrows()]
        all_results["Rule"]["preds"].extend(preds_rule)
        all_results["Rule"]["targets"].extend(y_ts)

        # 2. Tabular Features for LR and RF
        tr_tab = extract_summary_features(train_df)
        ts_tab = extract_summary_features(test_df)
        X_tr = tr_tab[summary_cols].values
        y_tr = tr_tab["label"].values
        X_ts = ts_tab[summary_cols].values

        # Standardize for LR
        mean = X_tr.mean(axis=0)
        std = X_tr.std(axis=0) + 1e-6
        X_tr_norm = (X_tr - mean) / std
        X_ts_norm = (X_ts - mean) / std

        lr = LogisticRegression(class_weight="balanced", random_state=RANDOM_SEED, max_iter=1000)
        lr.fit(X_tr_norm, y_tr)
        preds_lr = lr.predict(X_ts_norm)
        all_results["LR"]["preds"].extend(preds_lr)
        all_results["LR"]["targets"].extend(y_ts)

        rf = RandomForestClassifier(n_estimators=50, max_depth=4, class_weight="balanced", random_state=RANDOM_SEED)
        rf.fit(X_tr, y_tr)
        preds_rf = rf.predict(X_ts)
        all_results["RF"]["preds"].extend(preds_rf)
        all_results["RF"]["targets"].extend(y_ts)

        # 3. Fresh LSTM Model Trained From Scratch for This Fold
        train_loader = DataLoader(SequenceEvalDataset(tr_records, SEQUENCE_DIR), batch_size=8, shuffle=True)
        val_loader = DataLoader(SequenceEvalDataset(vl_records, SEQUENCE_DIR), batch_size=8, shuffle=False)

        model = ExerciseLSTM(input_size=len(FEATURE_NAMES), hidden_size=64, num_layers=2, num_classes=2, dropout=0.3).to(device)
        class_counts = np.bincount(y_tr, minlength=2)
        class_weights = torch.tensor([len(y_tr) / (2.0 * max(c, 1)) for c in class_counts], dtype=torch.float32).to(device)
        criterion = nn.CrossEntropyLoss(weight=class_weights)
        optimizer = torch.optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-4)

        best_val_f1 = -1.0
        best_state = None
        best_ep = 0

        for ep in range(1, 41):
            model.train()
            for x, y in train_loader:
                x, y = x.to(device), y.to(device)
                optimizer.zero_grad()
                out = model(x)
                loss = criterion(out, y)
                loss.backward()
                optimizer.step()

            # Evaluate on inner validation set
            val_res = evaluate_records(model, vl_records, SEQUENCE_DIR, device)
            if ep >= 4 and val_res["macro_f1"] > best_val_f1:
                best_val_f1 = val_res["macro_f1"]
                best_state = copy.deepcopy(model.state_dict())
                best_ep = ep

        if best_state is not None:
            model.load_state_dict(best_state)

        lstm_fold_res = evaluate_records(model, ts_records, SEQUENCE_DIR, device)
        all_results["LSTM"]["preds"].extend(lstm_fold_res["predictions"])
        all_results["LSTM"]["targets"].extend(y_ts)

        fold_metrics["LSTM"].append({
            "held_out": held_out,
            "train_subjs": tr_subjs,
            "train_count": len(tr_records),
            "val_count": len(vl_records),
            "test_count": len(ts_records),
            "acc": lstm_fold_res["accuracy"],
            "bal_acc": lstm_fold_res["balanced_accuracy"],
            "macro_f1": lstm_fold_res["macro_f1"],
            "corr_rec": lstm_fold_res["correct_recall"],
            "inc_rec": lstm_fold_res["incorrect_recall"],
            "cm": lstm_fold_res["confusion_matrix"].tolist(),
        })

        print(f"\nFold [{held_out}] LSTM Evaluation:")
        print(f"  Accuracy           : {lstm_fold_res['accuracy']:.2f}% ({lstm_fold_res['correct_predictions']}/{lstm_fold_res['samples']})")
        print(f"  Balanced Accuracy  : {lstm_fold_res['balanced_accuracy']:.2f}%")
        print(f"  Macro-F1           : {lstm_fold_res['macro_f1']:.2f}%")
        print(f"  Correct Recall     : {lstm_fold_res['correct_recall']:.2f}%")
        print(f"  Incorrect Recall   : {lstm_fold_res['incorrect_recall']:.2f}%")
        cm = lstm_fold_res["confusion_matrix"]
        print("  Confusion Matrix   :")
        print("                      Pred Correct   Pred Incorrect")
        print(f"    True Correct (0)      {cm[0, 0]:^12}   {cm[0, 1]:^14}")
        print(f"    True Incorrect (1)    {cm[1, 0]:^12}   {cm[1, 1]:^14}")

    print("\n" + "=" * 80)
    print("STEP 8: AGGREGATE LOSO-CV BENCHMARK COMPARISON (ALL 150 REPETITIONS)")
    print("=" * 80)
    aggregate_table = []
    for model_name in ["Rule", "LR", "RF", "LSTM"]:
        y_true = np.array(all_results[model_name]["targets"])
        y_pred = np.array(all_results[model_name]["preds"])

        acc = accuracy_score(y_true, y_pred) * 100.0
        bal_acc = balanced_accuracy_score(y_true, y_pred) * 100.0
        f1 = f1_score(y_true, y_pred, average="macro", zero_division=0) * 100.0
        cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
        c_rec = (cm[0, 0] / (cm[0, 0] + cm[0, 1]) * 100.0) if (cm[0, 0] + cm[0, 1]) > 0 else 0.0
        i_rec = (cm[1, 1] / (cm[1, 0] + cm[1, 1]) * 100.0) if (cm[1, 0] + cm[1, 1]) > 0 else 0.0

        aggregate_table.append({
            "Model": model_name,
            "Accuracy": acc,
            "Balanced_Acc": bal_acc,
            "Macro_F1": f1,
            "Correct_Recall": c_rec,
            "Incorrect_Recall": i_rec,
            "CM": cm,
        })

        print(f"\nModel: [{model_name}]")
        print(f"  Aggregate Accuracy : {acc:.2f}% ({int((y_true == y_pred).sum())}/{len(y_true)})")
        print(f"  Balanced Accuracy  : {bal_acc:.2f}%")
        print(f"  Macro-F1           : {f1:.2f}%")
        print(f"  Correct Recall     : {c_rec:.2f}%")
        print(f"  Incorrect Recall   : {i_rec:.2f}%")
        print("  Confusion Matrix   :")
        print("                      Pred Correct   Pred Incorrect")
        print(f"    True Correct (0)      {cm[0, 0]:^12}   {cm[0, 1]:^14}")
        print(f"    True Incorrect (1)    {cm[1, 0]:^12}   {cm[1, 1]:^14}")

    return fold_metrics, aggregate_table


def step9_analyze_problem_shift():
    """Step 9: Analyze whether human annotation changed the problem."""
    df_raw = pd.read_csv(RAW_ANNOTATIONS_PATH)
    total_raw = len(df_raw)

    folder_dist = df_raw["folder_label"].str.lower().value_counts().to_dict()
    human_dist = df_raw["ground_truth_label"].str.lower().value_counts().to_dict()

    # Agreement across all 153
    folder_agreed = (df_raw["folder_label"].str.lower() == df_raw["ground_truth_label"].str.lower()).sum()
    auto_agreed = (df_raw["auto_label"].str.lower() == df_raw["ground_truth_label"].str.lower()).sum()

    print("\n" + "=" * 80)
    print("STEP 9: PROBLEM SHIFT ANALYSIS (FOLDER LABELS VS. HUMAN GROUND TRUTH)")
    print("=" * 80)
    print(f"Total evaluated repetitions in queue : {total_raw}")
    print(f"Folder label distribution            : Correct={folder_dist.get('correct', 0)}, Incorrect={folder_dist.get('incorrect', 0)}")
    print(f"Human ground-truth distribution      : Correct={human_dist.get('correct', 0)}, Incorrect={human_dist.get('incorrect', 0)}, Ambiguous={human_dist.get('ambiguous', 0)}")
    print(f"Folder -> Human agreement            : {folder_agreed} / {total_raw} ({folder_agreed / total_raw * 100:.1f}%) [Changed: {total_raw - folder_agreed}]")
    print(f"Auto   -> Human agreement            : {auto_agreed} / {total_raw} ({auto_agreed / total_raw * 100:.1f}%) [Changed: {total_raw - auto_agreed}]")
    print("=" * 80)


def step10_verify_mix_videos_excluded(clean_df: pd.DataFrame):
    """Step 10: Verify the 4 mixed videos are 100% excluded."""
    excluded_videos = [
        "20260825_121230.mp4",
        "20260825_135917.mp4",
        "VID20260825125415.mp4",
        "VID20260825125816.mp4",
    ]
    overlap = clean_df[clean_df["video_name"].isin(excluded_videos)]
    print("\n" + "=" * 80)
    print("STEP 10: EXCLUSION VERIFICATION (4 BOTH-HAND ASSISTED MIX VIDEOS)")
    print("=" * 80)
    print(f"Excluded mix videos checked          : {len(excluded_videos)}")
    print(f"Overlap found in clean dataset       : {len(overlap)}")
    if len(overlap) > 0:
        raise ValueError("CRITICAL ERROR: Mixed videos found in clean supervised training data!")
    print("Verified: 100% of both-hand assisted mix videos are strictly excluded.\n")


def main():
    set_seed(RANDOM_SEED)

    if not DATA_PATH.exists():
        print(f"Error: Clean dataset not found at {DATA_PATH}")
        return

    clean_df = pd.read_csv(DATA_PATH)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Active Evaluation Device: {device}")

    # Step 6
    step6_res = step6_evaluate_person3(clean_df, device)

    # Steps 7 & 8
    fold_metrics, agg_table = step7_and_8_loso_benchmark(clean_df, device)

    # Step 9
    step9_analyze_problem_shift()

    # Step 10
    step10_verify_mix_videos_excluded(clean_df)


if __name__ == "__main__":
    main()

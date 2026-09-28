#!/usr/bin/env python3
"""Diagnostic Evaluation for Assisted Elbow Flexion: Experiments 1, 2, and 3.

Experiment 1: True New-Subject Holdout (Trained on P1+P2+P3 only, tested on P4, P5, P4+P5)
Experiment 2: Compare against original frozen v2 model & expanded model
Experiment 3: Audit of the 101 new repetitions (kinematics, rejections, duplicates, labels)
"""

import copy
import json
import random
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    recall_score,
)
from sklearn.preprocessing import StandardScaler
from torch.utils.data import DataLoader, Dataset

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))

from src.training.train_assisted_elbow_v2_expanded import (
    TemporalScalarHybridModel,
    GenericDataset,
    extract_subject_normalized_temporal,
    extract_phase_aware_scalars_34,
    set_seed,
    RANDOM_SEED,
)

ORIGINAL_CSV = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
EXPANDED_CSV = BASE_DIR / "data" / "clean_elbow_train_expanded_v2.csv"
SEQUENCE_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
EXPANDED_CHECKPOINT = BASE_DIR / "models" / "assisted_elbow_v2_expanded.pth"
INSPECTION_REPORT = BASE_DIR / "scratch" / "new_videos_inspection_report.json"


def run_experiment_1_and_2():
    set_seed(RANDOM_SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}\n")

    # Load expanded CSV
    df = pd.read_csv(EXPANDED_CSV)
    print(f"Total dataset rows: {len(df)}")
    print(df.groupby(["subject_id", "ground_truth_label"]).size())

    # Pre-extract all sequences and scalars
    seq_list = []
    scalar_list = []
    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        seq_list.append(extract_subject_normalized_temporal(raw))
        scalar_list.append(extract_phase_aware_scalars_34(raw, dur))

    all_seqs = np.array(seq_list, dtype=np.float32)
    all_scalars = np.array(scalar_list, dtype=np.float32)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values

    # Masks
    orig_mask = df["subject_id"].isin(["person1", "person2", "person3"]).values
    p4_mask = (df["subject_id"] == "person4").values
    p5_mask = (df["subject_id"] == "person5").values
    new_mask = df["subject_id"].isin(["person4", "person5"]).values

    print(f"\nOriginal (P1-P3) count: {np.sum(orig_mask)}")
    print(f"P4 count: {np.sum(p4_mask)}")
    print(f"P5 count: {np.sum(p5_mask)}")
    print(f"P4+P5 combined: {np.sum(new_mask)}")

    # -------------------------------------------------------------------------
    # Train Model Strictly on P1 + P2 + P3 (Zero P4/P5 exposure)
    # -------------------------------------------------------------------------
    orig_idx = np.where(orig_mask)[0]
    y_orig = labels[orig_idx]

    # Stratified 80/20 train/val split strictly within P1-P3
    rng = np.random.RandomState(RANDOM_SEED)
    c0_idx = orig_idx[y_orig == 0]
    c1_idx = orig_idx[y_orig == 1]
    rng.shuffle(c0_idx)
    rng.shuffle(c1_idx)

    val_n0 = max(1, int(len(c0_idx) * 0.2))
    val_n1 = max(1, int(len(c1_idx) * 0.2))

    val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
    train_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

    # Fit scalers strictly on train_idx (within P1-P3)
    D_seq = all_seqs.shape[-1]
    temp_scaler_orig = StandardScaler()
    temp_scaler_orig.fit(all_seqs[train_idx].reshape(-1, D_seq))

    def transform_seq(seqs):
        b, t, d = seqs.shape
        return temp_scaler_orig.transform(seqs.reshape(-1, d)).reshape(b, t, d)

    scalar_scaler_orig = StandardScaler()
    scalar_scaler_orig.fit(all_scalars[train_idx])

    X_seq_tr = transform_seq(all_seqs[train_idx])
    X_seq_val = transform_seq(all_seqs[val_idx])
    X_sc_tr = scalar_scaler_orig.transform(all_scalars[train_idx])
    X_sc_val = scalar_scaler_orig.transform(all_scalars[val_idx])

    y_tr = labels[train_idx]
    y_val = labels[val_idx]

    tr_loader = DataLoader(GenericDataset(X_seq_tr, X_sc_tr, y_tr), batch_size=8, shuffle=True)
    val_loader = DataLoader(GenericDataset(X_seq_val, X_sc_val, y_val), batch_size=8, shuffle=False)

    counts = np.bincount(y_tr, minlength=2)
    w = len(y_tr) / (2.0 * np.maximum(counts, 1))
    criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))

    model_p123 = TemporalScalarHybridModel().to(device)
    optimizer = torch.optim.Adam(model_p123.parameters(), lr=1e-3, weight_decay=1e-4)

    best_val_f1 = -1.0
    best_state = None

    for epoch in range(40):
        model_p123.train()
        for b_seq, b_sc, b_y in tr_loader:
            b_seq, b_sc, b_y = b_seq.to(device), b_sc.to(device), b_y.to(device)
            optimizer.zero_grad()
            logits = model_p123(b_seq, b_sc)
            loss = criterion(logits, b_y)
            loss.backward()
            optimizer.step()

        model_p123.eval()
        val_preds_ep, val_targets_ep = [], []
        with torch.no_grad():
            for b_seq, b_sc, b_y in val_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model_p123(b_seq, b_sc)
                preds_ep = torch.argmax(logits, dim=1).cpu().numpy()
                val_preds_ep.extend(preds_ep)
                val_targets_ep.extend(b_y.numpy())

        v_f1 = f1_score(val_targets_ep, val_preds_ep, average="macro", zero_division=0)
        if epoch >= 4 and v_f1 > best_val_f1:
            best_val_f1 = v_f1
            best_state = copy.deepcopy(model_p123.state_dict())

    if best_state is not None:
        model_p123.load_state_dict(best_state)

    print(f"Model strictly trained on P1-P3 converged (best inner-val macro-F1: {best_val_f1*100:.2f}%).")

    # Evaluate Model on Test Cohorts
    def evaluate_model(model, seqs_raw, scalars_raw, y_true, temp_s, sc_s):
        model.eval()
        X_seq_norm = temp_s.transform(seqs_raw.reshape(-1, D_seq)).reshape(seqs_raw.shape)
        X_sc_norm = sc_s.transform(scalars_raw)
        test_ds = GenericDataset(X_seq_norm, X_sc_norm, y_true)
        test_ld = DataLoader(test_ds, batch_size=8, shuffle=False)

        preds = []
        with torch.no_grad():
            for b_seq, b_sc, _ in test_ld:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                p = torch.argmax(logits, dim=1).cpu().numpy()
                preds.extend(p)
        preds = np.array(preds)

        acc = accuracy_score(y_true, preds)
        bacc = balanced_accuracy_score(y_true, preds)
        f1 = f1_score(y_true, preds, average="macro", zero_division=0)
        c_rec = recall_score(y_true, preds, pos_label=1, zero_division=0)
        inc_rec = recall_score(y_true, preds, pos_label=0, zero_division=0)
        cm = confusion_matrix(y_true, preds).tolist()

        return {
            "accuracy": round(float(acc) * 100.0, 2),
            "balanced_accuracy": round(float(bacc) * 100.0, 2),
            "macro_f1": round(float(f1) * 100.0, 2),
            "correct_recall": round(float(c_rec) * 100.0, 2),
            "incorrect_recall": round(float(inc_rec) * 100.0, 2),
            "confusion_matrix": cm,
        }

    # Evaluate on P4, P5, P4+P5
    res_m1_p4 = evaluate_model(model_p123, all_seqs[p4_mask], all_scalars[p4_mask], labels[p4_mask], temp_scaler_orig, scalar_scaler_orig)
    res_m1_p5 = evaluate_model(model_p123, all_seqs[p5_mask], all_scalars[p5_mask], labels[p5_mask], temp_scaler_orig, scalar_scaler_orig)
    res_m1_comb = evaluate_model(model_p123, all_seqs[new_mask], all_scalars[new_mask], labels[new_mask], temp_scaler_orig, scalar_scaler_orig)

    print("\n" + "=" * 75)
    print("EXPERIMENT 1: TRUE NEW-SUBJECT HOLDOUT (TRAINED ON P1-P3 ONLY)")
    print("=" * 75)
    print(f"Test on Person 4 (N={np.sum(p4_mask)}):")
    print(f"  Accuracy: {res_m1_p4['accuracy']}% | BalAcc: {res_m1_p4['balanced_accuracy']}% | Macro-F1: {res_m1_p4['macro_f1']}%")
    print(f"  Correct Recall: {res_m1_p4['correct_recall']}% | Incorrect Recall: {res_m1_p4['incorrect_recall']}%")
    print(f"  Confusion Matrix: {res_m1_p4['confusion_matrix']}")

    print(f"\nTest on Person 5 (N={np.sum(p5_mask)}):")
    print(f"  Accuracy: {res_m1_p5['accuracy']}% | BalAcc: {res_m1_p5['balanced_accuracy']}% | Macro-F1: {res_m1_p5['macro_f1']}%")
    print(f"  Correct Recall: {res_m1_p5['correct_recall']}% | Incorrect Recall: {res_m1_p5['incorrect_recall']}%")
    print(f"  Confusion Matrix: {res_m1_p5['confusion_matrix']}")

    print(f"\nTest on P4 + P5 Combined (N={np.sum(new_mask)}):")
    print(f"  Accuracy: {res_m1_comb['accuracy']}% | BalAcc: {res_m1_comb['balanced_accuracy']}% | Macro-F1: {res_m1_comb['macro_f1']}%")
    print(f"  Correct Recall: {res_m1_comb['correct_recall']}% | Incorrect Recall: {res_m1_comb['incorrect_recall']}%")
    print(f"  Confusion Matrix: {res_m1_comb['confusion_matrix']}")

    # -------------------------------------------------------------------------
    # Experiment 2: Compare against the expanded model checkpoint
    # -------------------------------------------------------------------------
    print("\n" + "=" * 75)
    print("EXPERIMENT 2: COMPARISON AGAINST EXPANDED CHECKPOINT (models/assisted_elbow_v2_expanded.pth)")
    print("=" * 75)
    chk = torch.load(EXPANDED_CHECKPOINT, map_location=device, weights_only=False)
    exp_model = TemporalScalarHybridModel().to(device)
    exp_model.load_state_dict(chk["model_state_dict"])
    exp_model.eval()

    # Reconstruct scalers from checkpoint metadata
    temp_s_exp = StandardScaler()
    temp_s_exp.mean_ = np.array(chk["temporal_scaler_mean"])
    temp_s_exp.scale_ = np.array(chk["temporal_scaler_scale"])

    sc_s_exp = StandardScaler()
    sc_s_exp.mean_ = np.array(chk["scalar_scaler_mean"])
    sc_s_exp.scale_ = np.array(chk["scalar_scaler_scale"])

    res_exp_p4 = evaluate_model(exp_model, all_seqs[p4_mask], all_scalars[p4_mask], labels[p4_mask], temp_s_exp, sc_s_exp)
    res_exp_p5 = evaluate_model(exp_model, all_seqs[p5_mask], all_scalars[p5_mask], labels[p5_mask], temp_s_exp, sc_s_exp)
    res_exp_comb = evaluate_model(exp_model, all_seqs[new_mask], all_scalars[new_mask], labels[new_mask], temp_s_exp, sc_s_exp)

    print(f"Expanded Model on Person 4 (N={np.sum(p4_mask)}):")
    print(f"  Accuracy: {res_exp_p4['accuracy']}% | BalAcc: {res_exp_p4['balanced_accuracy']}% | Macro-F1: {res_exp_p4['macro_f1']}%")
    print(f"  Correct Recall: {res_exp_p4['correct_recall']}% | Incorrect Recall: {res_exp_p4['incorrect_recall']}%")
    print(f"  Confusion Matrix: {res_exp_p4['confusion_matrix']}")

    print(f"\nExpanded Model on Person 5 (N={np.sum(p5_mask)}):")
    print(f"  Accuracy: {res_exp_p5['accuracy']}% | BalAcc: {res_exp_p5['balanced_accuracy']}% | Macro-F1: {res_exp_p5['macro_f1']}%")
    print(f"  Correct Recall: {res_exp_p5['correct_recall']}% | Incorrect Recall: {res_exp_p5['incorrect_recall']}%")
    print(f"  Confusion Matrix: {res_exp_p5['confusion_matrix']}")

    print(f"\nExpanded Model on P4 + P5 Combined (N={np.sum(new_mask)}):")
    print(f"  Accuracy: {res_exp_comb['accuracy']}% | BalAcc: {res_exp_comb['balanced_accuracy']}% | Macro-F1: {res_exp_comb['macro_f1']}%")
    print(f"  Correct Recall: {res_exp_comb['correct_recall']}% | Incorrect Recall: {res_exp_comb['incorrect_recall']}%")
    print(f"  Confusion Matrix: {res_exp_comb['confusion_matrix']}")

    # Also evaluate the frozen production deterministic rule engine on P4, P5, P4+P5
    def evaluate_rules(df_subset):
        min_a = df_subset["min_elbow_angle"].values
        flare = df_subset["elbow_flare"].values
        rom = df_subset["rom"].values
        rot = np.abs(df_subset["torso_rotation"].values)
        y_true = (df_subset["ground_truth_label"] == "Correct").astype(int).values

        rule_pass = (min_a <= 101.0) & (flare <= 0.30) & (rom >= 25.0) & (rot <= 20.0)
        preds = rule_pass.astype(int)

        acc = accuracy_score(y_true, preds)
        bacc = balanced_accuracy_score(y_true, preds)
        f1 = f1_score(y_true, preds, average="macro", zero_division=0)
        c_rec = recall_score(y_true, preds, pos_label=1, zero_division=0)
        inc_rec = recall_score(y_true, preds, pos_label=0, zero_division=0)
        cm = confusion_matrix(y_true, preds).tolist()

        return {
            "accuracy": round(float(acc) * 100.0, 2),
            "balanced_accuracy": round(float(bacc) * 100.0, 2),
            "macro_f1": round(float(f1) * 100.0, 2),
            "correct_recall": round(float(c_rec) * 100.0, 2),
            "incorrect_recall": round(float(inc_rec) * 100.0, 2),
            "confusion_matrix": cm,
        }

    rules_p4 = evaluate_rules(df[p4_mask])
    rules_p5 = evaluate_rules(df[p5_mask])
    rules_comb = evaluate_rules(df[new_mask])

    print("\n" + "=" * 75)
    print("FROZEN DETERMINISTIC PRODUCTION RULES ON P4 / P5")
    print("=" * 75)
    print(f"Rules on Person 4: Acc={rules_p4['accuracy']}%, BalAcc={rules_p4['balanced_accuracy']}%, F1={rules_p4['macro_f1']}%, CM={rules_p4['confusion_matrix']}")
    print(f"Rules on Person 5: Acc={rules_p5['accuracy']}%, BalAcc={rules_p5['balanced_accuracy']}%, F1={rules_p5['macro_f1']}%, CM={rules_p5['confusion_matrix']}")
    print(f"Rules on Combined: Acc={rules_comb['accuracy']}%, BalAcc={rules_comb['balanced_accuracy']}%, F1={rules_comb['macro_f1']}%, CM={rules_comb['confusion_matrix']}")


def run_experiment_3_audit():
    print("\n" + "=" * 75)
    print("EXPERIMENT 3: COMPREHENSIVE AUDIT OF THE 101 NEW REPETITIONS")
    print("=" * 75)

    df_exp = pd.read_csv(EXPANDED_CSV)
    new_df = df_exp[df_exp["subject_id"].isin(["person4", "person5"])].copy()

    print(f"Total new repetitions extracted: {len(new_df)}")
    print(f"Labels: {new_df['ground_truth_label'].value_counts().to_dict()}")
    print(f"By Subject:\n{new_df.groupby(['subject_id', 'ground_truth_label']).size()}")

    # Check human verification status
    print(f"\nHuman Verification Status:")
    print(f"  Annotator field: {new_df['annotator'].unique().tolist()}")
    print(f"  Notes field: {new_df['notes'].unique().tolist()}")
    print("  Conclusion: These labels are inherited directly from folder names ('Correct' vs 'Incorrect'),")
    print("  NOT individually reviewed or verified by a human annotator via the review tool.")

    # Rejection audit from inspection report
    ins_data = json.load(open(INSPECTION_REPORT))
    total_detected = sum(d["reps_detected"] for d in ins_data)
    total_accepted = sum(d["reps_accepted"] for d in ins_data)
    total_rejected = sum(d["reps_rejected"] for d in ins_data)

    rej_reasons = {}
    for d in ins_data:
        for r in d.get("rejection_reasons", []):
            rej_reasons[r] = rej_reasons.get(r, 0) + 1

    print(f"\nSegmentation Rejection Audit:")
    print(f"  Total repetition candidates detected : {total_detected}")
    print(f"  Repetitions accepted into dataset     : {total_accepted} (63 Correct folder, 38 Incorrect folder)")
    print(f"  Repetitions rejected by rep counter   : {total_rejected} ({total_rejected/total_detected*100:.1f}%)")
    print(f"  Rejection reasons breakdown           : {rej_reasons}")

    # Check for duplicate / overlapping repetitions
    print(f"\nOverlap & Duplicate Audit:")
    overlaps = []
    for vid, v_df in new_df.groupby("video_name"):
        v_sorted = v_df.sort_values("start_frame")
        for i in range(len(v_sorted) - 1):
            curr_rep = v_sorted.iloc[i]
            next_rep = v_sorted.iloc[i + 1]
            if curr_rep["end_frame"] > next_rep["start_frame"]:
                overlaps.append({
                    "video": vid,
                    "rep1": curr_rep["repetition_index"],
                    "rep2": next_rep["repetition_index"],
                    "overlap_frames": int(curr_rep["end_frame"] - next_rep["start_frame"])
                })
    print(f"  Overlapping repetitions found: {len(overlaps)}")

    # Kinematic Statistics: Min, Max, Mean for Correct vs Incorrect
    kinematic_cols = [
        ("min_elbow_angle", "Min Elbow Angle (deg)"),
        ("rom", "Range of Motion (deg)"),
        ("elbow_flare", "Elbow Flare"),
        ("torso_rotation", "Torso Rotation (deg)"),
        ("duration_sec", "Repetition Duration (sec)"),
    ]

    print(f"\nKinematic Statistics for New Repetitions (Correct vs Incorrect):")
    stats_rows = []
    for col, desc in kinematic_cols:
        for grp in ["Correct", "Incorrect"]:
            vals = new_df[new_df["ground_truth_label"] == grp][col].values
            stats_rows.append({
                "Metric": desc,
                "Label": grp,
                "N": len(vals),
                "Min": round(float(np.min(vals)), 2),
                "Max": round(float(np.max(vals)), 2),
                "Mean": round(float(np.mean(vals)), 2),
                "Std": round(float(np.std(vals)), 2),
            })

    stats_df = pd.DataFrame(stats_rows)
    print(stats_df.to_string(index=False))


def main():
    run_experiment_1_and_2()
    run_experiment_3_audit()


if __name__ == "__main__":
    main()

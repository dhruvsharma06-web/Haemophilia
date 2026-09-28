import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase8a_torso_rotation_results.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

RANDOM_SEED = 42
THETA_LIST = [10.0, 12.0, 14.0, 15.0, 16.0, 18.0, 20.0]

def run_phase8a_evaluation():
    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    min_a = df["min_elbow_angle"].values
    flare = df["elbow_flare"].values
    rom = df["rom"].values
    tilt = df["torso_tilt"].values
    abs_rot = df["torso_rotation"].abs().values

    # Base production rules
    # 1. min_elbow_angle <= 101.0°
    # 2. elbow_flare <= 0.30
    # 3. rom >= 25.0°
    # 4. torso_tilt <= 5.0° (inert)
    base_3 = (min_a <= 101.0) & (flare <= 0.30) & (rom >= 25.0)
    base_preds = (base_3 & (tilt <= 5.0)).astype(int)

    base_acc = float(accuracy_score(labels, base_preds))
    base_bal = float(balanced_accuracy_score(labels, base_preds))
    base_f1 = float(f1_score(labels, base_preds, average="macro", zero_division=0))
    base_cr = float(recall_score(labels, base_preds, pos_label=1, zero_division=0))
    base_ir = float(recall_score(labels, base_preds, pos_label=0, zero_division=0))
    base_cm = confusion_matrix(labels, base_preds).tolist()

    sub_bals_base = []
    base_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        s_acc = float(accuracy_score(labels[m], base_preds[m]))
        s_bal = float(balanced_accuracy_score(labels[m], base_preds[m]))
        s_f1 = float(f1_score(labels[m], base_preds[m], average="macro", zero_division=0))
        s_cr = float(recall_score(labels[m], base_preds[m], pos_label=1, zero_division=0))
        s_ir = float(recall_score(labels[m], base_preds[m], pos_label=0, zero_division=0))
        s_cm = confusion_matrix(labels[m], base_preds[m]).tolist()
        sub_bals_base.append(s_bal)
        base_per_sub[sub] = {
            "accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1,
            "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm
        }

    print("=" * 115)
    print("PHASE 8A: EVALUATION OF TRANSVERSE TORSO-ROTATION CRITERION")
    print(f"Dataset: {len(df)} clean repetitions across {len(unique_subjects)} subjects")
    print("Baseline Evaluator: min_elbow_angle <= 101.0°, flare <= 0.30, rom >= 25.0°, torso_tilt <= 5.0°")
    print(f"Baseline: Acc={base_acc*100:.2f}%, BalAcc={base_bal*100:.2f}%, MacroF1={base_f1*100:.2f}%, CM={base_cm}")
    print("=" * 115)

    # 1. Descriptive Fixed-Threshold Sweep
    print("\n" + "=" * 115)
    print("PART 1: DESCRIPTIVE FIXED-THRESHOLD SWEEP (OVERALL 3-FOLD LOSO)")
    print("=" * 115)
    header = f"{'Threshold':<14} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Fold BalAcc Mean±Std':<22} | {'FC Caught':<9} | {'Cor Rej':<7} | {'Confusion Matrix'}"
    print(header)
    print("-" * 135)

    sweep_results = {}

    # The 11 False Corrects of baseline
    base_fc_mask = (labels == 0) & (base_preds == 1)

    for th in THETA_LIST:
        pred_th = (base_3 & (abs_rot <= th)).astype(int)
        
        acc = float(accuracy_score(labels, pred_th))
        bal = float(balanced_accuracy_score(labels, pred_th))
        f1 = float(f1_score(labels, pred_th, average="macro", zero_division=0))
        cr = float(recall_score(labels, pred_th, pos_label=1, zero_division=0))
        ir = float(recall_score(labels, pred_th, pos_label=0, zero_division=0))
        cm = confusion_matrix(labels, pred_th).tolist()

        sub_bals = []
        per_sub = {}
        for sub in unique_subjects:
            m = (subjects == sub)
            s_acc = float(accuracy_score(labels[m], pred_th[m]))
            s_bal = float(balanced_accuracy_score(labels[m], pred_th[m]))
            s_f1 = float(f1_score(labels[m], pred_th[m], average="macro", zero_division=0))
            s_cr = float(recall_score(labels[m], pred_th[m], pos_label=1, zero_division=0))
            s_ir = float(recall_score(labels[m], pred_th[m], pos_label=0, zero_division=0))
            s_cm = confusion_matrix(labels[m], pred_th[m]).tolist()
            sub_bals.append(s_bal)
            per_sub[sub] = {
                "accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1,
                "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm
            }

        mean_bal = float(np.mean(sub_bals))
        std_bal = float(np.std(sub_bals))
        m_s_str = f"{mean_bal*100:.2f}% ± {std_bal*100:.2f}%"

        # 11 FC caught
        fc_caught = int(np.sum(base_fc_mask & (pred_th == 0)))
        # Correct repetitions newly rejected
        cor_rej = int(np.sum((labels == 1) & (base_preds == 1) & (pred_th == 0)))

        th_key = f"theta_{th}deg"
        print(f"{th_key:<14} | {acc*100:6.2f}% | {bal*100:6.2f}% | {f1*100:6.2f}% | {cr*100:6.2f}% | {ir*100:6.2f}% | {m_s_str:<22} | {fc_caught:<9} | {cor_rej:<7} | {str(cm)}")

        # Specific changed error cases
        changed_mask = (pred_th != base_preds)
        changed_reps = []
        for c_idx in np.where(changed_mask)[0]:
            r = df.iloc[c_idx]
            changed_reps.append({
                "index": int(c_idx),
                "subject": str(r["subject_id"]),
                "video": str(r["video_name"]),
                "rep": int(r["repetition_index"]),
                "ground_truth": str(r["ground_truth_label"]),
                "base_pred": "Correct" if base_preds[c_idx] == 1 else "Incorrect",
                "new_pred": "Correct" if pred_th[c_idx] == 1 else "Incorrect",
                "abs_torso_rotation": float(abs_rot[c_idx]),
                "error_tags": str(r.get("error_tags", "")),
                "notes": str(r.get("notes", "")),
                "status_change": "Helped (False Correct Caught)" if (labels[c_idx] == 0 and pred_th[c_idx] == 0) else "Hurt (Correct Rejected)"
            })

        sweep_results[th_key] = {
            "theta_rotation": th,
            "accuracy": acc,
            "balanced_accuracy": bal,
            "macro_f1": f1,
            "correct_recall": cr,
            "incorrect_recall": ir,
            "confusion_matrix": cm,
            "fold_balacc_mean": mean_bal,
            "fold_balacc_std": std_bal,
            "fc_caught_count": fc_caught,
            "correct_newly_rejected_count": cor_rej,
            "per_subject": per_sub,
            "changed_repetitions": changed_reps
        }

    # Per-subject detailed table for key thresholds
    print("\n" + "=" * 115)
    print("PER-SUBJECT BREAKDOWN ACROSS THRESHOLDS")
    print("=" * 115)
    for sub in unique_subjects:
        print(f"\n--- {sub.upper()} ---")
        base_s = base_per_sub[sub]
        print(f"  {'Baseline (tilt<=5°)':<20}: Acc={base_s['accuracy']*100:.2f}%, BalAcc={base_s['balanced_accuracy']*100:.2f}%, F1={base_s['macro_f1']*100:.2f}%, CorRec={base_s['correct_recall']*100:.2f}%, IncRec={base_s['incorrect_recall']*100:.2f}%, CM={base_s['confusion_matrix']}")
        for th in [10.0, 12.0, 15.0, 18.0, 20.0]:
            th_s = sweep_results[f"theta_{th}deg"]["per_subject"][sub]
            print(f"  {f'theta={th}°':<20}: Acc={th_s['accuracy']*100:.2f}%, BalAcc={th_s['balanced_accuracy']*100:.2f}%, F1={th_s['macro_f1']*100:.2f}%, CorRec={th_s['correct_recall']*100:.2f}%, IncRec={th_s['incorrect_recall']*100:.2f}%, CM={th_s['confusion_matrix']}")

    # 2. Separate Nested LOSO Experiment
    print("\n" + "=" * 115)
    print("PART 2: SEPARATE NESTED LOSO EXPERIMENT (INNER-SPLIT SELECTION)")
    print("=" * 115)
    nested_preds_bal = np.zeros(len(df), dtype=int)
    nested_preds_f1 = np.zeros(len(df), dtype=int)
    nested_fold_details = {}

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        tr_indices = np.where(~test_mask)[0]
        test_idx = np.where(test_mask)[0]
        y_tr = labels[tr_indices]

        # Inner validation split (20% stratified from training fold)
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_tr == 0]
        c1_idx = tr_indices[y_tr == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))
        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Grid search over THETA_LIST on val_idx
        best_bal = -1.0
        best_bal_th = None
        best_f1 = -1.0
        best_f1_th = None

        val_bal_scores = {}
        val_f1_scores = {}

        for th in THETA_LIST:
            p_val = (base_3[val_idx] & (abs_rot[val_idx] <= th)).astype(int)
            bal_v = balanced_accuracy_score(labels[val_idx], p_val)
            f1_v = f1_score(labels[val_idx], p_val, average="macro", zero_division=0)
            val_bal_scores[th] = float(bal_v)
            val_f1_scores[th] = float(f1_v)

            # Tie break rule: highest BalAcc on actual_tr, then highest theta (least restrictive)
            if bal_v > best_bal:
                best_bal = bal_v
                best_bal_th = th
            elif np.isclose(bal_v, best_bal):
                # evaluate on actual_tr_idx
                p_tr_cand = (base_3[actual_tr_idx] & (abs_rot[actual_tr_idx] <= th)).astype(int)
                p_tr_best = (base_3[actual_tr_idx] & (abs_rot[actual_tr_idx] <= best_bal_th)).astype(int)
                tr_bal_cand = balanced_accuracy_score(labels[actual_tr_idx], p_tr_cand)
                tr_bal_best = balanced_accuracy_score(labels[actual_tr_idx], p_tr_best)
                if tr_bal_cand > tr_bal_best:
                    best_bal = bal_v
                    best_bal_th = th
                elif np.isclose(tr_bal_cand, tr_bal_best):
                    if th > best_bal_th: # choose larger theta (more conservative / less false alarms)
                        best_bal_th = th

            if f1_v > best_f1:
                best_f1 = f1_v
                best_f1_th = th
            elif np.isclose(f1_v, best_f1):
                p_tr_cand = (base_3[actual_tr_idx] & (abs_rot[actual_tr_idx] <= th)).astype(int)
                p_tr_best = (base_3[actual_tr_idx] & (abs_rot[actual_tr_idx] <= best_f1_th)).astype(int)
                tr_f1_cand = f1_score(labels[actual_tr_idx], p_tr_cand, average="macro", zero_division=0)
                tr_f1_best = f1_score(labels[actual_tr_idx], p_tr_best, average="macro", zero_division=0)
                if tr_f1_cand > tr_f1_best:
                    best_f1 = f1_v
                    best_f1_th = th
                elif np.isclose(tr_f1_cand, tr_f1_best):
                    if th > best_f1_th:
                        best_f1_th = th

        # Apply to held-out test subject
        nested_preds_bal[test_idx] = (base_3[test_idx] & (abs_rot[test_idx] <= best_bal_th)).astype(int)
        nested_preds_f1[test_idx] = (base_3[test_idx] & (abs_rot[test_idx] <= best_f1_th)).astype(int)

        nested_fold_details[test_sub] = {
            "selected_theta_balacc": best_bal_th,
            "selected_theta_macrof1": best_f1_th,
            "val_balacc_max": best_bal,
            "val_macrof1_max": best_f1,
            "val_bal_scores": val_bal_scores,
            "val_f1_scores": val_f1_scores
        }
        print(f"Test Subject {test_sub}: Selected theta (BalAcc) = {best_bal_th}°, Selected theta (MacroF1) = {best_f1_th}°")

    # Evaluate nested predictions
    nested_acc = float(accuracy_score(labels, nested_preds_bal))
    nested_bal = float(balanced_accuracy_score(labels, nested_preds_bal))
    nested_f1 = float(f1_score(labels, nested_preds_bal, average="macro", zero_division=0))
    nested_cr = float(recall_score(labels, nested_preds_bal, pos_label=1, zero_division=0))
    nested_ir = float(recall_score(labels, nested_preds_bal, pos_label=0, zero_division=0))
    nested_cm = confusion_matrix(labels, nested_preds_bal).tolist()

    sub_bals_nested = []
    nested_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        s_acc = float(accuracy_score(labels[m], nested_preds_bal[m]))
        s_bal = float(balanced_accuracy_score(labels[m], nested_preds_bal[m]))
        s_f1 = float(f1_score(labels[m], nested_preds_bal[m], average="macro", zero_division=0))
        s_cr = float(recall_score(labels[m], nested_preds_bal[m], pos_label=1, zero_division=0))
        s_ir = float(recall_score(labels[m], nested_preds_bal[m], pos_label=0, zero_division=0))
        s_cm = confusion_matrix(labels[m], nested_preds_bal[m]).tolist()
        sub_bals_nested.append(s_bal)
        nested_per_sub[sub] = {
            "accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1,
            "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm
        }

    m_s_nested = f"{np.mean(sub_bals_nested)*100:.2f}% +/- {np.std(sub_bals_nested)*100:.2f}%"

    print("\nNESTED LOSO RESULTS (INNER SELECTION APPLIED TO TEST):")
    print(f"Accuracy         : {nested_acc*100:.2f}% (vs {base_acc*100:.2f}% baseline)")
    print(f"Balanced Accuracy: {nested_bal*100:.2f}% (vs {base_bal*100:.2f}% baseline) [Diff = +{(nested_bal - base_bal)*100:.2f}%]")
    print(f"Macro-F1         : {nested_f1*100:.2f}% (vs {base_f1*100:.2f}% baseline) [Diff = +{(nested_f1 - base_f1)*100:.2f}%]")
    print(f"Correct Recall   : {nested_cr*100:.2f}% (vs {base_cr*100:.2f}% baseline)")
    print(f"Incorrect Recall : {nested_ir*100:.2f}% (vs {base_ir*100:.2f}% baseline) [Diff = +{(nested_ir - base_ir)*100:.2f}%]")
    m_s_base = f"{np.mean(sub_bals_base)*100:.2f}% +/- {np.std(sub_bals_base)*100:.2f}%"
    print(f"Fold BalAcc      : {m_s_nested} (vs {m_s_base})")
    print(f"Confusion Matrix : {nested_cm} (vs {base_cm})")

    # Detailed audit of the 11 False Corrects
    print("\n" + "=" * 115)
    print("DETAILED AUDIT OF THE 11 BASELINE FALSE CORRECTS UNDER THETA=18 deg / 20 deg")
    print("=" * 115)
    for idx in np.where(base_fc_mask)[0]:
        r = df.iloc[idx]
        rot = abs_rot[idx]
        status_18 = "CAUGHT (Incorrect)" if rot > 18.0 else "PASSED (Still Missed)"
        print(f"Rep: {r['subject_id']} | {r['video_name']} #{r['repetition_index']} | Tag: {r['error_tags']} | |rot| = {rot:.1f} deg -> Under theta=18 deg: {status_18}")

    output_data = {
        "baseline": {
            "accuracy": base_acc, "balanced_accuracy": base_bal, "macro_f1": base_f1,
            "correct_recall": base_cr, "incorrect_recall": base_ir, "confusion_matrix": base_cm,
            "fold_balacc_mean": float(np.mean(sub_bals_base)), "fold_balacc_std": float(np.std(sub_bals_base)),
            "per_subject": base_per_sub
        },
        "descriptive_sweep": sweep_results,
        "nested_experiment": {
            "accuracy": nested_acc, "balanced_accuracy": nested_bal, "macro_f1": nested_f1,
            "correct_recall": nested_cr, "incorrect_recall": nested_ir, "confusion_matrix": nested_cm,
            "fold_balacc_mean": float(np.mean(sub_bals_nested)), "fold_balacc_std": float(np.std(sub_bals_nested)),
            "per_subject": nested_per_sub,
            "fold_details": nested_fold_details
        }
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nSaved Phase 8A results to {OUTPUT_JSON}")

if __name__ == "__main__":
    run_phase8a_evaluation()

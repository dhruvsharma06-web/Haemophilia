import sys
import copy
import json
import itertools
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase6_nested_rules_results.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

RANDOM_SEED = 42
BASE_THRESH = np.array([101.0, 0.30, 25.0, 5.0], dtype=np.float32)
PARAM_NAMES = ["min_elbow_angle", "elbow_flare", "rom", "torso_tilt"]

# Grid space defined by user prompt
grid_min_angle = np.array([97.0, 98.0, 99.0, 100.0, 101.0, 102.0, 103.0, 104.0], dtype=np.float32)
grid_flare = np.array([0.26, 0.27, 0.28, 0.29, 0.30, 0.31, 0.32, 0.33, 0.34], dtype=np.float32)
grid_rom = np.array([20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 35.0], dtype=np.float32)
grid_tilt = np.array([4.0, 5.0, 6.0, 7.0], dtype=np.float32)

all_combos = list(itertools.product(grid_min_angle, grid_flare, grid_rom, grid_tilt))
combos_arr = np.array(all_combos, dtype=np.float32) # (2016, 4)

def evaluate_predictions_vectorized(combos, indices, df, labels):
    sub_min_a = df["min_elbow_angle"].values[indices].astype(np.float32)
    sub_flare = df["elbow_flare"].values[indices].astype(np.float32)
    sub_rom = df["rom"].values[indices].astype(np.float32)
    sub_tilt = df["torso_tilt"].values[indices].astype(np.float32)
    y = labels[indices]
    
    cond1 = sub_min_a[None, :] <= combos[:, 0:1]
    cond2 = sub_flare[None, :] <= combos[:, 1:2]
    cond3 = sub_rom[None, :] >= combos[:, 2:3]
    cond4 = sub_tilt[None, :] <= combos[:, 3:4]
    
    preds = (cond1 & cond2 & cond3 & cond4) # (K, N) bool
    
    y_pos = (y == 1)[None, :]
    y_neg = (y == 0)[None, :]
    
    tp = np.sum(preds & y_pos, axis=1)
    fn = np.sum((~preds) & y_pos, axis=1)
    tn = np.sum((~preds) & y_neg, axis=1)
    fp = np.sum(preds & y_neg, axis=1)
    
    acc = (tp + tn) / len(y)
    
    rec_pos = np.where(tp + fn > 0, tp / np.maximum(tp + fn, 1), 0.0)
    rec_neg = np.where(tn + fp > 0, tn / np.maximum(tn + fp, 1), 0.0)
    bal_acc = 0.5 * (rec_pos + rec_neg)
    
    prec_pos = np.where(tp + fp > 0, tp / np.maximum(tp + fp, 1), 0.0)
    prec_neg = np.where(tn + fn > 0, tn / np.maximum(tn + fn, 1), 0.0)
    
    f1_pos = np.where(prec_pos + rec_pos > 0, 2 * prec_pos * rec_pos / np.maximum(prec_pos + rec_pos, 1e-9), 0.0)
    f1_neg = np.where(prec_neg + rec_neg > 0, 2 * prec_neg * rec_neg / np.maximum(prec_neg + rec_neg, 1e-9), 0.0)
    macro_f1 = 0.5 * (f1_pos + f1_neg)
    
    return bal_acc, macro_f1, acc, rec_pos, rec_neg, preds

def run_phase6_evaluation():
    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))
    
    print("=" * 110)
    print("PHASE 6: NESTED LOSO OPTIMIZATION OF DETERMINISTIC BIOMECHANICAL RULES")
    print(f"Dataset: {len(df)} clean repetitions across {len(unique_subjects)} subjects")
    print(f"Base Production Thresholds: min_elbow_angle <= 101.0°, flare <= 0.30, rom >= 25.0°, torso_tilt <= 5.0°")
    print(f"Search Grid Size: {len(combos_arr)} candidate threshold combinations")
    print("=" * 110)

    # Containers for predictions
    preds_dict = {
        "A_fixed_baseline": np.zeros(len(df), dtype=int),
        "B_opt_bal_acc": np.zeros(len(df), dtype=int),
        "C_opt_macro_f1": np.zeros(len(df), dtype=int)
    }
    
    selected_thresholds = {
        "B_opt_bal_acc": {},
        "C_opt_macro_f1": {}
    }
    
    fold_details = {
        sub: {} for sub in unique_subjects
    }
    
    scale = np.array([10.0, 0.1, 10.0, 2.0], dtype=np.float32)
    dist_to_base = np.sum(((combos_arr - BASE_THRESH) / scale) ** 2, axis=1)

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        tr_indices = np.where(~test_mask)[0]
        test_idx = np.where(test_mask)[0]
        y_tr = labels[tr_indices]
        y_te = labels[test_idx]

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

        # Evaluate Condition A (Fixed Production Rules) on test
        _, _, _, _, _, p_a = evaluate_predictions_vectorized(BASE_THRESH[None, :], test_idx, df, labels)
        preds_dict["A_fixed_baseline"][test_idx] = p_a[0].astype(int)

        # Optimize Condition B & C using ONLY inner validation split
        val_bal, val_f1, val_acc, _, _, _ = evaluate_predictions_vectorized(combos_arr, val_idx, df, labels)
        tr_bal, tr_f1, _, _, _, _ = evaluate_predictions_vectorized(combos_arr, actual_tr_idx, df, labels)

        # Baseline on inner val
        b_val_bal, b_val_f1, _, _, _, _ = evaluate_predictions_vectorized(BASE_THRESH[None, :], val_idx, df, labels)

        # Condition B: Optimize BalAcc
        max_val_bal = np.max(val_bal)
        cand_b_indices = np.where(np.isclose(val_bal, max_val_bal))[0]
        # Tie-break: secondary Macro-F1 on val, then BalAcc on actual_tr, then closest to BASE_THRESH
        sorted_cand_b = sorted(cand_b_indices, key=lambda i: (-val_f1[i], -tr_bal[i], dist_to_base[i]))
        best_b_idx = sorted_cand_b[0]
        chosen_b_th = combos_arr[best_b_idx]
        selected_thresholds["B_opt_bal_acc"][test_sub] = [float(x) for x in chosen_b_th]

        _, _, _, _, _, p_b = evaluate_predictions_vectorized(chosen_b_th[None, :], test_idx, df, labels)
        preds_dict["B_opt_bal_acc"][test_idx] = p_b[0].astype(int)

        # Condition C: Optimize Macro-F1
        max_val_f1 = np.max(val_f1)
        cand_c_indices = np.where(np.isclose(val_f1, max_val_f1))[0]
        sorted_cand_c = sorted(cand_c_indices, key=lambda i: (-val_bal[i], -tr_f1[i], dist_to_base[i]))
        best_c_idx = sorted_cand_c[0]
        chosen_c_th = combos_arr[best_c_idx]
        selected_thresholds["C_opt_macro_f1"][test_sub] = [float(x) for x in chosen_c_th]

        _, _, _, _, _, p_c = evaluate_predictions_vectorized(chosen_c_th[None, :], test_idx, df, labels)
        preds_dict["C_opt_macro_f1"][test_idx] = p_c[0].astype(int)

        fold_details[test_sub] = {
            "n_test": int(len(test_idx)),
            "n_train": int(len(tr_indices)),
            "n_val": int(len(val_idx)),
            "val_base_balacc": float(b_val_bal[0]),
            "val_base_macrof1": float(b_val_f1[0]),
            "val_best_balacc": float(max_val_bal),
            "val_best_macrof1": float(max_val_f1),
            "n_ties_balacc": int(len(cand_b_indices)),
            "n_ties_macrof1": int(len(cand_c_indices)),
            "chosen_thresh_balacc": [float(x) for x in chosen_b_th],
            "chosen_thresh_macrof1": [float(x) for x in chosen_c_th]
        }

    # Print summary tables
    print("\n" + "=" * 115)
    print("PHASE 6 OVERALL RESULTS (TRUE 3-FOLD LOSO)")
    print("=" * 115)
    header = f"{'Condition':<28} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Fold BalAcc Mean±Std':<22} | {'Confusion Matrix [[TN,FP],[FN,TP]]'}"
    print(header)
    print("-" * 135)

    results_summary = {}

    for cond_k, cond_p in preds_dict.items():
        acc = accuracy_score(labels, cond_p)
        bal = balanced_accuracy_score(labels, cond_p)
        f1 = f1_score(labels, cond_p, average="macro", zero_division=0)
        c_rec = recall_score(labels, cond_p, pos_label=1, zero_division=0)
        inc_rec = recall_score(labels, cond_p, pos_label=0, zero_division=0)
        cm = confusion_matrix(labels, cond_p).tolist()

        sub_bals = []
        sub_metrics = {}
        for sub in unique_subjects:
            sub_m = (subjects == sub)
            s_acc = accuracy_score(labels[sub_m], cond_p[sub_m])
            s_bal = balanced_accuracy_score(labels[sub_m], cond_p[sub_m])
            s_f1 = f1_score(labels[sub_m], cond_p[sub_m], average="macro", zero_division=0)
            s_cr = recall_score(labels[sub_m], cond_p[sub_m], pos_label=1, zero_division=0)
            s_ir = recall_score(labels[sub_m], cond_p[sub_m], pos_label=0, zero_division=0)
            s_cm = confusion_matrix(labels[sub_m], cond_p[sub_m]).tolist()
            sub_bals.append(s_bal)
            sub_metrics[sub] = {
                "accuracy": float(s_acc),
                "balanced_accuracy": float(s_bal),
                "macro_f1": float(s_f1),
                "correct_recall": float(s_cr),
                "incorrect_recall": float(s_ir),
                "confusion_matrix": s_cm
            }

        mean_bal = float(np.mean(sub_bals))
        std_bal = float(np.std(sub_bals))
        m_s_str = f"{mean_bal*100:.2f}% ± {std_bal*100:.2f}%"

        print(f"{cond_k:<28} | {acc*100:6.2f}% | {bal*100:6.2f}% | {f1*100:6.2f}% | {c_rec*100:6.2f}% | {inc_rec*100:6.2f}% | {m_s_str:<22} | {str(cm)}")

        results_summary[cond_k] = {
            "accuracy": float(acc),
            "balanced_accuracy": float(bal),
            "macro_f1": float(f1),
            "correct_recall": float(c_rec),
            "incorrect_recall": float(inc_rec),
            "confusion_matrix": cm,
            "fold_balacc_mean": mean_bal,
            "fold_balacc_std": std_bal,
            "per_subject": sub_metrics,
            "selected_thresholds": selected_thresholds.get(cond_k, {})
        }

    # Print per-subject breakdown
    print("\n" + "=" * 115)
    print("PER-SUBJECT BREAKDOWN")
    print("=" * 115)
    for sub in unique_subjects:
        print(f"\n--- {sub.upper()} (N={fold_details[sub]['n_test']}) ---")
        for cond_k in preds_dict.keys():
            sm = results_summary[cond_k]["per_subject"][sub]
            print(f"  {cond_k:<24}: Acc={sm['accuracy']*100:.2f}%, BalAcc={sm['balanced_accuracy']*100:.2f}%, F1={sm['macro_f1']*100:.2f}%, CorRec={sm['correct_recall']*100:.2f}%, IncRec={sm['incorrect_recall']*100:.2f}%, CM={sm['confusion_matrix']}")

    # Print threshold stability and difference frequency
    print("\n" + "=" * 115)
    print("THRESHOLD STABILITY & DEVIATION FREQUENCY")
    print("=" * 115)
    print(f"Base Production Thresholds: {dict(zip(PARAM_NAMES, BASE_THRESH.tolist()))}")
    
    deviation_counts = {k: {p: 0 for p in PARAM_NAMES} for k in ["B_opt_bal_acc", "C_opt_macro_f1"]}
    for cond_k in ["B_opt_bal_acc", "C_opt_macro_f1"]:
        print(f"\nCondition: {cond_k}")
        for sub in unique_subjects:
            th = selected_thresholds[cond_k][sub]
            diffs = []
            for i, p in enumerate(PARAM_NAMES):
                if not np.isclose(th[i], BASE_THRESH[i]):
                    deviation_counts[cond_k][p] += 1
                    diffs.append(f"{p}: {BASE_THRESH[i]} -> {th[i]}")
            diff_str = ", ".join(diffs) if diffs else "Identical to Baseline"
            print(f"  Test {sub} fold: Selected={dict(zip(PARAM_NAMES, th))} | Deviations: [{diff_str}]")

        print(f"  Deviation frequency across 3 folds:")
        for p in PARAM_NAMES:
            cnt = deviation_counts[cond_k][p]
            pct = cnt / len(unique_subjects) * 100
            print(f"    {p:<18}: {cnt}/{len(unique_subjects)} folds ({pct:.1f}%)")

    # Detailed Error Inspection on Held-Out Predictions
    print("\n" + "=" * 115)
    print("HELD-OUT ERROR INSPECTION (DIAGNOSTIC REPORTING ONLY)")
    print("=" * 115)
    r_preds = preds_dict["A_fixed_baseline"]
    b_preds = preds_dict["B_opt_bal_acc"]
    
    diff_mask = (r_preds != b_preds)
    num_diff = int(np.sum(diff_mask))
    print(f"Total repetitions where Optimized Thresholds differ from Base Rules: {num_diff} / {len(df)}")
    
    diff_df = df[diff_mask].copy()
    diff_df["base_pred"] = r_preds[diff_mask]
    diff_df["opt_pred"] = b_preds[diff_mask]
    diff_df["ground_truth"] = labels[diff_mask]
    
    helped_mask = (diff_df["opt_pred"] == diff_df["ground_truth"])
    hurt_mask = (diff_df["base_pred"] == diff_df["ground_truth"])
    
    num_helped = int(np.sum(helped_mask))
    num_hurt = int(np.sum(hurt_mask))
    print(f"  Helped cases (Base wrong -> Opt correct): {num_helped}")
    print(f"  Hurt cases   (Base correct -> Opt wrong): {num_hurt}")
    print(f"  Net difference: {num_helped - num_hurt} cases")

    for sub in unique_subjects:
        sub_diff = diff_df[diff_df["subject_id"] == sub]
        s_helped = int(np.sum(sub_diff["opt_pred"] == sub_diff["ground_truth"]))
        s_hurt = int(np.sum(sub_diff["base_pred"] == sub_diff["ground_truth"]))
        print(f"  {sub}: {len(sub_diff)} changed reps | Helped: {s_helped}, Hurt: {s_hurt} (Net: {s_helped - s_hurt})")
        for _, row in sub_diff.iterrows():
            orig_stat = "CORRECT" if row['base_pred'] == row['ground_truth'] else "WRONG"
            opt_stat = "CORRECT" if row['opt_pred'] == row['ground_truth'] else "WRONG"
            print(f"    - Rep: {row['video_name']} #{row['repetition_index']} (True: {row['ground_truth_label']}): Base {orig_stat} -> Opt {opt_stat} | min_a={row['min_elbow_angle']}°, flare={row['elbow_flare']}, rom={row['rom']}°, tilt={row['torso_tilt']}°")

    output_data = {
        "summary": results_summary,
        "fold_details": fold_details,
        "deviation_counts": deviation_counts,
        "held_out_error_analysis": {
            "total_diff": num_diff,
            "num_helped": num_helped,
            "num_hurt": num_hurt,
            "net_diff": num_helped - num_hurt
        }
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(output_data, f, indent=2)
    print(f"\nSaved Phase 6 results to {OUTPUT_JSON}")

if __name__ == "__main__":
    run_phase6_evaluation()

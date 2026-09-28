import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
SEQ_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase8d_movement_quality_results.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

RANDOM_SEED = 42

def run_phase8d_evaluation():
    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    min_a = df["min_elbow_angle"].values
    flare = df["elbow_flare"].values
    rom = df["rom"].values
    abs_rot = df["torso_rotation"].abs().values
    durs = df["duration_sec"].values

    # Phase 8A rules
    p_8a = ((min_a <= 101.0) & (flare <= 0.30) & (rom >= 25.0) & (abs_rot <= 20.0)).astype(int)

    # Phase 8C Duration Baseline (Nested LOSO: P1: 1.0s, P2: 1.75s, P3: 1.75s)
    p_8c_nested = np.zeros(len(df), dtype=int)
    for sub, th in [("person1", 1.00), ("person2", 1.75), ("person3", 1.75)]:
        m = (subjects == sub)
        p_8c_nested[m] = (p_8a[m] & (durs[m] >= th)).astype(int)

    # Fixed 1.75s benchmark
    p_8c_fixed = (p_8a & (durs >= 1.75)).astype(int)

    base_acc = float(accuracy_score(labels, p_8c_nested))
    base_bal = float(balanced_accuracy_score(labels, p_8c_nested))
    base_f1 = float(f1_score(labels, p_8c_nested, average="macro", zero_division=0))
    base_cr = float(recall_score(labels, p_8c_nested, pos_label=1, zero_division=0))
    base_ir = float(recall_score(labels, p_8c_nested, pos_label=0, zero_division=0))
    base_cm = confusion_matrix(labels, p_8c_nested).tolist()

    sub_bals_base = [float(balanced_accuracy_score(labels[subjects == s], p_8c_nested[subjects == s])) for s in unique_subjects]

    print("=" * 115)
    print("PHASE 8D: TEMPORAL MOVEMENT-QUALITY DIAGNOSTIC")
    print(f"Dataset: {len(df)} clean repetitions across {len(unique_subjects)} subjects")
    print(f"Primary Evaluation Baseline (Phase 8C Nested): Acc={base_acc*100:.2f}%, BalAcc={base_bal*100:.2f}%, MacroF1={base_f1*100:.2f}%, CM={base_cm}")
    print(f"Descriptive Fixed 1.75s Benchmark: Acc={accuracy_score(labels, p_8c_fixed)*100:.2f}%, BalAcc={balanced_accuracy_score(labels, p_8c_fixed)*100:.2f}%, F1={f1_score(labels, p_8c_fixed, average='macro')*100:.2f}%")
    print("=" * 115)

    # 1. Feature Extraction for All 12 Candidate Temporal Metrics
    raw_feats = {
        "smoothness": [],
        "peak_jerk": [],
        "mean_abs_jerk": [],
        "peak_abs_acc": [],
        "mean_abs_acc": [],
        "vel_sign_changes": [],
        "ecc_conc_vel_ratio": [],
        "flex_dur": [],
        "ext_dur": [],
        "flex_ext_ratio": [],
        "time_to_peak_pct": [],
        "recovery_rate": []
    }

    for idx, r in df.iterrows():
        raw = np.load(SEQ_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        act_ang_deg = raw[:, 0] * 180.0
        act_vel = raw[:, 2]

        idx_peak = int(np.argmin(act_ang_deg))
        idx_peak = max(5, min(idx_peak, len(act_ang_deg) - 6))

        acc = np.gradient(act_vel)
        jerk = np.gradient(acc)

        flex_d = dur * (idx_peak / 128.0)
        ext_d = dur * ((128.0 - idx_peak) / 128.0)

        mean_flex_v = float(np.mean(np.abs(act_vel[:idx_peak])))
        mean_ext_v = float(np.mean(np.abs(act_vel[idx_peak:])))

        rom_val = float(np.max(act_ang_deg) - np.min(act_ang_deg))
        min_ang_val = float(np.min(act_ang_deg))
        recov = float((act_ang_deg[-1] - min_ang_val) / max(rom_val, 1e-3))

        signs = np.sign(act_vel)
        active_vel = np.where(np.abs(act_vel) > 0.02, signs, 0)
        nz = active_vel[active_vel != 0]
        n_changes = int(np.sum(np.diff(nz) != 0)) if len(nz) > 1 else 0

        raw_feats["smoothness"].append(float(r["smoothness"]))
        raw_feats["peak_jerk"].append(float(np.max(np.abs(jerk))))
        raw_feats["mean_abs_jerk"].append(float(np.mean(np.abs(jerk))))
        raw_feats["peak_abs_acc"].append(float(np.max(np.abs(acc))))
        raw_feats["mean_abs_acc"].append(float(np.mean(np.abs(acc))))
        raw_feats["vel_sign_changes"].append(n_changes)
        raw_feats["ecc_conc_vel_ratio"].append(float(mean_ext_v / max(mean_flex_v, 1e-4)))
        raw_feats["flex_dur"].append(float(flex_d))
        raw_feats["ext_dur"].append(float(ext_d))
        raw_feats["flex_ext_ratio"].append(float(flex_d / max(ext_d, 1e-3)))
        raw_feats["time_to_peak_pct"].append(float(idx_peak / 128.0))
        raw_feats["recovery_rate"].append(float(recov))

    for k in raw_feats:
        raw_feats[k] = np.array(raw_feats[k], dtype=np.float32)

    # 2. Descriptive Comparison: Correct vs Incorrect
    print("\n" + "=" * 115)
    print("PART 1: DESCRIPTIVE COMPARISON (CORRECT vs INCORRECT)")
    print("=" * 115)
    header = f"{'Feature':<22} | {'Correct (Mean±Std)':<24} | {'Correct Med [Q1, Q3]':<22} | {'Incorrect (Mean±Std)':<24} | {'Incorrect Med [Q1, Q3]'}"
    print(header)
    print("-" * 125)

    def calc_dist(arr):
        return {
            "mean": float(np.mean(arr)), "std": float(np.std(arr)), "median": float(np.median(arr)),
            "q25": float(np.percentile(arr, 25)), "q75": float(np.percentile(arr, 75)),
            "min": float(np.min(arr)), "max": float(np.max(arr))
        }

    descriptive_table = {}
    for feat_name, arr in raw_feats.items():
        c_dist = calc_dist(arr[labels == 1])
        i_dist = calc_dist(arr[labels == 0])
        descriptive_table[feat_name] = {"correct": c_dist, "incorrect": i_dist}

        c_str_m = f"{c_dist['mean']:.3f} +/- {c_dist['std']:.3f}"
        c_str_q = f"{c_dist['median']:.3f} [{c_dist['q25']:.3f}, {c_dist['q75']:.3f}]"
        i_str_m = f"{i_dist['mean']:.3f} +/- {i_dist['std']:.3f}"
        i_str_q = f"{i_dist['median']:.3f} [{i_dist['q25']:.3f}, {i_dist['q75']:.3f}]"

        print(f"{feat_name:<22} | {c_str_m:<24} | {c_str_q:<22} | {i_str_m:<24} | {i_str_q}")

    # Specific Inspection of Remaining False Corrects
    print("\n" + "=" * 115)
    print("PART 2: SPECIFIC INSPECTION OF REMAINING FALSE CORRECTS")
    print("=" * 115)
    fc_mask = (labels == 0) & (p_8c_nested == 1)
    fc_indices = np.where(fc_mask)[0]
    print(f"Total Remaining False Corrects: {len(fc_indices)}")
    
    fc_audit_list = []
    for idx in fc_indices:
        r = df.iloc[idx]
        audit_entry = {
            "subject": str(r["subject_id"]), "video": str(r["video_name"]), "rep": int(r["repetition_index"]),
            "error_tags": str(r.get("error_tags", "")), "notes": str(r.get("notes", "")),
            "dur": float(r["duration_sec"]),
            "smoothness": float(raw_feats["smoothness"][idx]),
            "ext_dur": float(raw_feats["ext_dur"][idx]),
            "flex_dur": float(raw_feats["flex_dur"][idx]),
            "flex_ext_ratio": float(raw_feats["flex_ext_ratio"][idx]),
            "ttp_pct": float(raw_feats["time_to_peak_pct"][idx]),
            "ecc_conc_vel": float(raw_feats["ecc_conc_vel_ratio"][idx]),
            "peak_jerk": float(raw_feats["peak_jerk"][idx])
        }
        fc_audit_list.append(audit_entry)
        print(f"Rep: {r['subject_id']} | {r['video_name']} #{r['repetition_index']} | Tag: {r.get('error_tags', '')} | dur={r['duration_sec']}s")
        print(f"     ext_dur={audit_entry['ext_dur']:.2f}s, flex/ext={audit_entry['flex_ext_ratio']:.2f}, ttp%={audit_entry['ttp_pct']:.2f}, ecc/conc vel={audit_entry['ecc_conc_vel']:.2f}, smooth={audit_entry['smoothness']:.3f}, pk_jerk={audit_entry['peak_jerk']:.3f}")

    # 3. Univariate Candidate-Threshold Diagnostics
    print("\n" + "=" * 115)
    print("PART 3: UNIVARIATE CANDIDATE-THRESHOLD DIAGNOSTICS (DESCRIPTIVE SWEEP)")
    print("=" * 115)

    candidates_eval = {
        "ext_dur": (raw_feats["ext_dur"], ">=", [0.50, 0.60, 0.65, 0.70, 0.75, 0.80]),
        "flex_ext_ratio": (raw_feats["flex_ext_ratio"], "<=", [2.0, 2.5, 3.0, 3.5, 4.0]),
        "time_to_peak_pct": (raw_feats["time_to_peak_pct"], "<=", [0.65, 0.70, 0.75, 0.80]),
        "ecc_conc_vel_ratio": (raw_feats["ecc_conc_vel_ratio"], "<=", [1.5, 1.8, 2.0, 2.2, 2.5]),
        "smoothness": (raw_feats["smoothness"], ">=", [0.20, 0.25, 0.28, 0.30, 0.35])
    }

    sweep_results = {}
    for feat_name, (arr, op, grid) in candidates_eval.items():
        print(f"\nFeature: {feat_name} ({op})")
        header = f"{'Threshold':<14} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Cor Rej':<8} | {'FC Caught':<10} | {'Confusion Matrix'}"
        print(header)
        print("-" * 115)

        feat_sweep = {}
        for th in grid:
            cond = (arr >= th) if op == ">=" else (arr <= th)
            p_cand = (p_8c_nested & cond).astype(int)

            acc = float(accuracy_score(labels, p_cand))
            bal = float(balanced_accuracy_score(labels, p_cand))
            f1 = float(f1_score(labels, p_cand, average="macro", zero_division=0))
            cr = float(recall_score(labels, p_cand, pos_label=1, zero_division=0))
            ir = float(recall_score(labels, p_cand, pos_label=0, zero_division=0))
            cm = confusion_matrix(labels, p_cand).tolist()

            cor_rej = int(np.sum((labels == 1) & (p_8c_nested == 1) & (p_cand == 0)))
            fc_caught = int(np.sum(fc_mask & (p_cand == 0)))

            sub_bals = [float(balanced_accuracy_score(labels[subjects == s], p_cand[subjects == s])) for s in unique_subjects]

            feat_sweep[str(th)] = {
                "threshold": th, "accuracy": acc, "balanced_accuracy": bal, "macro_f1": f1,
                "correct_recall": cr, "incorrect_recall": ir, "confusion_matrix": cm,
                "cor_newly_rejected": cor_rej, "fc_caught": fc_caught,
                "fold_balacc_mean": float(np.mean(sub_bals)), "fold_balacc_std": float(np.std(sub_bals))
            }

            th_label = f"{op} {th:.2f}"
            print(f"{th_label:<14} | {acc*100:6.2f}% | {bal*100:6.2f}% | {f1*100:6.2f}% | {cr*100:6.2f}% | {ir*100:6.2f}% | {cor_rej:<8} | {fc_caught:<10} | {cm}")

        sweep_results[feat_name] = feat_sweep

    # 4. Strict Nested LOSO Evaluation on Strongest Candidates
    print("\n" + "=" * 115)
    print("PART 4: STRICT NESTED LOSO EVALUATION (TRAINING-PORTION SELECTION)")
    print("=" * 115)

    nested_results = {}
    for feat_name in ["ext_dur", "flex_ext_ratio", "time_to_peak_pct", "ecc_conc_vel_ratio", "smoothness"]:
        arr, op, grid = candidates_eval[feat_name]
        nested_preds = np.zeros(len(df), dtype=int)
        fold_details = {}

        for test_sub in unique_subjects:
            test_mask = (subjects == test_sub)
            tr_indices = np.where(~test_mask)[0]
            test_idx = np.where(test_mask)[0]
            y_tr = labels[tr_indices]

            # Selection strictly on training subjects
            base_tr_bal = balanced_accuracy_score(labels[tr_indices], p_8c_nested[tr_indices])
            best_tr_bal = base_tr_bal
            best_th = None

            for th in grid:
                cond_tr = (arr[tr_indices] >= th) if op == ">=" else (arr[tr_indices] <= th)
                cand_p_tr = (p_8c_nested[tr_indices] & cond_tr).astype(int)
                bal_tr = balanced_accuracy_score(labels[tr_indices], cand_p_tr)

                if bal_tr > best_tr_bal:
                    best_tr_bal = bal_tr
                    best_th = th
                elif np.isclose(bal_tr, best_tr_bal) and best_th is not None:
                    # prefer more conservative
                    if op == ">=" and th < best_th: best_th = th
                    elif op == "<=" and th > best_th: best_th = th

            fold_details[test_sub] = {"selected_th": best_th, "train_base_balacc": float(base_tr_bal), "train_best_balacc": float(best_tr_bal)}

            if best_th is not None:
                t_cond = (arr[test_idx] >= best_th) if op == ">=" else (arr[test_idx] <= best_th)
                nested_preds[test_idx] = (p_8c_nested[test_idx] & t_cond).astype(int)
            else:
                nested_preds[test_idx] = p_8c_nested[test_idx]

        acc_n = float(accuracy_score(labels, nested_preds))
        bal_n = float(balanced_accuracy_score(labels, nested_preds))
        f1_n = float(f1_score(labels, nested_preds, average="macro", zero_division=0))
        cr_n = float(recall_score(labels, nested_preds, pos_label=1, zero_division=0))
        ir_n = float(recall_score(labels, nested_preds, pos_label=0, zero_division=0))
        cm_n = confusion_matrix(labels, nested_preds).tolist()

        sub_bals_n = []
        per_sub_n = {}
        for s in unique_subjects:
            m = (subjects == s)
            s_acc = float(accuracy_score(labels[m], nested_preds[m]))
            s_bal = float(balanced_accuracy_score(labels[m], nested_preds[m]))
            s_f1 = float(f1_score(labels[m], nested_preds[m], average="macro", zero_division=0))
            s_cr = float(recall_score(labels[m], nested_preds[m], pos_label=1, zero_division=0))
            s_ir = float(recall_score(labels[m], nested_preds[m], pos_label=0, zero_division=0))
            s_cm = confusion_matrix(labels[m], nested_preds[m]).tolist()
            sub_bals_n.append(s_bal)
            per_sub_n[s] = {"accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1, "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm}

        cor_rej_n = int(np.sum((labels == 1) & (p_8c_nested == 1) & (nested_preds == 0)))
        fc_cgt_n = int(np.sum(fc_mask & (nested_preds == 0)))

        nested_results[feat_name] = {
            "accuracy": acc_n, "balanced_accuracy": bal_n, "macro_f1": f1_n,
            "correct_recall": cr_n, "incorrect_recall": ir_n, "confusion_matrix": cm_n,
            "fold_balacc_mean": float(np.mean(sub_bals_n)), "fold_balacc_std": float(np.std(sub_bals_n)),
            "per_subject": per_sub_n, "fold_details": fold_details,
            "cor_newly_rejected": cor_rej_n, "fc_caught": fc_cgt_n
        }

        m_s = f"{np.mean(sub_bals_n)*100:.2f}% +/- {np.std(sub_bals_n)*100:.2f}%"
        th_summary = ", ".join([f"{s}: {fold_details[s]['selected_th']}" for s in unique_subjects])
        print(f"{feat_name:<18} | Acc={acc_n*100:6.2f}% | BalAcc={bal_n*100:6.2f}% | F1={f1_n*100:6.2f}% | CorRec={cr_n*100:6.2f}% | IncRec={ir_n*100:6.2f}% | Fold: {m_s} | FC Caught: {fc_cgt_n} | Rej: {cor_rej_n}")
        print(f"   Selected Thresholds: [{th_summary}]")

    output_data = {
        "descriptive_table": descriptive_table,
        "fc_audit": fc_audit_list,
        "sweep_results": sweep_results,
        "nested_results": nested_results
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nSaved complete Phase 8D diagnostic results to {OUTPUT_JSON}")

if __name__ == "__main__":
    run_phase8d_evaluation()

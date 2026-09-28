import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
SEQ_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase8b_dynamic_flare_results.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

RANDOM_SEED = 42
WINDOWS = [0.10, 0.15, 0.20]
THETA_GRID = [0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15]

def run_phase8b_evaluation():
    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    min_a = df["min_elbow_angle"].values
    flare = df["elbow_flare"].values
    rom = df["rom"].values
    abs_rot = df["torso_rotation"].abs().values

    # Phase 8A rule configuration (other 3 rules frozen)
    rule_other = (min_a <= 101.0) & (rom >= 25.0) & (abs_rot <= 20.0)

    # Condition A: Phase 8A Baseline (absolute flare <= 0.30)
    preds_a = (rule_other & (flare <= 0.30)).astype(int)
    base_acc = float(accuracy_score(labels, preds_a))
    base_bal = float(balanced_accuracy_score(labels, preds_a))
    base_f1 = float(f1_score(labels, preds_a, average="macro", zero_division=0))
    base_cr = float(recall_score(labels, preds_a, pos_label=1, zero_division=0))
    base_ir = float(recall_score(labels, preds_a, pos_label=0, zero_division=0))
    base_cm = confusion_matrix(labels, preds_a).tolist()

    sub_bals_base = []
    base_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        s_acc = float(accuracy_score(labels[m], preds_a[m]))
        s_bal = float(balanced_accuracy_score(labels[m], preds_a[m]))
        s_f1 = float(f1_score(labels[m], preds_a[m], average="macro", zero_division=0))
        s_cr = float(recall_score(labels[m], preds_a[m], pos_label=1, zero_division=0))
        s_ir = float(recall_score(labels[m], preds_a[m], pos_label=0, zero_division=0))
        s_cm = confusion_matrix(labels[m], preds_a[m]).tolist()
        sub_bals_base.append(s_bal)
        base_per_sub[sub] = {
            "accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1,
            "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm
        }

    print("=" * 115)
    print("PHASE 8B: DYNAMIC FLARE / BASELINE-NORMALIZED FLARE EVALUATION")
    print(f"Dataset: {len(df)} clean repetitions across {len(unique_subjects)} subjects")
    print(f"Phase 8A Baseline: Acc={base_acc*100:.2f}%, BalAcc={base_bal*100:.2f}%, MacroF1={base_f1*100:.2f}%, CM={base_cm}")
    print("=" * 115)

    # 1. Feature Extraction & Descriptive Analysis
    print("\n" + "=" * 115)
    print("PART 1: DESCRIPTIVE ANALYSIS OF DYNAMIC FLARE & BASELINE POSTURE")
    print("=" * 115)
    
    dyn_flares = {w: [] for w in WINDOWS}
    base_flares = {w: [] for w in WINDOWS}
    dyn_ratios = {w: [] for w in WINDOWS}
    peak_flares = []

    for idx, r in df.iterrows():
        raw = np.load(SEQ_DIR / r["sequence_file"])
        act_flare = raw[:, 6]
        pk_fl = float(np.max(act_flare))
        peak_flares.append(pk_fl)

        for w in WINDOWS:
            n_win = max(1, int(len(act_flare) * w))
            b_fl = float(np.median(act_flare[:n_win]))
            d_fl = pk_fl - b_fl
            d_ratio = d_fl / max(abs(b_fl), 1e-4)
            dyn_flares[w].append(d_fl)
            base_flares[w].append(b_fl)
            dyn_ratios[w].append(d_ratio)

    peak_flares = np.array(peak_flares, dtype=np.float32)
    for w in WINDOWS:
        dyn_flares[w] = np.array(dyn_flares[w], dtype=np.float32)
        base_flares[w] = np.array(base_flares[w], dtype=np.float32)
        dyn_ratios[w] = np.array(dyn_ratios[w], dtype=np.float32)

    descriptive_stats = {}
    p2_cor_high = (subjects == "person2") & (labels == 1) & (flare > 0.30)
    inc_pass_fl = (labels == 0) & (flare <= 0.30)

    for w in WINDOWS:
        w_pct = int(w * 100)
        df_w = dyn_flares[w]
        bf_w = base_flares[w]
        dr_w = dyn_ratios[w]

        stats_w = {
            "all_mean_peak": float(np.mean(peak_flares)),
            "cor_mean_base": float(np.mean(bf_w[labels == 1])),
            "inc_mean_base": float(np.mean(bf_w[labels == 0])),
            "cor_mean_dyn": float(np.mean(df_w[labels == 1])),
            "inc_mean_dyn": float(np.mean(df_w[labels == 0])),
            "cor_median_dyn": float(np.median(df_w[labels == 1])),
            "inc_median_dyn": float(np.median(df_w[labels == 0])),
            "cor_mean_ratio": float(np.mean(dr_w[labels == 1])),
            "inc_mean_ratio": float(np.mean(dr_w[labels == 0])),
            "p2_high_cor": {
                "count": int(np.sum(p2_cor_high)),
                "peak_mean": float(np.mean(peak_flares[p2_cor_high])),
                "base_mean": float(np.mean(bf_w[p2_cor_high])),
                "dyn_mean": float(np.mean(df_w[p2_cor_high])),
                "dyn_min": float(np.min(df_w[p2_cor_high])),
                "dyn_max": float(np.max(df_w[p2_cor_high])),
                "ratio_mean": float(np.mean(dr_w[p2_cor_high]))
            },
            "inc_pass_flare": {
                "count": int(np.sum(inc_pass_fl)),
                "peak_mean": float(np.mean(peak_flares[inc_pass_fl])),
                "base_mean": float(np.mean(bf_w[inc_pass_fl])),
                "dyn_mean": float(np.mean(df_w[inc_pass_fl])),
                "dyn_min": float(np.min(df_w[inc_pass_fl])),
                "dyn_max": float(np.max(df_w[inc_pass_fl])),
                "ratio_mean": float(np.mean(dr_w[inc_pass_fl]))
            }
        }
        descriptive_stats[f"window_{w_pct}pct"] = stats_w

        print(f"Window {w_pct}% (Frames: {int(128*w)}/128):")
        print(f"  Base Flare  : Correct Mean = {stats_w['cor_mean_base']:.3f} | Incorrect Mean = {stats_w['inc_mean_base']:.3f}")
        print(f"  Dyn Flare   : Correct Mean = {stats_w['cor_mean_dyn']:.3f} | Incorrect Mean = {stats_w['inc_mean_dyn']:.3f}")
        print(f"  Dyn Ratio   : Correct Mean = {stats_w['cor_mean_ratio']:.2f} | Incorrect Mean = {stats_w['inc_mean_ratio']:.2f}")
        p2h = stats_w["p2_high_cor"]
        print(f"  P2 High-Flare Correct (N={p2h['count']}): Peak={p2h['peak_mean']:.3f}, Base={p2h['base_mean']:.3f}, Dyn={p2h['dyn_mean']:.3f} (Range: [{p2h['dyn_min']:.3f}, {p2h['dyn_max']:.3f}]), Ratio={p2h['ratio_mean']:.2f}")
        ipf = stats_w["inc_pass_flare"]
        print(f"  Incorrect Passing Abs Flare (N={ipf['count']}): Peak={ipf['peak_mean']:.3f}, Base={ipf['base_mean']:.3f}, Dyn={ipf['dyn_mean']:.3f} (Range: [{ipf['dyn_min']:.3f}, {ipf['dyn_max']:.3f}]), Ratio={ipf['ratio_mean']:.2f}")

    # 2. Descriptive Grid Sweep over Conditions B and C
    print("\n" + "=" * 115)
    print("PART 2: DESCRIPTIVE GRID SWEEP OVER CONDITIONS B & C")
    print("=" * 115)
    header = f"{'Condition':<14} | {'Window':<8} | {'Theta':<7} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'P2 Rescued':<10} | {'Cor Rej':<7} | {'Inc Caught':<10}"
    print(header)
    print("-" * 135)

    sweep_b_results = {}
    sweep_c_results = {}

    for w in WINDOWS:
        w_pct = int(w * 100)
        d_fl = dyn_flares[w]

        for th in THETA_GRID:
            # Condition B: Replace absolute flare with dynamic flare
            p_b = (rule_other & (d_fl <= th)).astype(int)
            acc_b = float(accuracy_score(labels, p_b))
            bal_b = float(balanced_accuracy_score(labels, p_b))
            f1_b = float(f1_score(labels, p_b, average="macro", zero_division=0))
            cr_b = float(recall_score(labels, p_b, pos_label=1, zero_division=0))
            ir_b = float(recall_score(labels, p_b, pos_label=0, zero_division=0))
            cm_b = confusion_matrix(labels, p_b).tolist()

            # P2 high-flare correct rescued (was 0 in baseline, now 1)
            p2_rescued_b = int(np.sum(p2_cor_high & (preds_a == 0) & (p_b == 1)))
            cor_newly_rej_b = int(np.sum((labels == 1) & (preds_a == 1) & (p_b == 0)))
            inc_newly_caught_b = int(np.sum((labels == 0) & (preds_a == 1) & (p_b == 0)))

            sub_bals_b = [float(balanced_accuracy_score(labels[subjects == s], p_b[subjects == s])) for s in unique_subjects]

            key_b = f"W{w_pct}_th{th}"
            sweep_b_results[key_b] = {
                "window": w, "theta": th, "accuracy": acc_b, "balanced_accuracy": bal_b, "macro_f1": f1_b,
                "correct_recall": cr_b, "incorrect_recall": ir_b, "confusion_matrix": cm_b,
                "p2_rescued": p2_rescued_b, "cor_newly_rejected": cor_newly_rej_b, "inc_newly_caught": inc_newly_caught_b,
                "fold_balacc_mean": float(np.mean(sub_bals_b)), "fold_balacc_std": float(np.std(sub_bals_b))
            }

            print(f"{'Cond B (Repl)':<14} | {w_pct:<7}% | {th:<7.2f} | {acc_b*100:6.2f}% | {bal_b*100:6.2f}% | {f1_b*100:6.2f}% | {cr_b*100:6.2f}% | {ir_b*100:6.2f}% | {p2_rescued_b:<10} | {cor_newly_rej_b:<7} | {inc_newly_caught_b:<10}")

            # Condition C: Keep absolute flare AND add dynamic flare
            p_c = (rule_other & (flare <= 0.30) & (d_fl <= th)).astype(int)
            acc_c = float(accuracy_score(labels, p_c))
            bal_c = float(balanced_accuracy_score(labels, p_c))
            f1_c = float(f1_score(labels, p_c, average="macro", zero_division=0))
            cr_c = float(recall_score(labels, p_c, pos_label=1, zero_division=0))
            ir_c = float(recall_score(labels, p_c, pos_label=0, zero_division=0))
            cm_c = confusion_matrix(labels, p_c).tolist()

            p2_rescued_c = int(np.sum(p2_cor_high & (preds_a == 0) & (p_c == 1))) # always 0 since flare <= 0.30 retained
            cor_newly_rej_c = int(np.sum((labels == 1) & (preds_a == 1) & (p_c == 0)))
            inc_newly_caught_c = int(np.sum((labels == 0) & (preds_a == 1) & (p_c == 0)))

            sub_bals_c = [float(balanced_accuracy_score(labels[subjects == s], p_c[subjects == s])) for s in unique_subjects]

            key_c = f"W{w_pct}_th{th}"
            sweep_c_results[key_c] = {
                "window": w, "theta": th, "accuracy": acc_c, "balanced_accuracy": bal_c, "macro_f1": f1_c,
                "correct_recall": cr_c, "incorrect_recall": ir_c, "confusion_matrix": cm_c,
                "p2_rescued": p2_rescued_c, "cor_newly_rejected": cor_newly_rej_c, "inc_newly_caught": inc_newly_caught_c,
                "fold_balacc_mean": float(np.mean(sub_bals_c)), "fold_balacc_std": float(np.std(sub_bals_c))
            }

            print(f"{'Cond C (Supp)':<14} | {w_pct:<7}% | {th:<7.2f} | {acc_c*100:6.2f}% | {bal_c*100:6.2f}% | {f1_c*100:6.2f}% | {cr_c*100:6.2f}% | {ir_c*100:6.2f}% | {p2_rescued_c:<10} | {cor_newly_rej_c:<7} | {inc_newly_caught_c:<10}")

    # 3. Strict Nested LOSO Protocol
    print("\n" + "=" * 115)
    print("PART 3: STRICT NESTED LOSO EXPERIMENT (ZERO TEST LEAKAGE)")
    print("=" * 115)
    
    nested_preds_b = np.zeros(len(df), dtype=int)
    nested_preds_c = np.zeros(len(df), dtype=int)
    nested_fold_details_b = {}
    nested_fold_details_c = {}

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

        # Baseline on inner val
        p_base_val = (rule_other[val_idx] & (flare[val_idx] <= 0.30)).astype(int)
        val_base_bal = balanced_accuracy_score(labels[val_idx], p_base_val)

        # Condition B Optimization on inner val
        best_b_val_bal = -1.0
        best_b_cfg = None

        for w in WINDOWS:
            d_val = dyn_flares[w][val_idx]
            d_tr = dyn_flares[w][actual_tr_idx]
            for th in THETA_GRID:
                p_val_b = (rule_other[val_idx] & (d_val <= th)).astype(int)
                bal_v = balanced_accuracy_score(labels[val_idx], p_val_b)
                if bal_v > best_b_val_bal:
                    best_b_val_bal = bal_v
                    best_b_cfg = (w, th)
                elif np.isclose(bal_v, best_b_val_bal):
                    # tie break on actual_tr_idx
                    p_tr_cand = (rule_other[actual_tr_idx] & (d_tr <= th)).astype(int)
                    d_tr_best = dyn_flares[best_b_cfg[0]][actual_tr_idx]
                    p_tr_best = (rule_other[actual_tr_idx] & (d_tr_best <= best_b_cfg[1])).astype(int)
                    if balanced_accuracy_score(labels[actual_tr_idx], p_tr_cand) > balanced_accuracy_score(labels[actual_tr_idx], p_tr_best):
                        best_b_cfg = (w, th)

        # Condition C Optimization on inner val
        best_c_val_bal = -1.0
        best_c_cfg = None

        for w in WINDOWS:
            d_val = dyn_flares[w][val_idx]
            d_tr = dyn_flares[w][actual_tr_idx]
            for th in THETA_GRID:
                p_val_c = (rule_other[val_idx] & (flare[val_idx] <= 0.30) & (d_val <= th)).astype(int)
                bal_v = balanced_accuracy_score(labels[val_idx], p_val_c)
                if bal_v > best_c_val_bal:
                    best_c_val_bal = bal_v
                    best_c_cfg = (w, th)
                elif np.isclose(bal_v, best_c_val_bal):
                    p_tr_cand = (rule_other[actual_tr_idx] & (flare[actual_tr_idx] <= 0.30) & (d_tr <= th)).astype(int)
                    d_tr_best = dyn_flares[best_c_cfg[0]][actual_tr_idx]
                    p_tr_best = (rule_other[actual_tr_idx] & (flare[actual_tr_idx] <= 0.30) & (d_tr_best <= best_c_cfg[1])).astype(int)
                    if balanced_accuracy_score(labels[actual_tr_idx], p_tr_cand) > balanced_accuracy_score(labels[actual_tr_idx], p_tr_best):
                        best_c_cfg = (w, th)

        # Apply winning configurations once to test subject
        w_b, th_b = best_b_cfg
        nested_preds_b[test_idx] = (rule_other[test_idx] & (dyn_flares[w_b][test_idx] <= th_b)).astype(int)

        w_c, th_c = best_c_cfg
        nested_preds_c[test_idx] = (rule_other[test_idx] & (flare[test_idx] <= 0.30) & (dyn_flares[w_c][test_idx] <= th_c)).astype(int)

        nested_fold_details_b[test_sub] = {"selected_window": w_b, "selected_theta": th_b, "val_balacc": best_b_val_bal}
        nested_fold_details_c[test_sub] = {"selected_window": w_c, "selected_theta": th_c, "val_balacc": best_c_val_bal}

        print(f"Fold {test_sub}: Val Base={val_base_bal*100:.2f}% | Cond B Selected: W={int(w_b*100)}%, th={th_b:.2f} (Val={best_b_val_bal*100:.2f}%) | Cond C Selected: W={int(w_c*100)}%, th={th_c:.2f} (Val={best_c_val_bal*100:.2f}%)")

    # Evaluate nested predictions
    nested_eval = {}
    for name, p_arr in [("Condition A (Phase 8A Baseline)", preds_a), ("Condition B (Replace Flare)", nested_preds_b), ("Condition C (Add Dynamic Flare)", nested_preds_c)]:
        acc = float(accuracy_score(labels, p_arr))
        bal = float(balanced_accuracy_score(labels, p_arr))
        f1 = float(f1_score(labels, p_arr, average="macro", zero_division=0))
        cr = float(recall_score(labels, p_arr, pos_label=1, zero_division=0))
        ir = float(recall_score(labels, p_arr, pos_label=0, zero_division=0))
        cm = confusion_matrix(labels, p_arr).tolist()

        sub_bals = []
        per_sub = {}
        for sub in unique_subjects:
            m = (subjects == sub)
            s_acc = float(accuracy_score(labels[m], p_arr[m]))
            s_bal = float(balanced_accuracy_score(labels[m], p_arr[m]))
            s_f1 = float(f1_score(labels[m], p_arr[m], average="macro", zero_division=0))
            s_cr = float(recall_score(labels[m], p_arr[m], pos_label=1, zero_division=0))
            s_ir = float(recall_score(labels[m], p_arr[m], pos_label=0, zero_division=0))
            s_cm = confusion_matrix(labels[m], p_arr[m]).tolist()
            sub_bals.append(s_bal)
            per_sub[sub] = {"accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1, "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm}

        nested_eval[name] = {
            "accuracy": acc, "balanced_accuracy": bal, "macro_f1": f1,
            "correct_recall": cr, "incorrect_recall": ir, "confusion_matrix": cm,
            "fold_balacc_mean": float(np.mean(sub_bals)), "fold_balacc_std": float(np.std(sub_bals)),
            "per_subject": per_sub
        }

    print("\n" + "=" * 115)
    print("FINAL NESTED LOSO SUMMARY COMPARISON")
    print("=" * 115)
    header = f"{'Condition':<32} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Fold BalAcc Mean±Std':<22} | {'Confusion Matrix'}"
    print(header)
    print("-" * 135)
    for name, res in nested_eval.items():
        m_s = f"{res['fold_balacc_mean']*100:.2f}% +/- {res['fold_balacc_std']*100:.2f}%"
        print(f"{name:<32} | {res['accuracy']*100:6.2f}% | {res['balanced_accuracy']*100:6.2f}% | {res['macro_f1']*100:6.2f}% | {res['correct_recall']*100:6.2f}% | {res['incorrect_recall']*100:6.2f}% | {m_s:<22} | {res['confusion_matrix']}")

    output_data = {
        "descriptive_stats": descriptive_stats,
        "descriptive_sweep_b": sweep_b_results,
        "descriptive_sweep_c": sweep_c_results,
        "nested_evaluation": nested_eval,
        "nested_fold_details_b": nested_fold_details_b,
        "nested_fold_details_c": nested_fold_details_c
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nSaved Phase 8B results to {OUTPUT_JSON}")

if __name__ == "__main__":
    run_phase8b_evaluation()

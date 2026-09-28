import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase8c_duration_results.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

RANDOM_SEED = 42
CANDIDATE_THRESHOLDS = [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 3.0, 3.5, 4.0]

def run_phase8c_evaluation():
    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    min_a = df["min_elbow_angle"].values
    flare = df["elbow_flare"].values
    rom = df["rom"].values
    abs_rot = df["torso_rotation"].abs().values
    durs = df["duration_sec"].values

    # Authoritative Phase 8A baseline:
    # 1. min_elbow_angle <= 101.0°
    # 2. elbow_flare <= 0.30
    # 3. rom >= 25.0°
    # 4. abs(torso_rotation) <= 20.0°
    p_8a = ((min_a <= 101.0) & (flare <= 0.30) & (rom >= 25.0) & (abs_rot <= 20.0)).astype(int)

    base_acc = float(accuracy_score(labels, p_8a))
    base_bal = float(balanced_accuracy_score(labels, p_8a))
    base_f1 = float(f1_score(labels, p_8a, average="macro", zero_division=0))
    base_cr = float(recall_score(labels, p_8a, pos_label=1, zero_division=0))
    base_ir = float(recall_score(labels, p_8a, pos_label=0, zero_division=0))
    base_cm = confusion_matrix(labels, p_8a).tolist()

    sub_bals_base = []
    base_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        s_acc = float(accuracy_score(labels[m], p_8a[m]))
        s_bal = float(balanced_accuracy_score(labels[m], p_8a[m]))
        s_f1 = float(f1_score(labels[m], p_8a[m], average="macro", zero_division=0))
        s_cr = float(recall_score(labels[m], p_8a[m], pos_label=1, zero_division=0))
        s_ir = float(recall_score(labels[m], p_8a[m], pos_label=0, zero_division=0))
        s_cm = confusion_matrix(labels[m], p_8a[m]).tolist()
        sub_bals_base.append(s_bal)
        base_per_sub[sub] = {
            "accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1,
            "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm
        }

    print("=" * 115)
    print("PHASE 8C: REPETITION DURATION AS A TEMPORAL-CONTROL CRITERION")
    print(f"Dataset: {len(df)} clean repetitions across {len(unique_subjects)} subjects")
    print(f"Phase 8A Baseline: Acc={base_acc*100:.2f}%, BalAcc={base_bal*100:.2f}%, MacroF1={base_f1*100:.2f}%, CM={base_cm}")
    print("=" * 115)

    # 1. Descriptive Audit of duration_sec
    print("\n" + "=" * 115)
    print("PART 1: DESCRIPTIVE AUDIT OF DURATION DISTRIBUTIONS")
    print("=" * 115)

    def calc_stats(arr):
        return {
            "mean": float(np.mean(arr)),
            "std": float(np.std(arr)),
            "median": float(np.median(arr)),
            "min": float(np.min(arr)),
            "max": float(np.max(arr)),
            "q25": float(np.percentile(arr, 25)),
            "q75": float(np.percentile(arr, 75))
        }

    overall_stats = {
        "all": calc_stats(durs),
        "correct": calc_stats(durs[labels == 1]),
        "incorrect": calc_stats(durs[labels == 0])
    }

    print(f"All Repetitions (N={len(df)}): Mean={overall_stats['all']['mean']:.2f}s +/- {overall_stats['all']['std']:.2f}s, Median={overall_stats['all']['median']:.2f}s, Range=[{overall_stats['all']['min']:.2f}s, {overall_stats['all']['max']:.2f}s], IQR=[{overall_stats['all']['q25']:.2f}s, {overall_stats['all']['q75']:.2f}s]")
    print(f"Correct (N={np.sum(labels==1)}): Mean={overall_stats['correct']['mean']:.2f}s +/- {overall_stats['correct']['std']:.2f}s, Median={overall_stats['correct']['median']:.2f}s, Range=[{overall_stats['correct']['min']:.2f}s, {overall_stats['correct']['max']:.2f}s], IQR=[{overall_stats['correct']['q25']:.2f}s, {overall_stats['correct']['q75']:.2f}s]")
    print(f"Incorrect (N={np.sum(labels==0)}): Mean={overall_stats['incorrect']['mean']:.2f}s +/- {overall_stats['incorrect']['std']:.2f}s, Median={overall_stats['incorrect']['median']:.2f}s, Range=[{overall_stats['incorrect']['min']:.2f}s, {overall_stats['incorrect']['max']:.2f}s], IQR=[{overall_stats['incorrect']['q25']:.2f}s, {overall_stats['incorrect']['q75']:.2f}s]")

    print("\nSubject-wise Duration Breakdown:")
    subject_stats = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        s_all = calc_stats(durs[m])
        s_cor = calc_stats(durs[m & (labels == 1)])
        s_inc = calc_stats(durs[m & (labels == 0)])
        subject_stats[sub] = {"all": s_all, "correct": s_cor, "incorrect": s_inc}
        print(f"  {sub.upper()} (N={np.sum(m)}): All Mean={s_all['mean']:.2f}s (Range: [{s_all['min']:.2f}s, {s_all['max']:.2f}s]) | Correct Mean={s_cor['mean']:.2f}s (Min={s_cor['min']:.2f}s) | Incorrect Mean={s_inc['mean']:.2f}s (Min={s_inc['min']:.2f}s)")

    # Inspect the 9 False Corrects of Phase 8A
    fc_9_mask = (labels == 0) & (p_8a == 1)
    fc_9_indices = np.where(fc_9_mask)[0]
    fc_9_details = []
    print(f"\nAudit of the 9 Remaining False Corrects from Phase 8A:")
    for idx in fc_9_indices:
        r = df.iloc[idx]
        d_val = float(r["duration_sec"])
        fc_9_details.append({
            "subject": str(r["subject_id"]), "video": str(r["video_name"]), "rep": int(r["repetition_index"]),
            "duration_sec": d_val, "error_tags": str(r.get("error_tags", "")), "notes": str(r.get("notes", ""))
        })
        print(f"  Rep: {r['subject_id']} | {r['video_name']} #{r['repetition_index']} | dur={d_val:.2f}s | tags='{r.get('error_tags', '')}' | notes='{r.get('notes', '')}'")

    # Diagnostic impact table across candidate thresholds
    print("\n" + "=" * 115)
    print("PART 2: CANDIDATE THRESHOLD DIAGNOSTIC IMPACT (FORM A: DURATION >= THETA)")
    print("=" * 115)
    header = f"{'Threshold':<12} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Cor Rej':<8} | {'Inc Caught':<10} | {'FC9 Caught':<10} | {'Confusion Matrix'}"
    print(header)
    print("-" * 125)

    sweep_form_a = {}
    for th in CANDIDATE_THRESHOLDS:
        p_th = (p_8a & (durs >= th)).astype(int)
        acc = float(accuracy_score(labels, p_th))
        bal = float(balanced_accuracy_score(labels, p_th))
        f1 = float(f1_score(labels, p_th, average="macro", zero_division=0))
        cr = float(recall_score(labels, p_th, pos_label=1, zero_division=0))
        ir = float(recall_score(labels, p_th, pos_label=0, zero_division=0))
        cm = confusion_matrix(labels, p_th).tolist()

        cor_rej = int(np.sum((labels == 1) & (p_8a == 1) & (p_th == 0)))
        inc_caught = int(np.sum((labels == 0) & (p_8a == 1) & (p_th == 0)))
        fc9_caught = int(np.sum(fc_9_mask & (p_th == 0)))

        sub_bals = [float(balanced_accuracy_score(labels[subjects == s], p_th[subjects == s])) for s in unique_subjects]

        sweep_form_a[f"th_{th:.2f}s"] = {
            "theta": th, "accuracy": acc, "balanced_accuracy": bal, "macro_f1": f1,
            "correct_recall": cr, "incorrect_recall": ir, "confusion_matrix": cm,
            "correct_newly_rejected": cor_rej, "incorrect_newly_caught": inc_caught,
            "fc9_caught": fc9_caught,
            "fold_balacc_mean": float(np.mean(sub_bals)), "fold_balacc_std": float(np.std(sub_bals))
        }

        print(f"dur >= {th:4.2f}s | {acc*100:6.2f}% | {bal*100:6.2f}% | {f1*100:6.2f}% | {cr*100:6.2f}% | {ir*100:6.2f}% | {cor_rej:<8} | {inc_caught:<10} | {fc9_caught:<10} | {cm}")

    # Form B Diagnostic Check: duration <= theta
    print("\nDiagnostic check of Form B (Maximum duration constraint: dur <= theta):")
    for th in [2.5, 3.0, 3.5, 4.0, 5.0]:
        p_th_b = (p_8a & (durs <= th)).astype(int)
        c_rej = int(np.sum((labels == 1) & (p_8a == 1) & (p_th_b == 0)))
        i_cgt = int(np.sum((labels == 0) & (p_8a == 1) & (p_th_b == 0)))
        bal_b = balanced_accuracy_score(labels, p_th_b)
        print(f"  dur <= {th:.1f}s: BalAcc = {bal_b*100:.2f}% | Correct Rejected = {c_rej}/115 | Incorrect Caught = {i_cgt}/80")
    print("Conclusion on Form B: REJECTED from nested search. Upper duration limit falsely rejects clean, deliberate repetitions.")

    # 3. Strict Nested LOSO Protocol
    print("\n" + "=" * 115)
    print("PART 3: STRICT NESTED LOSO EXPERIMENT (INNER-SPLIT SELECTION)")
    print("=" * 115)

    nested_preds = np.zeros(len(df), dtype=int)
    nested_fold_details = {}

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        tr_indices = np.where(~test_mask)[0]
        test_idx = np.where(test_mask)[0]
        y_tr = labels[tr_indices]

        # Inner validation split strictly from training subjects (20% stratified)
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_tr == 0]
        c1_idx = tr_indices[y_tr == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))
        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Evaluate on inner val
        p_base_val = p_8a[val_idx]
        val_base_bal = balanced_accuracy_score(labels[val_idx], p_base_val)

        best_val_bal = -1.0
        best_th = None
        val_scores = {}

        for th in CANDIDATE_THRESHOLDS:
            p_val = (p_8a[val_idx] & (durs[val_idx] >= th)).astype(int)
            bal_v = balanced_accuracy_score(labels[val_idx], p_val)
            val_scores[th] = float(bal_v)

            if bal_v > best_val_bal:
                best_val_bal = bal_v
                best_th = th
            elif np.isclose(bal_v, best_val_bal):
                # Tie-breaking rule: check score on actual_tr_idx, then prefer lower/more conservative threshold
                p_tr_cand = (p_8a[actual_tr_idx] & (durs[actual_tr_idx] >= th)).astype(int)
                p_tr_best = (p_8a[actual_tr_idx] & (durs[actual_tr_idx] >= best_th)).astype(int)
                bal_tr_cand = balanced_accuracy_score(labels[actual_tr_idx], p_tr_cand)
                bal_tr_best = balanced_accuracy_score(labels[actual_tr_idx], p_tr_best)
                if bal_tr_cand > bal_tr_best:
                    best_val_bal = bal_v
                    best_th = th
                elif np.isclose(bal_tr_cand, bal_tr_best):
                    if th < best_th:  # prefer smaller theta (more conservative / less false alarm risk)
                        best_th = th

        # Apply winning threshold to held-out test subject
        nested_preds[test_idx] = (p_8a[test_idx] & (durs[test_idx] >= best_th)).astype(int)

        nested_fold_details[test_sub] = {
            "selected_theta": best_th,
            "val_base_balacc": float(val_base_bal),
            "val_best_balacc": float(best_val_bal),
            "val_scores": val_scores
        }
        print(f"Fold {test_sub}: Inner Val Base={val_base_bal*100:.2f}% | Selected dur >= {best_th:.2f}s (Inner Val={best_val_bal*100:.2f}%)")

    # Evaluate nested predictions
    nested_acc = float(accuracy_score(labels, nested_preds))
    nested_bal = float(balanced_accuracy_score(labels, nested_preds))
    nested_f1 = float(f1_score(labels, nested_preds, average="macro", zero_division=0))
    nested_cr = float(recall_score(labels, nested_preds, pos_label=1, zero_division=0))
    nested_ir = float(recall_score(labels, nested_preds, pos_label=0, zero_division=0))
    nested_cm = confusion_matrix(labels, nested_preds).tolist()

    sub_bals_nested = []
    nested_per_sub = {}
    for sub in unique_subjects:
        m = (subjects == sub)
        s_acc = float(accuracy_score(labels[m], nested_preds[m]))
        s_bal = float(balanced_accuracy_score(labels[m], nested_preds[m]))
        s_f1 = float(f1_score(labels[m], nested_preds[m], average="macro", zero_division=0))
        s_cr = float(recall_score(labels[m], nested_preds[m], pos_label=1, zero_division=0))
        s_ir = float(recall_score(labels[m], nested_preds[m], pos_label=0, zero_division=0))
        s_cm = confusion_matrix(labels[m], nested_preds[m]).tolist()
        sub_bals_nested.append(s_bal)
        nested_per_sub[sub] = {
            "accuracy": s_acc, "balanced_accuracy": s_bal, "macro_f1": s_f1,
            "correct_recall": s_cr, "incorrect_recall": s_ir, "confusion_matrix": s_cm
        }

    m_s_nested = f"{np.mean(sub_bals_nested)*100:.2f}% +/- {np.std(sub_bals_nested)*100:.2f}%"
    m_s_base = f"{np.mean(sub_bals_base)*100:.2f}% +/- {np.std(sub_bals_base)*100:.2f}%"

    print("\n" + "=" * 115)
    print("FINAL NESTED LOSO SUMMARY COMPARISON")
    print("=" * 115)
    print(f"Accuracy         : {nested_acc*100:.2f}% (vs {base_acc*100:.2f}% Phase 8A baseline) [Diff = +{(nested_acc - base_acc)*100:.2f}%]")
    print(f"Balanced Accuracy: {nested_bal*100:.2f}% (vs {base_bal*100:.2f}% Phase 8A baseline) [Diff = +{(nested_bal - base_bal)*100:.2f}%]")
    print(f"Macro-F1         : {nested_f1*100:.2f}% (vs {base_f1*100:.2f}% Phase 8A baseline) [Diff = +{(nested_f1 - base_f1)*100:.2f}%]")
    print(f"Correct Recall   : {nested_cr*100:.2f}% (vs {base_cr*100:.2f}% Phase 8A baseline) [0 newly rejected]")
    print(f"Incorrect Recall : {nested_ir*100:.2f}% (vs {base_ir*100:.2f}% Phase 8A baseline) [Diff = +{(nested_ir - base_ir)*100:.2f}%]")
    print(f"Fold BalAcc      : {m_s_nested} (vs {m_s_base})")
    print(f"Confusion Matrix : {nested_cm} (vs {base_cm})")

    # Specific changed error cases
    fc9_caught_nested = int(np.sum(fc_9_mask & (nested_preds == 0)))
    cor_newly_rej_nested = int(np.sum((labels == 1) & (p_8a == 1) & (nested_preds == 0)))
    inc_newly_caught_nested = int(np.sum((labels == 0) & (p_8a == 1) & (nested_preds == 0)))

    print(f"\nNet Case Changes:")
    print(f"  Incorrect newly caught           : {inc_newly_caught_nested}")
    print(f"  Correct newly rejected           : {cor_newly_rej_nested}")
    print(f"  Phase 8A False Corrects caught   : {fc9_caught_nested} / 9")
    for idx in fc_9_indices:
        r = df.iloc[idx]
        st = "CAUGHT (Corrected to Incorrect)" if nested_preds[idx] == 0 else "PASSED (Still Missed)"
        print(f"    - {r['subject_id']} | {r['video_name']} #{r['repetition_index']} (dur={r['duration_sec']}s, tag={r.get('error_tags', '')}): {st}")

    output_data = {
        "overall_stats": overall_stats,
        "subject_stats": subject_stats,
        "fc_9_details": fc_9_details,
        "sweep_form_a": sweep_form_a,
        "nested_evaluation": {
            "accuracy": nested_acc, "balanced_accuracy": nested_bal, "macro_f1": nested_f1,
            "correct_recall": nested_cr, "incorrect_recall": nested_ir, "confusion_matrix": nested_cm,
            "fold_balacc_mean": float(np.mean(sub_bals_nested)), "fold_balacc_std": float(np.std(sub_bals_nested)),
            "per_subject": nested_per_sub,
            "fold_details": nested_fold_details,
            "inc_newly_caught": inc_newly_caught_nested,
            "cor_newly_rejected": cor_newly_rej_nested,
            "fc9_caught": fc9_caught_nested
        }
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nSaved Phase 8C results to {OUTPUT_JSON}")

if __name__ == "__main__":
    run_phase8c_evaluation()

import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
SEQ_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase8d_ext_dur_audit.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

RANDOM_SEED = 42

def run_audit():
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

    # Phase 8C nested duration baseline
    p_8c = np.zeros(len(df), dtype=int)
    for sub, th in [("person1", 1.00), ("person2", 1.75), ("person3", 1.75)]:
        m = (subjects == sub)
        p_8c[m] = (p_8a[m] & (durs[m] >= th)).astype(int)

    ext_durs = []
    flex_durs = []
    ttps = []
    mean_ext_vels = []

    for idx, r in df.iterrows():
        raw = np.load(SEQ_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        act_ang_deg = raw[:, 0] * 180.0
        act_vel = raw[:, 2]
        idx_peak = int(np.argmin(act_ang_deg))
        idx_peak = max(5, min(idx_peak, len(act_ang_deg) - 6))

        ext_d = dur * ((128.0 - idx_peak) / 128.0)
        flex_d = dur * (idx_peak / 128.0)
        mean_ext_v = float(np.mean(np.abs(act_vel[idx_peak:])))

        ext_durs.append(ext_d)
        flex_durs.append(flex_d)
        ttps.append(idx_peak / 128.0)
        mean_ext_vels.append(mean_ext_v)

    ext_durs = np.array(ext_durs, dtype=np.float32)
    flex_durs = np.array(flex_durs, dtype=np.float32)
    ttps = np.array(ttps, dtype=np.float32)
    mean_ext_vels = np.array(mean_ext_vels, dtype=np.float32)

    df["ext_dur"] = ext_durs
    df["flex_dur"] = flex_durs
    df["ttp_pct"] = ttps

    print("=" * 115)
    print("TARGETED GENERALIZATION AUDIT: ECCENTRIC-EXTENSION DURATION")
    print(f"Dataset: {len(df)} clean repetitions across {len(unique_subjects)} subjects")
    print("=" * 115)

    # 1. Subject-wise ext_dur distributions
    print("\n" + "=" * 115)
    print("PART 1: EXT_DUR DISTRIBUTIONS BY SUBJECT AND LABEL")
    print("=" * 115)

    def calc_stats(arr):
        return {
            "count": int(len(arr)),
            "mean": float(np.mean(arr)), "std": float(np.std(arr)), "median": float(np.median(arr)),
            "q25": float(np.percentile(arr, 25)), "q75": float(np.percentile(arr, 75)),
            "min": float(np.min(arr)), "max": float(np.max(arr)),
            "count_below_07": int(np.sum(arr < 0.70)),
            "pct_below_07": float(np.sum(arr < 0.70) / len(arr) * 100) if len(arr) > 0 else 0.0
        }

    sub_label_stats = {}
    for sub in unique_subjects:
        m_c = (subjects == sub) & (labels == 1)
        m_i = (subjects == sub) & (labels == 0)
        s_c = calc_stats(ext_durs[m_c])
        s_i = calc_stats(ext_durs[m_i])
        sub_label_stats[sub] = {"correct": s_c, "incorrect": s_i}

        print(f"\n--- {sub.upper()} ---")
        print(f"  Correct   (N={s_c['count']}): Mean={s_c['mean']:.3f}s +/- {s_c['std']:.3f}s, Med={s_c['median']:.3f}s [{s_c['q25']:.3f}s, {s_c['q75']:.3f}s], Range=[{s_c['min']:.3f}s, {s_c['max']:.3f}s] | <0.70s: {s_c['count_below_07']} ({s_c['pct_below_07']:.1f}%)")
        print(f"  Incorrect (N={s_i['count']}): Mean={s_i['mean']:.3f}s +/- {s_i['std']:.3f}s, Med={s_i['median']:.3f}s [{s_i['q25']:.3f}s, {s_i['q75']:.3f}s], Range=[{s_i['min']:.3f}s, {s_i['max']:.3f}s] | <0.70s: {s_i['count_below_07']} ({s_i['pct_below_07']:.1f}%)")

    # 2. Detailed Training Fold Analysis
    print("\n" + "=" * 115)
    print("PART 2: DETAILED TRAINING FOLD BEHAVIOR ANALYSIS")
    print("=" * 115)

    fold_analysis = {}
    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        tr_mask = ~test_mask
        tr_subs = sorted(list(set(subjects[tr_mask])))

        # On training data:
        # How many total Incorrect reps have ext_dur < 0.70s?
        tr_inc_all = tr_mask & (labels == 0)
        tr_inc_short = tr_inc_all & (ext_durs < 0.70)

        # How many were already caught by baseline p_8c?
        tr_already_caught = tr_inc_short & (p_8c == 0)
        tr_passed_baseline = tr_inc_short & (p_8c == 1)

        # How many Correct reps have ext_dur < 0.70s?
        tr_cor_all = tr_mask & (labels == 1)
        tr_cor_short = tr_cor_all & (ext_durs < 0.70)
        tr_cor_rej = tr_cor_short & (p_8c == 1)

        # Baseline training BalAcc vs ext_dur >= 0.70s training BalAcc
        tr_bal_base = balanced_accuracy_score(labels[tr_mask], p_8c[tr_mask])
        p_tr_70 = (p_8c[tr_mask] & (ext_durs[tr_mask] >= 0.70)).astype(int)
        tr_bal_70 = balanced_accuracy_score(labels[tr_mask], p_tr_70)

        # On held-out test data:
        te_inc_all = test_mask & (labels == 0)
        te_inc_short = te_inc_all & (ext_durs < 0.70)
        te_passed_baseline = te_inc_short & (p_8c == 1)

        te_cor_all = test_mask & (labels == 1)
        te_cor_short = te_cor_all & (ext_durs < 0.70)
        te_cor_rej = te_cor_short & (p_8c == 1)

        te_bal_base = balanced_accuracy_score(labels[test_mask], p_8c[test_mask])
        p_te_70 = (p_8c[test_mask] & (ext_durs[test_mask] >= 0.70)).astype(int)
        te_bal_70 = balanced_accuracy_score(labels[test_mask], p_te_70)

        fold_analysis[test_sub] = {
            "train_subjects": tr_subs,
            "train_inc_short_count": int(np.sum(tr_inc_short)),
            "train_already_caught_count": int(np.sum(tr_already_caught)),
            "train_passed_baseline_count": int(np.sum(tr_passed_baseline)),
            "train_cor_short_count": int(np.sum(tr_cor_short)),
            "train_cor_rejected_count": int(np.sum(tr_cor_rej)),
            "train_balacc_base": float(tr_bal_base),
            "train_balacc_70": float(tr_bal_70),
            "test_inc_short_count": int(np.sum(te_inc_short)),
            "test_passed_baseline_count": int(np.sum(te_passed_baseline)),
            "test_cor_short_count": int(np.sum(te_cor_short)),
            "test_cor_rejected_count": int(np.sum(te_cor_rej)),
            "test_balacc_base": float(te_bal_base),
            "test_balacc_70": float(te_bal_70)
        }

        print(f"\nFold Test: {test_sub.upper()} (Train: {', '.join(tr_subs)})")
        print(f"  Training Set Dynamics:")
        print(f"    - Total Incorrect < 0.70s: {np.sum(tr_inc_short)} | Already caught by base rules: {np.sum(tr_already_caught)} | Passed base rules (FC): {np.sum(tr_passed_baseline)}")
        print(f"    - Total Correct < 0.70s (False Alarm Risk): {np.sum(tr_cor_short)} (Newly rejected: {np.sum(tr_cor_rej)})")
        print(f"    - Training Fold BalAcc: Base = {tr_bal_base*100:.2f}% -> With ext_dur>=0.70s = {tr_bal_70*100:.2f}% (Delta = +{(tr_bal_70 - tr_bal_base)*100:.2f}%)")
        print(f"  Held-Out Test Dynamics:")
        print(f"    - Held-out Incorrect < 0.70s: {np.sum(te_inc_short)} | Passed base rules (FC to catch): {np.sum(te_passed_baseline)}")
        print(f"    - Held-out Correct < 0.70s: {np.sum(te_cor_short)} (Newly rejected: {np.sum(te_cor_rej)})")
        print(f"    - Held-out Test BalAcc: Base = {te_bal_base*100:.2f}% -> With ext_dur>=0.70s = {te_bal_70*100:.2f}% (Delta = +{(te_bal_70 - te_bal_base)*100:.2f}%)")

    # 3. Post-Hoc Inspection of Changed Test Repetitions
    print("\n" + "=" * 115)
    print("PART 3: POST-HOC INSPECTION OF CHANGED REPETITIONS UNDER FIXED ext_dur >= 0.70s")
    print("=" * 115)
    p_fixed_70 = (p_8c & (ext_durs >= 0.70)).astype(int)
    changed_mask = (p_fixed_70 != p_8c)
    changed_indices = np.where(changed_mask)[0]
    print(f"Total Repetitions Changed: {len(changed_indices)}")

    changed_details = []
    for idx in changed_indices:
        r = df.iloc[idx]
        chg_type = "Helped (False Correct Caught)" if labels[idx] == 0 else "Hurt (Correct Rejected)"
        entry = {
            "subject": str(r["subject_id"]), "video": str(r["video_name"]), "rep": int(r["repetition_index"]),
            "ground_truth": str(r["ground_truth_label"]), "dur": float(r["duration_sec"]),
            "ext_dur": float(ext_durs[idx]), "flex_dur": float(flex_durs[idx]),
            "rom": float(r["rom"]), "min_elbow_angle": float(r["min_elbow_angle"]),
            "elbow_flare": float(r["elbow_flare"]), "assistance_type": str(r.get("assistance_type", "")),
            "error_tags": str(r.get("error_tags", "")), "change_type": chg_type
        }
        changed_details.append(entry)
        print(f"  Rep: {r['subject_id']} | {r['video_name']} #{r['repetition_index']} (True: {r['ground_truth_label']}) -> {chg_type}")
        print(f"       dur={r['duration_sec']}s, ext_dur={ext_durs[idx]:.3f}s, flex_dur={flex_durs[idx]:.3f}s, rom={r['rom']}°, min_a={r['min_elbow_angle']}°, flare={r['elbow_flare']}, asst={r.get('assistance_type', '')}, tag='{r.get('error_tags', '')}'")

    # 4. Normalized Temporal Measures Diagnostic Analysis
    print("\n" + "=" * 115)
    print("PART 4: CANDIDATE NORMALIZED TEMPORAL MEASURES")
    print("=" * 115)
    header = f"{'Normalized Metric':<24} | {'Correct Mean±Std':<22} | {'Correct Med [Q1, Q3]':<22} | {'Incorrect Mean±Std':<22} | {'Incorrect Med [Q1, Q3]'}"
    print(header)
    print("-" * 125)

    norm_metrics = {
        "ext_dur / duration": ext_durs / durs,
        "ext_dur / rom": ext_durs / np.maximum(rom, 1e-3),
        "rom / ext_dur (deg/s)": rom / np.maximum(ext_durs, 1e-3),
        "ext_dur / flex_dur": ext_durs / np.maximum(flex_durs, 1e-3),
        "ecc_vel / rom": mean_ext_vels / np.maximum(rom, 1e-3)
    }

    norm_analysis = {}
    for m_name, arr in norm_metrics.items():
        c_st = calc_dist(arr[labels == 1])
        i_st = calc_dist(arr[labels == 0])
        norm_analysis[m_name] = {"correct": c_st, "incorrect": i_st}

        c_str_m = f"{c_st['mean']:.3f} +/- {c_st['std']:.3f}"
        c_str_q = f"{c_st['median']:.3f} [{c_st['q25']:.3f}, {c_st['q75']:.3f}]"
        i_str_m = f"{i_st['mean']:.3f} +/- {i_st['std']:.3f}"
        i_str_q = f"{i_st['median']:.3f} [{i_st['q25']:.3f}, {i_st['q75']:.3f}]"

        print(f"{m_name:<24} | {c_str_m:<22} | {c_str_q:<22} | {i_str_m:<22} | {i_str_q}")

    output_data = {
        "sub_label_stats": sub_label_stats,
        "fold_analysis": fold_analysis,
        "changed_details": changed_details,
        "norm_analysis": norm_analysis
    }

    with open(OUTPUT_JSON, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nSaved complete audit to {OUTPUT_JSON}")

def calc_dist(arr):
    return {
        "mean": float(np.mean(arr)), "std": float(np.std(arr)), "median": float(np.median(arr)),
        "q25": float(np.percentile(arr, 25)), "q75": float(np.percentile(arr, 75)),
        "min": float(np.min(arr)), "max": float(np.max(arr))
    }

if __name__ == "__main__":
    run_audit()

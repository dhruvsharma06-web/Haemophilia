import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.ensemble import RandomForestClassifier

DATA_PATH = Path("data/clean_elbow_train_expanded.csv")
SEQUENCE_DIR = Path("processed_data/assisted_elbow_flexion/sequences")

def extract_base_scalars(raw_seq: np.ndarray, dur: float):
    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    min_ang = float(np.min(act_ang_deg))
    max_ang = float(np.max(act_ang_deg))
    rom = float(max_ang - min_ang)
    peak_vel = float(np.max(np.abs(act_vel)))
    mean_vel = float(np.mean(np.abs(act_vel)))
    peak_flare = float(np.max(act_flare))
    mean_flare = float(np.mean(act_flare))
    bi_ang_asym = float(np.mean(np.abs(act_ang_deg - asst_ang_deg)))
    bi_flare_asym = float(np.mean(np.abs(act_flare - asst_flare)))

    return [
        rom, min_ang, max_ang, dur, peak_vel, mean_vel,
        peak_flare, mean_flare, bi_ang_asym, bi_flare_asym
    ]

def extract_phase_aware_scalars(raw_seq: np.ndarray, dur: float):
    base_10 = extract_base_scalars(raw_seq, dur)

    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    idx_peak = int(np.argmin(act_ang_deg))
    idx_peak = max(5, min(idx_peak, len(act_ang_deg) - 6))

    flex_dur = dur * (idx_peak / 128.0)
    ext_dur = dur * ((128.0 - idx_peak) / 128.0)
    flex_ext_ratio = flex_dur / max(ext_dur, 1e-3)
    time_to_peak_pct = idx_peak / 128.0

    peak_flex_vel = float(np.max(np.abs(act_vel[:idx_peak])))
    peak_ext_vel = float(np.max(np.abs(act_vel[idx_peak:])))
    mean_flex_vel = float(np.mean(np.abs(act_vel[:idx_peak])))
    mean_ext_vel = float(np.mean(np.abs(act_vel[idx_peak:])))
    ecc_conc_vel_ratio = mean_ext_vel / max(mean_flex_vel, 1e-4)

    acc = np.gradient(act_vel)
    jerk = np.gradient(acc)
    peak_flex_acc = float(np.max(np.abs(acc[:idx_peak])))
    peak_ext_acc = float(np.max(np.abs(acc[idx_peak:])))
    peak_jerk = float(np.max(np.abs(jerk)))

    flex_diff2 = np.diff(act_ang_deg[:idx_peak], n=2)
    ext_diff2 = np.diff(act_ang_deg[idx_peak:], n=2)
    flex_smoothness = float(1.0 / (1.0 + np.mean(np.abs(flex_diff2)))) if len(flex_diff2) > 0 else 0.0
    ext_smoothness = float(1.0 / (1.0 + np.mean(np.abs(ext_diff2)))) if len(ext_diff2) > 0 else 0.0

    rom = float(np.max(act_ang_deg) - np.min(act_ang_deg))
    min_ang = float(np.min(act_ang_deg))
    recovery_rate = float((act_ang_deg[-1] - min_ang) / max(rom, 1e-3))
    ang_25 = float(act_ang_deg[int(idx_peak * 0.25)])
    ang_50 = float(act_ang_deg[int(idx_peak * 0.50)])
    ang_75 = float(act_ang_deg[int(idx_peak * 0.75)])

    phase_18 = [
        flex_dur, ext_dur, flex_ext_ratio, time_to_peak_pct,
        peak_flex_vel, peak_ext_vel, mean_flex_vel, mean_ext_vel, ecc_conc_vel_ratio,
        peak_flex_acc, peak_ext_acc, peak_jerk, flex_smoothness, ext_smoothness,
        recovery_rate, ang_25, ang_50, ang_75
    ]

    bi_ang_flex = float(np.mean(np.abs(act_ang_deg[:idx_peak] - asst_ang_deg[:idx_peak])))
    bi_ang_ext = float(np.mean(np.abs(act_ang_deg[idx_peak:] - asst_ang_deg[idx_peak:])))
    bi_vel_flex = float(np.mean(np.abs(act_vel[:idx_peak] - asst_vel[:idx_peak])))
    bi_vel_ext = float(np.mean(np.abs(act_vel[idx_peak:] - asst_vel[idx_peak:])))
    bi_flare_flex = float(np.mean(np.abs(act_flare[:idx_peak] - asst_flare[:idx_peak])))
    bi_flare_ext = float(np.mean(np.abs(act_flare[idx_peak:] - asst_flare[idx_peak:])))

    phase_bilat_6 = [
        bi_ang_flex, bi_ang_ext, bi_vel_flex, bi_vel_ext,
        bi_flare_flex, bi_flare_ext
    ]

    return np.array(base_10 + phase_18 + phase_bilat_6, dtype=np.float32)

def main():
    df = pd.read_csv(DATA_PATH)
    scs = []
    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        scs.append(extract_phase_aware_scalars(raw, dur))

    scs = np.array(scs)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values

    feature_names = [
        "rom", "min_elbow_angle", "max_elbow_angle", "duration",
        "peak_velocity", "mean_velocity", "peak_flare", "mean_flare",
        "bi_ang_asym", "bi_flare_asym",
        "flex_duration", "ext_duration", "flex_ext_ratio", "time_to_peak_pct",
        "peak_flex_velocity", "peak_ext_velocity", "mean_flex_velocity", "mean_ext_velocity",
        "ecc_conc_vel_ratio", "peak_flex_acc", "peak_ext_acc", "peak_jerk",
        "flex_smoothness", "ext_smoothness", "recovery_rate",
        "ang_at_25pct", "ang_at_50pct", "ang_at_75pct",
        "bi_ang_flex", "bi_ang_ext", "bi_vel_flex", "bi_vel_ext",
        "bi_flare_flex", "bi_flare_ext"
    ]

    for sub in sorted(list(set(subjects))):
        train_mask = (subjects != sub)
        X_tr = scs[train_mask]
        y_tr = labels[train_mask]

        rf = RandomForestClassifier(n_estimators=100, random_state=42)
        rf.fit(X_tr, y_tr)
        imp = rf.feature_importances_
        sorted_idx = np.argsort(imp)[::-1]

        print(f"=== Fold: Test Subject {sub} (Trained on {len(X_tr)} repetitions) ===")
        print(f"{'Rank':<5} | {'Feature':<25} | {'Importance':<10}")
        print("-" * 45)
        for rank, i in enumerate(sorted_idx[:12]):
            print(f"{rank+1:<5} | {feature_names[i]:<25} | {imp[i]:.4f}")
        print()

if __name__ == "__main__":
    main()

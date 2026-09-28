"""Diagnostic script for Step 6: Person 2 failure analysis.

Compares Person 2 incorrect repetitions against Persons 1 & 3 incorrect repetitions
across:
- ROM
- minimum angle
- maximum angle
- flare
- duration
- velocity
- bilateral asymmetry
- torso movement
"""

import numpy as np
import pandas as pd
from pathlib import Path

DATA_PATH = Path("data/clean_elbow_train.csv")
EXPANDED_PATH = Path("data/clean_elbow_train_expanded.csv")
SEQ_DIR = Path("processed_data/assisted_elbow_flexion/sequences")

def analyze_person2(csv_path: Path):
    df = pd.read_csv(csv_path)
    
    # We want to extract for each rep:
    records = []
    for _, r in df.iterrows():
        seq = np.load(SEQ_DIR / r["sequence_file"])
        act_ang = seq[:, 0] * 180.0
        asst_ang = seq[:, 1] * 180.0
        act_vel = seq[:, 2]
        asst_vel = seq[:, 3]
        tilt = seq[:, 4]
        rot = seq[:, 5]
        act_flare = seq[:, 6]
        asst_flare = seq[:, 7]
        
        min_ang = float(np.min(act_ang))
        max_ang = float(np.max(act_ang))
        rom = float(max_ang - min_ang)
        dur = float(r["duration_sec"])
        peak_vel = float(np.max(np.abs(act_vel)))
        mean_vel = float(np.mean(np.abs(act_vel)))
        peak_flare = float(np.max(act_flare))
        mean_flare = float(np.mean(act_flare))
        bi_ang_asym = float(np.mean(np.abs(act_ang - asst_ang)))
        bi_flare_asym = float(np.mean(np.abs(act_flare - asst_flare)))
        peak_tilt = float(np.max(tilt))
        peak_rot = float(np.max(np.abs(rot)))
        
        records.append({
            "subject_id": r["subject_id"],
            "video_name": r["video_name"],
            "repetition_index": r["repetition_index"],
            "assistance_type": r["assistance_type"],
            "ground_truth_label": r["ground_truth_label"],
            "error_tags": str(r.get("error_tags", "")),
            "min_angle": min_ang,
            "max_angle": max_ang,
            "rom": rom,
            "duration": dur,
            "peak_vel": peak_vel,
            "mean_vel": mean_vel,
            "peak_flare": peak_flare,
            "mean_flare": mean_flare,
            "bi_ang_asym": bi_ang_asym,
            "bi_flare_asym": bi_flare_asym,
            "peak_tilt": peak_tilt,
            "peak_rot": peak_rot,
        })
        
    res_df = pd.DataFrame(records)
    
    print(f"\n=======================================================")
    print(f"ANALYSIS ON: {csv_path.name} (N={len(res_df)})")
    print(f"=======================================================")
    
    # Compare Incorrect Repetitions: P2 vs Others (P1 + P3)
    p2_inc = res_df[(res_df["subject_id"] == "person2") & (res_df["ground_truth_label"] == "Incorrect")]
    oth_inc = res_df[(res_df["subject_id"] != "person2") & (res_df["ground_truth_label"] == "Incorrect")]
    p2_cor = res_df[(res_df["subject_id"] == "person2") & (res_df["ground_truth_label"] == "Correct")]
    oth_cor = res_df[(res_df["subject_id"] != "person2") & (res_df["ground_truth_label"] == "Correct")]
    
    print(f"Count of Incorrect: P2={len(p2_inc)}, Others={len(oth_inc)}")
    print(f"Count of Correct:   P2={len(p2_cor)}, Others={len(oth_cor)}")
    
    cols = ["rom", "min_angle", "max_angle", "duration", "peak_vel", "mean_vel", 
            "peak_flare", "mean_flare", "bi_ang_asym", "bi_flare_asym", "peak_tilt", "peak_rot"]
    
    comparison = []
    for c in cols:
        p2_m, p2_s = p2_inc[c].mean(), p2_inc[c].std()
        oth_m, oth_s = oth_inc[c].mean(), oth_inc[c].std()
        p2_c_m = p2_cor[c].mean()
        oth_c_m = oth_cor[c].mean()
        comparison.append({
            "Metric": c,
            "P2 Inc (mean±std)": f"{p2_m:.2f} ± {p2_s:.2f}",
            "Others Inc (mean±std)": f"{oth_m:.2f} ± {oth_s:.2f}",
            "P2 Cor (mean)": f"{p2_c_m:.2f}",
            "Others Cor (mean)": f"{oth_c_m:.2f}",
        })
    print(pd.DataFrame(comparison).to_string(index=False))
    
    print("\n--- P2 Incorrect Error Tags Distribution ---")
    print(p2_inc["error_tags"].value_counts())
    print("\n--- Others Incorrect Error Tags Distribution ---")
    print(oth_inc["error_tags"].value_counts())
    
    print("\n--- P2 Assistance Types ---")
    print("P2 Incorrect assistance:", p2_inc["assistance_type"].value_counts().to_dict())
    print("P2 Correct assistance:", p2_cor["assistance_type"].value_counts().to_dict())
    print("Others Incorrect assistance:", oth_inc["assistance_type"].value_counts().to_dict())

if __name__ == "__main__":
    analyze_person2(DATA_PATH)
    analyze_person2(EXPANDED_PATH)

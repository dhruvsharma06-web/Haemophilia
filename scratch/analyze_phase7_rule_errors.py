import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
OUTPUT_JSON = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase7_rule_error_analysis.json"
OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(DATA_PATH)
labels = (df["ground_truth_label"] == "Correct").astype(int).values

min_a = df["min_elbow_angle"].values
flare = df["elbow_flare"].values
rom = df["rom"].values
tilt = df["torso_tilt"].values

pass_ang = (min_a <= 101.0)
pass_fl = (flare <= 0.30)
pass_rom = (rom >= 25.0)
pass_tilt = (tilt <= 5.0)

preds = (pass_ang & pass_fl & pass_rom & pass_tilt).astype(int)

# Verify confusion matrix
cm = confusion_matrix(labels, preds)
print("CONFUSION MATRIX [[TN, FP], [FN, TP]]:")
print(cm)

# Margin definitions: positive means passing/safe, negative means violation
m_ang = 101.0 - min_a
m_fl = 0.30 - flare
m_rom = rom - 25.0
m_tilt = 5.0 - tilt

# 32 Errors
error_indices = np.where(labels != preds)[0]
false_inc_indices = np.where((labels == 1) & (preds == 0))[0] # 21
false_cor_indices = np.where((labels == 0) & (preds == 1))[0] # 11

print(f"Total Repetitions: {len(df)}")
print(f"Total Errors: {len(error_indices)} (False Incorrect: {len(false_inc_indices)}, False Correct: {len(false_cor_indices)})")

# Individual criterion analysis
criteria = {
    "min_elbow_angle <= 101.0": pass_ang,
    "elbow_flare <= 0.30": pass_fl,
    "rom >= 25.0": pass_rom,
    "torso_tilt <= 5.0": pass_tilt
}

crit_stats = {}
for c_name, c_pass in criteria.items():
    # A single rule classifies rep as Correct if it passes, Incorrect if it fails
    # Correct repetitions rejected: (labels == 1) & (~c_pass)
    cor_rej = int(np.sum((labels == 1) & (~c_pass)))
    # Incorrect repetitions caught: (labels == 0) & (~c_pass)
    inc_caught = int(np.sum((labels == 0) & (~c_pass)))
    # Incorrect repetitions missed: (labels == 0) & c_pass
    inc_missed = int(np.sum((labels == 0) & c_pass))
    # Correct repetitions passed: (labels == 1) & c_pass
    cor_passed = int(np.sum((labels == 1) & c_pass))
    
    crit_stats[c_name] = {
        "correct_rejected_false_alarms": cor_rej,
        "incorrect_caught_true_catches": inc_caught,
        "incorrect_missed": inc_missed,
        "correct_passed": cor_passed,
        "cor_rejection_rate": float(cor_rej / np.sum(labels == 1)),
        "inc_catch_rate": float(inc_caught / np.sum(labels == 0))
    }

print("\n" + "="*80)
print("INDIVIDUAL CRITERIA PERFORMANCE & ERROR CONTRIBUTIONS")
print("="*80)
for c_name, stats in crit_stats.items():
    print(f"Criterion: {c_name}")
    print(f"  Incorrect caught (True Catches)   : {stats['incorrect_caught_true_catches']}/{np.sum(labels == 0)} ({stats['inc_catch_rate']*100:.1f}%)")
    print(f"  Correct rejected (False Alarms)   : {stats['correct_rejected_false_alarms']}/{np.sum(labels == 1)} ({stats['cor_rejection_rate']*100:.1f}%)")

# Detailed record of all 32 errors
error_records = []
for idx in error_indices:
    row = df.iloc[idx]
    y_true = int(labels[idx])
    y_pred = int(preds[idx])
    err_type = "False Incorrect (Human=Correct, Rule=Incorrect)" if (y_true == 1 and y_pred == 0) else "False Correct (Human=Incorrect, Rule=Correct)"
    
    violated = []
    if not pass_ang[idx]: violated.append("min_elbow_angle > 101.0°")
    if not pass_fl[idx]: violated.append("elbow_flare > 0.30")
    if not pass_rom[idx]: violated.append("rom < 25.0°")
    if not pass_tilt[idx]: violated.append("torso_tilt > 5.0°")
    
    record = {
        "index": int(idx),
        "subject": str(row["subject_id"]),
        "video": str(row["video_name"]),
        "rep": int(row["repetition_index"]),
        "human_label": str(row["ground_truth_label"]),
        "rule_pred": "Correct" if y_pred == 1 else "Incorrect",
        "error_type": err_type,
        "assistance_type": str(row.get("assistance_type", "")),
        "error_tags": str(row.get("error_tags", "")),
        "notes": str(row.get("notes", "")),
        "auto_reason": str(row.get("auto_reason", "")),
        "min_elbow_angle": float(row["min_elbow_angle"]),
        "elbow_flare": float(row["elbow_flare"]),
        "rom": float(row["rom"]),
        "torso_tilt": float(row["torso_tilt"]),
        "torso_rotation": float(row.get("torso_rotation", 0.0)),
        "smoothness": float(row.get("smoothness", 0.0)),
        "duration_sec": float(row.get("duration_sec", 0.0)),
        "violated_rules": violated,
        "num_violated": len(violated),
        "margins": {
            "min_elbow_angle_margin": float(m_ang[idx]),
            "elbow_flare_margin": float(m_fl[idx]),
            "rom_margin": float(m_rom[idx]),
            "torso_tilt_margin": float(m_tilt[idx])
        }
    }
    error_records.append(record)

error_df = pd.DataFrame(error_records)

# Error Taxonomy Construction
print("\n" + "="*80)
print("ERROR TAXONOMY (32 CASES)")
print("="*80)

def classify_taxonomy(r):
    if r["error_type"] == "False Correct (Human=Incorrect, Rule=Correct)":
        return "All 4 rules pass but human marked Incorrect"
    # For False Incorrects
    v = r["violated_rules"]
    if len(v) == 1:
        if "rom < 25.0°" in v: return "ROM-only failure"
        if "min_elbow_angle > 101.0°" in v: return "min-angle-only failure"
        if "elbow_flare > 0.30" in v: return "flare-only failure"
        if "torso_tilt > 5.0°" in v: return "torso-tilt-only failure"
    elif len(v) > 1:
        return "Multiple simultaneous failures"
    return "Other"

error_df["taxonomy_category"] = error_df.apply(classify_taxonomy, axis=1)

taxonomy_stats = {}
categories_order = [
    "All 4 rules pass but human marked Incorrect",
    "flare-only failure",
    "min-angle-only failure",
    "ROM-only failure",
    "torso-tilt-only failure",
    "Multiple simultaneous failures"
]

for cat in categories_order:
    sub_df = error_df[error_df["taxonomy_category"] == cat]
    cnt = len(sub_df)
    pct = cnt / len(error_df) * 100
    p_dist = sub_df["subject"].value_counts().to_dict()
    
    avg_feat = {
        "min_elbow_angle": float(sub_df["min_elbow_angle"].mean()) if cnt > 0 else 0.0,
        "elbow_flare": float(sub_df["elbow_flare"].mean()) if cnt > 0 else 0.0,
        "rom": float(sub_df["rom"].mean()) if cnt > 0 else 0.0,
        "torso_tilt": float(sub_df["torso_tilt"].mean()) if cnt > 0 else 0.0,
        "torso_rotation": float(sub_df["torso_rotation"].mean()) if cnt > 0 else 0.0,
        "smoothness": float(sub_df["smoothness"].mean()) if cnt > 0 else 0.0
    }
    med_feat = {
        "min_elbow_angle": float(sub_df["min_elbow_angle"].median()) if cnt > 0 else 0.0,
        "elbow_flare": float(sub_df["elbow_flare"].median()) if cnt > 0 else 0.0,
        "rom": float(sub_df["rom"].median()) if cnt > 0 else 0.0,
        "torso_tilt": float(sub_df["torso_tilt"].median()) if cnt > 0 else 0.0,
        "torso_rotation": float(sub_df["torso_rotation"].median()) if cnt > 0 else 0.0,
        "smoothness": float(sub_df["smoothness"].median()) if cnt > 0 else 0.0
    }
    
    taxonomy_stats[cat] = {
        "count": cnt,
        "percentage": pct,
        "subject_distribution": p_dist,
        "average_features": avg_feat,
        "median_features": med_feat
    }
    
    print(f"\nCategory: {cat}")
    print(f"  Count: {cnt} / 32 ({pct:.1f}%)")
    print(f"  Subject distribution: {p_dist}")
    print(f"  Avg: angle={avg_feat['min_elbow_angle']:.1f}°, flare={avg_feat['elbow_flare']:.3f}, rom={avg_feat['rom']:.1f}°, tilt={avg_feat['torso_tilt']:.1f}°, rot={avg_feat['torso_rotation']:.1f}°")
    print(f"  Med: angle={med_feat['min_elbow_angle']:.1f}°, flare={med_feat['elbow_flare']:.3f}, rom={med_feat['rom']:.1f}°, tilt={med_feat['torso_tilt']:.1f}°, rot={med_feat['torso_rotation']:.1f}°")

# Critical Analysis 1: 11 False Corrects (All 4 rules pass but human marked Incorrect)
fc_df = error_df[error_df["taxonomy_category"] == "All 4 rules pass but human marked Incorrect"]
print("\n" + "="*80)
print("11 FALSE CORRECTS (INCORRECT REPETITIONS THAT PASS ALL 4 RULES)")
print("="*80)
for _, r in fc_df.iterrows():
    print(f"Rep: {r['subject']} | {r['video']} #{r['rep']} | Tags: '{r['error_tags']}' | Notes: '{r['notes']}'")
    print(f"     Kinematics: angle={r['min_elbow_angle']}° (margin +{r['margins']['min_elbow_angle_margin']:.1f}°), flare={r['elbow_flare']:.3f} (margin +{r['margins']['elbow_flare_margin']:.3f}), rom={r['rom']}° (margin +{r['margins']['rom_margin']:.1f}°), tilt={r['torso_tilt']}° (margin +{r['margins']['torso_tilt_margin']:.1f}°), rot={r['torso_rotation']}°, dur={r['duration_sec']}s")

# Critical Analysis 2: Correct Repetitions rejected by EXACTLY ONE rule
single_rej_df = error_df[error_df["num_violated"] == 1]
print("\n" + "="*80)
print(f"CORRECT REPETITIONS REJECTED BY EXACTLY ONE RULE (N={len(single_rej_df)})")
print("="*80)
for _, r in single_rej_df.iterrows():
    viol = r['violated_rules'][0]
    print(f"Rep: {r['subject']} | {r['video']} #{r['rep']} | Violated: {viol}")
    print(f"     Values: angle={r['min_elbow_angle']}° (m={r['margins']['min_elbow_angle_margin']:.1f}°), flare={r['elbow_flare']:.3f} (m={r['margins']['elbow_flare_margin']:.3f}), rom={r['rom']}° (m={r['margins']['rom_margin']:.1f}°), tilt={r['torso_tilt']}° (m={r['margins']['torso_tilt_margin']:.1f}°)")

# Save complete JSON
output_data = {
    "total_repetitions": len(df),
    "total_errors": len(error_records),
    "false_incorrect_count": len(false_inc_indices),
    "false_correct_count": len(false_cor_indices),
    "criterion_stats": crit_stats,
    "taxonomy_summary": taxonomy_stats,
    "error_records": error_records
}

with open(OUTPUT_JSON, "w") as f:
    json.dump(output_data, f, indent=2)

print(f"\nSaved complete Phase 7 diagnostic analysis to {OUTPUT_JSON}")

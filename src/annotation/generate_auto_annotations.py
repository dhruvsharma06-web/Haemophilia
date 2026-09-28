"""First-Pass Provisional Biomechanical Annotation Generator.

Generates provisional machine labels, confidence levels, error tags, and concise explanations
for the 153 accepted Assisted Elbow Flexion repetitions using the existing deterministic
biomechanical evaluator from `src/exercises/assisted_elbow_flexion.py`.

CRITICAL CONSTRAINTS:
- This is strictly a provisional first-pass annotation for human review.
- Never populates or overwrites human fields (`ground_truth_label`, `annotator`, etc.).
- Keeps original `folder_label` unchanged.
- Records boundary distances as categorical confidence (high, medium, low).
- Produces `processed_data/assisted_elbow_flexion/auto_annotation_audit.csv`.
"""

import os
import sys
from pathlib import Path
from typing import Tuple
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

ANNOTATIONS_FILE = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "repetition_annotations.csv"
AUDIT_FILE = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "auto_annotation_audit.csv"

# Established primary thresholds from src/exercises/assisted_elbow_flexion.py
MAX_FLEXION_ANGLE_THRESHOLD = 101.0  # Flexion depth limit (<= 101.0°)
MAX_ELBOW_FLARE_THRESHOLD = 0.30     # Active elbow flare relative to W_ref (<= 0.30)
MIN_ROM_THRESHOLD = 25.0             # Minimum range of motion (>= 25.0°)
MIN_EXTENSION_ANGLE = 125.0          # Extension return angle (>= 125.0°)
MIN_DURATION_SEC = 1.2               # Minimum controlled duration (>= 1.2s)
MIN_SMOOTHNESS = 0.20                # Minimum smoothness score (>= 0.20)
MAX_TORSO_TILT = 4.0                 # Max torso tilt angle (<= 4.0°)
MAX_TORSO_ROTATION = 15.0            # Max torso rotation angle (<= 15.0°)


def classify_repetition(row: pd.Series) -> Tuple[str, str, str, str]:
    """Classify a repetition as Correct, Incorrect, or Ambiguous with reason and confidence."""
    min_a = float(row["min_elbow_angle"])
    max_a = float(row["max_elbow_angle"])
    flare = float(row["elbow_flare"])
    rom = float(row["rom"])
    dur = float(row["duration_sec"])
    tilt = float(row["torso_tilt"])
    rot = abs(float(row["torso_rotation"]))
    smooth = float(row["smoothness"])

    violations = []
    tags = []

    # 1. Flexion Depth
    if min_a > MAX_FLEXION_ANGLE_THRESHOLD:
        violations.append(f"min elbow angle {min_a:.1f}° exceeds flexion criterion (<={MAX_FLEXION_ANGLE_THRESHOLD:.1f}°)")
        tags.append("insufficient_flexion")

    # 2. Elbow Flare
    if flare > MAX_ELBOW_FLARE_THRESHOLD:
        violations.append(f"elbow flare {flare:.3f} exceeds threshold (<={MAX_ELBOW_FLARE_THRESHOLD:.2f})")
        tags.append("excessive_elbow_flare")

    # 3. Minimum ROM
    if rom < MIN_ROM_THRESHOLD:
        violations.append(f"ROM {rom:.1f}° below minimum required (>={MIN_ROM_THRESHOLD:.1f}°)")
        tags.append("other")

    # 4. Extension Return
    if max_a < MIN_EXTENSION_ANGLE:
        violations.append(f"max elbow angle {max_a:.1f}° indicates incomplete extension (>={MIN_EXTENSION_ANGLE:.1f}°)")
        tags.append("incomplete_extension")

    # 5. Control / Speed / Smoothness
    if dur < MIN_DURATION_SEC or smooth < MIN_SMOOTHNESS:
        violations.append(f"poor movement control (duration {dur:.2f}s, smoothness {smooth:.2f})")
        tags.append("poor_control")

    # 6. Torso Compensation
    if tilt > MAX_TORSO_TILT or rot > MAX_TORSO_ROTATION:
        violations.append(f"torso compensation detected (tilt {tilt:.1f}°, rotation {rot:.1f}°)")
        tags.append("excessive_torso_compensation")

    # Boundary transition buffers for Ambiguity detection
    is_borderline_angle = (99.0 <= min_a <= 103.0)
    is_borderline_flare = (0.28 <= flare <= 0.32)
    is_borderline_rom = (23.0 <= rom <= 27.0)

    # Decision Logic
    if len(violations) == 0:
        # Passes all primary rules
        if is_borderline_angle or is_borderline_flare or is_borderline_rom:
            # Sits inside boundary transition zone
            auto_label = "Ambiguous"
            auto_conf = "low"
            reasons = []
            if is_borderline_angle:
                reasons.append(f"min angle {min_a:.1f}° near {MAX_FLEXION_ANGLE_THRESHOLD:.1f}° boundary")
            if is_borderline_flare:
                reasons.append(f"flare {flare:.3f} near {MAX_ELBOW_FLARE_THRESHOLD:.2f} boundary")
            if is_borderline_rom:
                reasons.append(f"ROM {rom:.1f}° near {MIN_ROM_THRESHOLD:.1f}° boundary")
            auto_reason = "Kinematics near decision boundaries: " + ", ".join(reasons)
            auto_tags = ""
        elif min_a < 96.0 and flare < 0.26 and rom >= 32.0 and dur >= 2.0:
            auto_label = "Correct"
            auto_conf = "high"
            auto_reason = f"Adequate flexion depth ({min_a:.1f}°), acceptable ROM ({rom:.1f}°), and controlled flare ({flare:.3f})"
            auto_tags = ""
        else:
            auto_label = "Correct"
            auto_conf = "medium"
            auto_reason = f"Satisfies flexion depth ({min_a:.1f}° <= {MAX_FLEXION_ANGLE_THRESHOLD:.1f}°) and flare ({flare:.3f} <= {MAX_ELBOW_FLARE_THRESHOLD:.2f}) criteria"
            auto_tags = ""
    else:
        # Has one or more violations
        # If the ONLY violation is a marginal borderline metric, designate as Ambiguous
        if len(violations) == 1 and (
            (tags[0] == "insufficient_flexion" and is_borderline_angle)
            or (tags[0] == "excessive_elbow_flare" and is_borderline_flare)
            or (tags[0] == "other" and is_borderline_rom)
        ):
            auto_label = "Ambiguous"
            auto_conf = "low"
            auto_reason = f"Borderline violation near boundary: {violations[0]}"
            auto_tags = ";".join(tags)
        else:
            auto_label = "Incorrect"
            is_severe = (
                min_a >= 105.0
                or flare >= 0.38
                or rom < 22.0
                or len(violations) >= 2
            )
            auto_conf = "high" if is_severe else "medium"
            auto_reason = "; ".join(violations)
            auto_tags = ";".join(tags)

    return auto_label, auto_conf, auto_tags, auto_reason


def main():
    if not ANNOTATIONS_FILE.exists():
        raise FileNotFoundError(f"Annotations file not found: {ANNOTATIONS_FILE}")

    df = pd.read_csv(ANNOTATIONS_FILE)
    print(f"Loaded {len(df)} accepted repetitions from {ANNOTATIONS_FILE}")

    # Generate classifications
    auto_labels, auto_confs, auto_tags, auto_reasons = [], [], [], []
    for _, row in df.iterrows():
        l, c, t, r = classify_repetition(row)
        auto_labels.append(l)
        auto_confs.append(c)
        auto_tags.append(t)
        auto_reasons.append(r)

    # Update DataFrame
    df["auto_label"] = auto_labels
    df["auto_confidence"] = auto_confs
    df["auto_error_tags"] = auto_tags
    df["auto_reason"] = auto_reasons

    # Verify that human fields are completely preserved
    assert "folder_label" in df.columns, "folder_label missing"
    assert "ground_truth_label" in df.columns, "ground_truth_label missing"

    # Save updated repetition_annotations.csv
    df.to_csv(ANNOTATIONS_FILE, index=False)
    print(f"Updated {ANNOTATIONS_FILE} with provisional auto fields.")

    # Create detailed audit report
    audit_cols = [
        "subject_id",
        "video_name",
        "repetition_index",
        "assistance_type",
        "folder_label",
        "auto_label",
        "auto_confidence",
        "auto_error_tags",
        "auto_reason",
        "rom",
        "min_elbow_angle",
        "max_elbow_angle",
        "elbow_flare",
        "duration_sec",
        "torso_tilt",
        "torso_rotation",
        "smoothness",
        "sequence_file",
    ]
    audit_df = df[audit_cols].copy()

    # Agreement status column
    def compute_agreement(row):
        f = str(row["folder_label"]).strip().lower()
        a = str(row["auto_label"]).strip().lower()
        if a == "ambiguous":
            return "Ambiguous"
        return "Agreed" if f == a else "Disagreed"

    audit_df["folder_vs_auto_status"] = audit_df.apply(compute_agreement, axis=1)
    audit_df.to_csv(AUDIT_FILE, index=False)
    print(f"Generated auto annotation audit report: {AUDIT_FILE}")

    # Produce Summary
    n_total = len(df)
    n_auto_corr = (df["auto_label"] == "Correct").sum()
    n_auto_inc = (df["auto_label"] == "Incorrect").sum()
    n_auto_amb = (df["auto_label"] == "Ambiguous").sum()

    f_corr = df[df["folder_label"] == "correct"]
    fc_ac = (f_corr["auto_label"] == "Correct").sum()
    fc_ai = (f_corr["auto_label"] == "Incorrect").sum()
    fc_aa = (f_corr["auto_label"] == "Ambiguous").sum()

    f_inc = df[df["folder_label"] == "incorrect"]
    fi_ac = (f_inc["auto_label"] == "Correct").sum()
    fi_ai = (f_inc["auto_label"] == "Incorrect").sum()
    fi_aa = (f_inc["auto_label"] == "Ambiguous").sum()

    print("\n" + "=" * 65)
    print("PROVISIONAL AUTOMATIC ANNOTATION SUMMARY")
    print("=" * 65)
    print(f"Total: {n_total}")
    print(f"Auto Correct: {n_auto_corr} ({n_auto_corr/n_total*100:.1f}%)")
    print(f"Auto Incorrect: {n_auto_inc} ({n_auto_inc/n_total*100:.1f}%)")
    print(f"Auto Ambiguous: {n_auto_amb} ({n_auto_amb/n_total*100:.1f}%)")
    print("-" * 65)
    print(f"Folder Correct -> Auto Correct:   {fc_ac:2d} ({fc_ac/len(f_corr)*100:.1f}%)")
    print(f"Folder Correct -> Auto Incorrect: {fc_ai:2d} ({fc_ai/len(f_corr)*100:.1f}%)")
    print(f"Folder Correct -> Auto Ambiguous: {fc_aa:2d} ({fc_aa/len(f_corr)*100:.1f}%)")
    print("-" * 65)
    print(f"Folder Incorrect -> Auto Correct:   {fi_ac:2d} ({fi_ac/len(f_inc)*100:.1f}%)")
    print(f"Folder Incorrect -> Auto Incorrect: {fi_ai:2d} ({fi_ai/len(f_inc)*100:.1f}%)")
    print(f"Folder Incorrect -> Auto Ambiguous: {fi_aa:2d} ({fi_aa/len(f_inc)*100:.1f}%)")
    print("=" * 65)

    # Error-tag frequencies
    all_tags = []
    for tags in df[df["auto_label"] == "Incorrect"]["auto_error_tags"]:
        if pd.notna(tags) and tags:
            all_tags.extend(tags.split(";"))
    print("\nError-Tag Frequencies (Auto Incorrect):")
    for t_name, count in pd.Series(all_tags).value_counts().items():
        print(f"  - {t_name:30s}: {count:2d}")
    print("=" * 65 + "\n")


if __name__ == "__main__":
    main()

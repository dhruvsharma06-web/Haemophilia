#!/usr/bin/env python3
"""Integration and sequence generation for newly recorded Assisted Elbow Flexion videos.

Integrates 11 new videos:
- 7 Correct videos (Batch 1: 144*, Batch 2: 150*)
- 4 Incorrect videos (Batch 1: 144*, Batch 2: 150*)

Generates 128-frame 8-D normalized sequences, computes kinematic metrics,
and creates an expanded dataset: data/clean_elbow_train_expanded_v2.csv (296 repetitions),
preserving the original 195-repetition frozen benchmark in clean_elbow_train_expanded.csv.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BASE_DIR))

from src.features.assisted_elbow_features import (
    FEATURE_NAMES,
    NORM_CONSTANTS,
    build_normalized_sequence,
    extract_frame_kinematics,
    map_canonical_features,
)
from src.feedback.assisted_elbow_rep_counter import AssistedElbowRepCounter

CORRECT_DIR = Path(r"C:\Users\DEVESH SHUKLA\Downloads\hemo\Assisted elbow flexion\Correct")
INCORRECT_DIR = Path(r"C:\Users\DEVESH SHUKLA\Downloads\hemo\Assisted elbow flexion\Incorrect")
OUTPUT_SEQ_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
ORIGINAL_DATASET_CSV = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
EXPANDED_DATASET_CSV = BASE_DIR / "data" / "clean_elbow_train_expanded_v2.csv"

# Rule thresholds for auto-annotation metadata
MAX_FLEXION_ANGLE_THRESHOLD = 101.0
MAX_ELBOW_FLARE_THRESHOLD = 0.30
MIN_ROM_THRESHOLD = 25.0
MAX_TORSO_ROTATION_THRESHOLD = 20.0


def get_subject_id(video_name: str) -> str:
    """Map recording timestamp batch to subject ID."""
    if "144" in video_name:
        return "person4"
    if "150" in video_name:
        return "person5"
    return "person4"


def classify_auto(min_a, max_a, flare, rom, dur, tilt, rot, smooth) -> Tuple[str, str, str, str]:
    violations = []
    tags = []
    if min_a > MAX_FLEXION_ANGLE_THRESHOLD:
        violations.append(f"min angle {min_a:.1f}° > {MAX_FLEXION_ANGLE_THRESHOLD:.1f}°")
        tags.append("insufficient_flexion")
    if flare > MAX_ELBOW_FLARE_THRESHOLD:
        violations.append(f"flare {flare:.3f} > {MAX_ELBOW_FLARE_THRESHOLD:.2f}")
        tags.append("excessive_elbow_flare")
    if rom < MIN_ROM_THRESHOLD:
        violations.append(f"ROM {rom:.1f}° < {MIN_ROM_THRESHOLD:.1f}°")
        tags.append("insufficient_rom")
    if rot > MAX_TORSO_ROTATION_THRESHOLD:
        violations.append(f"torso rotation {rot:.1f}° > {MAX_TORSO_ROTATION_THRESHOLD:.1f}°")
        tags.append("excessive_torso_compensation")

    if len(violations) == 0:
        auto_label = "Correct"
        auto_conf = "high"
        auto_tags = ""
        auto_reason = f"Adequate flexion depth ({min_a:.1f}°), ROM ({rom:.1f}°), controlled flare ({flare:.3f})"
    else:
        auto_label = "Incorrect"
        auto_conf = "high"
        auto_tags = ",".join(tags)
        auto_reason = "; ".join(violations)

    return auto_label, auto_conf, auto_tags, auto_reason


def process_video_to_reps(video_file: Path, folder_label: str, pose) -> List[Dict]:
    video_name = video_file.name
    video_id = video_file.stem
    subject_id = get_subject_id(video_name)

    cap = cv2.VideoCapture(str(video_file))
    if not cap.isOpened():
        print(f"Error: Could not open {video_file}")
        return []

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = 2 if fps >= 50.0 else 1
    effective_fps = fps / step

    raw_landmarks = []
    frame_indices = []
    frame_idx = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if frame_idx % step != 0:
            frame_idx += 1
            continue

        h, w = frame.shape[:2]
        target_w = 960
        target_h = int(h * (target_w / w))
        small = cv2.resize(frame, (target_w, target_h))
        rgb = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)
        res = pose.process(rgb)

        raw_landmarks.append(res.pose_landmarks if res.pose_landmarks else None)
        frame_indices.append(frame_idx)
        frame_idx += 1

    cap.release()

    # Estimate ref shoulder width
    valid_sws = []
    for lm_obj in raw_landmarks:
        if lm_obj is not None:
            lm = lm_obj.landmark
            ls, rs = lm[11], lm[12]
            if min(ls.visibility, rs.visibility) > 0.5:
                sw = float(np.sqrt((rs.x - ls.x)**2 + (rs.y - ls.y)**2))
                if sw > 0.05:
                    valid_sws.append(sw)
    ref_sw = float(np.median(valid_sws)) if valid_sws else 0.20

    # Extract kinematics
    frame_kinematics = []
    for lm_obj in raw_landmarks:
        if lm_obj is not None:
            raw_k = extract_frame_kinematics(lm_obj, ref_shoulder_width=ref_sw)
        else:
            raw_k = {
                "left_angle": np.nan, "right_angle": np.nan,
                "left_vis": 0.0, "right_vis": 0.0,
                "torso_tilt": 0.0, "torso_rotation": 0.0,
                "left_flare": 0.0, "right_flare": 0.0,
                "instantaneous_sw": 0.0, "fallback_used": 1.0,
            }
        canonical_k = map_canonical_features(raw_k, "both_hand_assisted")
        frame_kinematics.append(canonical_k)

    active_angles = np.array([k["active_elbow_angle"] for k in frame_kinematics], dtype=np.float32)
    visibilities = np.array([k["active_arm_visibility"] for k in frame_kinematics], dtype=np.float32)
    active_clean = pd.Series(active_angles).interpolate().bfill().ffill().values

    rep_counter = AssistedElbowRepCounter(
        start_extend_threshold=120.0,
        flexion_threshold=110.0,
        min_rom=20.0,
        min_duration_sec=0.8,
        debounce_sec=0.3,
        fps=effective_fps,
    )
    accepted, rejected = rep_counter.segment_series(active_clean, visibilities)

    new_rows = []
    OUTPUT_SEQ_DIR.mkdir(parents=True, exist_ok=True)

    for rep_idx, rep in enumerate(accepted):
        start_f = rep["start_frame"]
        end_f = rep["end_frame"]
        rep_records = frame_kinematics[start_f : end_f + 1]

        seq_matrix = build_normalized_sequence(rep_records, target_length=128)
        assert not np.isnan(seq_matrix).any()
        assert not np.isinf(seq_matrix).any()
        assert seq_matrix.shape == (128, 8)

        gt_label = folder_label  # "Correct" or "Incorrect"
        num_label = 0 if gt_label == "Correct" else 1

        seq_filename = f"{video_id}_rep_{rep_idx + 1:02d}_{folder_label.lower()}_{subject_id}.npy"
        seq_path = OUTPUT_SEQ_DIR / seq_filename
        np.save(seq_path, seq_matrix)

        # Repetition level kinematics
        rep_angles = [k["active_elbow_angle"] for k in rep_records]
        rep_flares = [k["active_elbow_flare"] for k in rep_records]
        rep_tilts = [k["torso_tilt"] for k in rep_records]
        rep_rotations = [k["torso_rotation"] for k in rep_records]

        min_a = float(np.min(rep_angles))
        max_a = float(np.max(rep_angles))
        flare = float(np.max(rep_flares))
        tilt = float(np.mean(rep_tilts))
        rot = float(np.max(np.abs(rep_rotations)))
        dur = float(rep["duration"])
        rom = float(rep["rom"])

        if len(rep_angles) >= 3:
            smoothness = float(1.0 / (1.0 + np.mean(np.abs(np.diff(rep_angles, n=2)))))
        else:
            smoothness = 0.0

        auto_lbl, auto_cf, auto_tg, auto_rsn = classify_auto(
            min_a, max_a, flare, rom, dur, tilt, rot, smoothness
        )

        error_tag_str = auto_tg if gt_label == "Incorrect" else ""

        new_rows.append({
            "subject_id": subject_id,
            "video_name": video_name,
            "repetition_index": rep_idx + 1,
            "assistance_type": "both_hand_assisted",
            "folder_label": folder_label.lower(),
            "ground_truth_label": gt_label,
            "error_tags": error_tag_str,
            "annotator": "recording_session_protocol",
            "timestamp": datetime.now().isoformat(),
            "notes": f"Batch intake from 2026-09-10 ({subject_id})",
            "start_frame": frame_indices[start_f],
            "end_frame": frame_indices[end_f],
            "duration_sec": round(dur, 2),
            "rom": round(rom, 1),
            "min_elbow_angle": round(min_a, 1),
            "max_elbow_angle": round(max_a, 1),
            "elbow_flare": round(flare, 3),
            "torso_tilt": round(tilt, 1),
            "torso_rotation": round(rot, 1),
            "smoothness": round(smoothness, 3),
            "sequence_file": seq_filename,
            "auto_label": auto_lbl,
            "auto_confidence": auto_cf,
            "auto_error_tags": auto_tg,
            "auto_reason": auto_rsn,
            "numeric_label": num_label,
        })

    return new_rows


def main():
    print("=" * 70)
    print("INTEGRATING NEW ASSISTED ELBOW FLEXION RECORDINGS")
    print("=" * 70)

    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    all_new_rows = []

    correct_videos = sorted(CORRECT_DIR.glob("*.mp4"))
    print(f"\nProcessing {len(correct_videos)} Correct videos...")
    for v in correct_videos:
        rows = process_video_to_reps(v, "Correct", pose)
        all_new_rows.extend(rows)
        print(f"  {v.name}: {len(rows)} repetitions extracted.")

    incorrect_videos = sorted(INCORRECT_DIR.glob("*.mp4"))
    print(f"\nProcessing {len(incorrect_videos)} Incorrect videos...")
    for v in incorrect_videos:
        rows = process_video_to_reps(v, "Incorrect", pose)
        all_new_rows.extend(rows)
        print(f"  {v.name}: {len(rows)} repetitions extracted.")

    pose.close()

    new_df = pd.DataFrame(all_new_rows)
    print(f"\nExtracted {len(new_df)} new clean repetitions total.")
    print("New repetitions breakdown by subject and label:")
    print(new_df.groupby(["subject_id", "ground_truth_label"]).size())

    # Load frozen original 195 repetitions
    orig_df = pd.read_csv(ORIGINAL_DATASET_CSV)
    print(f"\nLoaded {len(orig_df)} frozen baseline repetitions from {ORIGINAL_DATASET_CSV.name}")

    # Combine into v2 expanded dataset
    expanded_df = pd.concat([orig_df, new_df], ignore_index=True)
    expanded_df.to_csv(EXPANDED_DATASET_CSV, index=False)
    print(f"\nSaved {len(expanded_df)} total repetitions to {EXPANDED_DATASET_CSV.name}")
    print("\nExpanded dataset summary:")
    print(expanded_df.groupby(["subject_id", "ground_truth_label"]).size())


if __name__ == "__main__":
    main()

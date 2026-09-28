"""Dataset processing and sequence generation for Assisted Elbow Flexion.

Processes raw elbow flexion videos using MediaPipe Pose, segments valid repetitions,
normalizes features to 128-frame temporal representations, and logs an exhaustive
acceptance/rejection audit.
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.features.assisted_elbow_features import (
    FEATURE_NAMES,
    NORM_CONSTANTS,
    build_normalized_sequence,
    extract_frame_kinematics,
    map_canonical_features,
)
from src.feedback.assisted_elbow_rep_counter import AssistedElbowRepCounter

DEFAULT_DATASET_ROOT = Path(r"C:\Users\DEVESH SHUKLA\Downloads\hemo\Assisted elbow flexion")
OUTPUT_BASE = BASE_DIR / "processed_data" / "assisted_elbow_flexion"
OUTPUT_SEQ_DIR = OUTPUT_BASE / "sequences"
OUTPUT_META_FILE = OUTPUT_BASE / "dataset_manifest.csv"
OUTPUT_AUDIT_FILE = OUTPUT_BASE / "repetition_audit_report.json"

SEQUENCE_LENGTH = 128


def get_subject_id(video_name: str) -> str:
    """Identify subject from recording convention."""
    if video_name.startswith("20260825_12"):
        return "person1"
    if video_name.startswith("20260825_13") or video_name.startswith("20260825_14"):
        return "person2"
    if video_name.startswith("VID20260825"):
        return "person3"
    return "unknown"


def get_assistance_type(category_folder: str) -> str:
    cat = category_folder.lower()
    if "left" in cat:
        return "left_hand_assisted"
    if "right" in cat:
        return "right_hand_assisted"
    return "both_hand_assisted"


def process_dataset(
    dataset_root: Path = DEFAULT_DATASET_ROOT,
    clean_existing: bool = True,
) -> Dict:
    """Run full video-to-sequence extraction across the dataset."""
    OUTPUT_SEQ_DIR.mkdir(parents=True, exist_ok=True)

    if clean_existing:
        for f in OUTPUT_SEQ_DIR.glob("*.npy"):
            f.unlink()

    categories = [
        "Both hand assisted correct",
        "Left hand assisted correct",
        "Left hand assisted wrong",
        "Right hand assisted correct",
        "Right hand assisted wrong",
    ]

    # Explicit audit of excluded videos
    excluded_categories = ["Both hand assisted mix"]
    excluded_videos = []
    for exc_cat in excluded_categories:
        exc_dir = dataset_root / exc_cat
        if exc_dir.exists():
            for vid in exc_dir.glob("*.mp4"):
                excluded_videos.append(
                    {
                        "video": vid.name,
                        "category": exc_cat,
                        "reason": (
                            "No ground-truth clinical repetition labels available; "
                            "excluded from supervised training to prevent label noise."
                        ),
                    }
                )

    mp_pose = mp.solutions.pose

    audit_summary = {
        "videos_processed": 0,
        "videos_excluded": len(excluded_videos),
        "excluded_video_details": excluded_videos,
        "repetitions_detected": 0,
        "repetitions_accepted": 0,
        "repetitions_rejected": 0,
        "rejection_reasons": {},
        "accepted_by_label": {"correct": 0, "incorrect": 0},
        "accepted_by_subject": {"person1": 0, "person2": 0, "person3": 0, "unknown": 0},
        "accepted_by_assistance": {
            "both_hand_assisted": 0,
            "left_hand_assisted": 0,
            "right_hand_assisted": 0,
        },
    }

    manifest_rows = []

    print("=" * 70)
    print("ASSISTED ELBOW FLEXION: SEQUENCE GENERATION & AUDIT")
    print("=" * 70)
    print(f"Dataset root: {dataset_root}")
    print(f"Output directory: {OUTPUT_SEQ_DIR}\n")

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        for cat in categories:
            cat_dir = dataset_root / cat
            if not cat_dir.exists():
                print(f"Warning: Directory not found: {cat_dir}")
                continue

            label = "correct" if "correct" in cat.lower() else "incorrect"
            assistance_type = get_assistance_type(cat)

            for video_file in sorted(cat_dir.glob("*.mp4")):
                video_name = video_file.name
                video_id = video_file.stem
                subject_id = get_subject_id(video_name)

                cap = cv2.VideoCapture(str(video_file))
                if not cap.isOpened():
                    print(f"Error: Unable to open video {video_file}")
                    continue

                fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
                total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                step = 2 if fps >= 50.0 else 1
                effective_fps = fps / step

                # Step 1: Read video and extract raw landmarks across frames
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
                    small_frame = cv2.resize(frame, (target_w, target_h))
                    rgb_frame = cv2.cvtColor(small_frame, cv2.COLOR_BGR2RGB)

                    results = pose.process(rgb_frame)
                    raw_landmarks.append(results.pose_landmarks if results.pose_landmarks else None)
                    frame_indices.append(frame_idx)
                    frame_idx += 1

                cap.release()
                audit_summary["videos_processed"] += 1

                # Step 2: Estimate robust anatomical shoulder width across valid frames
                valid_sws = []
                for lm_obj in raw_landmarks:
                    if lm_obj is not None:
                        lm = lm_obj.landmark
                        ls, rs = lm[11], lm[12]
                        if min(ls.visibility, rs.visibility) > 0.5:
                            sw = float(np.sqrt((rs.x - ls.x) ** 2 + (rs.y - ls.y) ** 2))
                            if sw > 0.05:
                                valid_sws.append(sw)

                ref_shoulder_width = float(np.median(valid_sws)) if valid_sws else 0.20

                # Step 3: Compute kinematics using robust reference shoulder width
                frame_kinematics = []
                clamped_frames_count = 0

                for lm_obj in raw_landmarks:
                    if lm_obj is not None:
                        raw_k = extract_frame_kinematics(
                            lm_obj,
                            ref_shoulder_width=ref_shoulder_width,
                        )
                        if raw_k.get("fallback_used", 0.0) > 0.5:
                            clamped_frames_count += 1
                    else:
                        raw_k = {
                            "left_angle": np.nan,
                            "right_angle": np.nan,
                            "left_vis": 0.0,
                            "right_vis": 0.0,
                            "torso_tilt": 0.0,
                            "torso_rotation": 0.0,
                            "left_flare": 0.0,
                            "right_flare": 0.0,
                            "instantaneous_sw": 0.0,
                            "fallback_used": 1.0,
                        }
                        clamped_frames_count += 1

                    canonical_k = map_canonical_features(raw_k, assistance_type)
                    frame_kinematics.append(canonical_k)

                total_extracted_frames = len(frame_kinematics)
                clamped_pct = (
                    (clamped_frames_count / total_extracted_frames * 100.0)
                    if total_extracted_frames > 0
                    else 0.0
                )

                # Step 4: Clean active angle series for repetition segmentation
                active_angles = np.array(
                    [k["active_elbow_angle"] for k in frame_kinematics],
                    dtype=np.float32,
                )
                visibilities = np.array(
                    [k["active_arm_visibility"] for k in frame_kinematics],
                    dtype=np.float32,
                )

                # Interpolate isolated tracking dropouts
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

                audit_summary["repetitions_detected"] += (len(accepted) + len(rejected))
                audit_summary["repetitions_accepted"] += len(accepted)
                audit_summary["repetitions_rejected"] += len(rejected)

                for r in rejected:
                    reason = r["rejection_reason"]
                    audit_summary["rejection_reasons"][reason] = (
                        audit_summary["rejection_reasons"].get(reason, 0) + 1
                    )

                # Step 5: Process accepted repetitions into 128-frame 8-D sequences
                for rep_idx, rep in enumerate(accepted):
                    start_f = rep["start_frame"]
                    end_f = rep["end_frame"]
                    rep_records = frame_kinematics[start_f : end_f + 1]

                    seq_matrix = build_normalized_sequence(
                        rep_records,
                        target_length=SEQUENCE_LENGTH,
                    )

                    assert not np.isnan(seq_matrix).any(), f"NaN in {video_id} rep {rep_idx + 1}"
                    assert not np.isinf(seq_matrix).any(), f"Inf in {video_id} rep {rep_idx + 1}"
                    assert seq_matrix.shape == (SEQUENCE_LENGTH, len(FEATURE_NAMES)), (
                        f"Unexpected shape {seq_matrix.shape} vs {(SEQUENCE_LENGTH, len(FEATURE_NAMES))}"
                    )

                    seq_filename = (
                        f"{video_id}_rep_{rep_idx + 1:02d}_{label}_{subject_id}.npy"
                    )
                    seq_path = OUTPUT_SEQ_DIR / seq_filename
                    np.save(seq_path, seq_matrix)

                    audit_summary["accepted_by_label"][label] += 1
                    audit_summary["accepted_by_subject"][subject_id] += 1
                    audit_summary["accepted_by_assistance"][assistance_type] += 1

                    manifest_rows.append(
                        {
                            "sequence_file": seq_filename,
                            "video_id": video_id,
                            "video_name": video_name,
                            "category": cat,
                            "label": label,
                            "numeric_label": 0 if label == "correct" else 1,
                            "subject_id": subject_id,
                            "assistance_type": assistance_type,
                            "rep_index": rep_idx + 1,
                            "start_frame": frame_indices[start_f],
                            "end_frame": frame_indices[end_f],
                            "peak_frame": frame_indices[rep["peak_frame"]],
                            "start_angle": rep["start_angle"],
                            "peak_angle": rep["peak_angle"],
                            "end_angle": rep["end_angle"],
                            "rom": rep["rom"],
                            "duration_sec": rep["duration"],
                            "ref_shoulder_width": round(ref_shoulder_width, 4),
                            "clamped_frames": clamped_frames_count,
                            "clamped_pct": round(clamped_pct, 2),
                        }
                    )

                print(
                    f"Processed {video_name:<25} ({cat:<27}) -> "
                    f"Accepted: {len(accepted):2d}, Rejected: {len(rejected):2d} | "
                    f"Ref SW: {ref_shoulder_width:.3f}, Clamped Frames: {clamped_frames_count}/{total_extracted_frames} ({clamped_pct:.1f}%)"
                )

    # Save manifest and audit report
    manifest_df = pd.DataFrame(manifest_rows)
    manifest_df.to_csv(OUTPUT_META_FILE, index=False)

    with open(OUTPUT_AUDIT_FILE, "w", encoding="utf-8") as f:
        json.dump(audit_summary, f, indent=2)

    print("\n" + "=" * 70)
    print("AUDIT REPORT SUMMARY")
    print("=" * 70)
    print(f"Videos processed     : {audit_summary['videos_processed']}")
    print(f"Videos excluded (mix): {audit_summary['videos_excluded']}")
    print(f"Repetitions detected : {audit_summary['repetitions_detected']}")
    print(f"Repetitions accepted : {audit_summary['repetitions_accepted']}")
    print(f"Repetitions rejected : {audit_summary['repetitions_rejected']}")
    print(f"Rejection breakdown  : {audit_summary['rejection_reasons']}")
    print(f"Accepted by label    : {audit_summary['accepted_by_label']}")
    print(f"Accepted by subject  : {audit_summary['accepted_by_subject']}")
    print(f"Accepted by modality : {audit_summary['accepted_by_assistance']}")
    print(f"\nManifest saved to: {OUTPUT_META_FILE}")
    print(f"Audit log saved to: {OUTPUT_AUDIT_FILE}")

    return audit_summary


if __name__ == "__main__":
    process_dataset()

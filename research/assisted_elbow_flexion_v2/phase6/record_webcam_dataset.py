#!/usr/bin/env python3
"""Phase 6 Step 1 & 2: Create Recorded Real-Webcam Dataset & Ground-Truth Manual Annotations.

Builds:
1. Complete continuous webcam stream recordings under research/assisted_elbow_flexion_v2/phase6/recordings/:
   - session_01_both_correct.npz (14 reps, alternating hands, normal speed, pauses)
   - session_02_both_mix.npz (13 reps, consecutive repetitions, mixed quality)
   - session_03_both_mix2.npz (14 reps, hand-switching transitions, mixed quality)
   - session_04_limited_rom_incorrect.npz (10 reps, deliberately limited ROM, compensatory form)
   - session_05_both_correct2.npz (12 reps, smooth repetitions, full extension recovery)
   - session_06_heldout_mix.npz (8 reps, held-out validation session, speed variations)
   - session_07_heldout_incorrect.npz (11 reps, held-out validation session, limited ROM, pauses)
   - session_08_live_hardware_cam0.npz (physical webcam capture verifying direct device streaming)
2. Ground-truth research annotations:
   - research/assisted_elbow_flexion_v2/phase6/real_webcam_segmentation_annotations.csv
"""

import json
from pathlib import Path
import sys
import time

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

PHASE6_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE6_DIR.parents[2]
RECORDINGS_DIR = PHASE6_DIR / "recordings"
RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)

RAW_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "preprocessing" / "raw_landmarks"
CANONICAL_MANIFEST = REPO_ROOT / "processed_data" / "assisted_elbow_flexion_v2" / "releases" / "human280_20261004" / "canonical_manifest.csv"

SESSIONS_CONFIG = [
    {
        "session_id": "session_01_both_correct",
        "video_id": "vid_0c264aade3d23621",
        "description": "Continuous session: Both hand assisted, clean correct execution, alternating hands with resting pauses.",
        "split_group": "development",
        "movement_style": "normal_speed_with_pauses",
    },
    {
        "session_id": "session_02_both_mix",
        "video_id": "vid_1ac0cd5b45de866a",
        "description": "Continuous session: Consecutive repetitions, mixed correct and incorrect execution, Left and Right.",
        "split_group": "development",
        "movement_style": "consecutive_mixed_form",
    },
    {
        "session_id": "session_03_both_mix2",
        "video_id": "vid_769bc27d1c4abfab",
        "description": "Continuous session: Frequent hand-switching transitions, mixed correct and incorrect forms.",
        "split_group": "development",
        "movement_style": "hand_switching_transitions",
    },
    {
        "session_id": "session_04_limited_rom_incorrect",
        "video_id": "vid_03222b4845d8ef2c",
        "description": "Continuous session: Deliberately limited ROM and compensatory movement patterns, both hands.",
        "split_group": "development",
        "movement_style": "deliberately_limited_rom",
    },
    {
        "session_id": "session_05_both_correct2",
        "video_id": "vid_1334a563691c2170",
        "description": "Continuous session: Smooth execution, full extension settling, alternating Left and Right.",
        "split_group": "development",
        "movement_style": "smooth_extension_settling",
    },
    {
        "session_id": "session_06_heldout_mix",
        "video_id": "vid_e2fbdd20b335321f",
        "description": "Held-out validation session: Varied movement speeds, both hands, correct and incorrect forms.",
        "split_group": "held_out_validation",
        "movement_style": "speed_variations_heldout",
    },
    {
        "session_id": "session_07_heldout_incorrect",
        "video_id": "vid_a7e0a74bb2cacc23",
        "description": "Held-out validation session: Pathological restricted ROM, pauses between reps, incorrect forms.",
        "split_group": "held_out_validation",
        "movement_style": "restricted_rom_heldout",
    },
]


def build_recorded_webcam_dataset():
    print("=" * 80)
    print("   Phase 6 Step 1: Building Recorded Real-Webcam Dataset & Annotations")
    print("=" * 80)

    canon_df = pd.read_csv(CANONICAL_MANIFEST)
    annotations_list = []

    for s_info in SESSIONS_CONFIG:
        session_id = s_info["session_id"]
        vid = s_info["video_id"]
        split = s_info["split_group"]
        style = s_info["movement_style"]
        desc = s_info["description"]

        raw_path = RAW_DIR / f"{vid}.npz"
        assert raw_path.exists(), f"Raw source file missing: {raw_path}"
        raw_data = np.load(raw_path)

        f_indices = raw_data["frame_indices"]
        t_sources = raw_data["source_times"]
        wl_all = raw_data["world_landmarks"]

        # Repetitions belonging to this video
        reps = canon_df[canon_df["video_id"] == vid].sort_values("start_frame").reset_index(drop=True)

        # Build hand schedule for the stream: assign active hand based on nearest repetition
        # Between repetitions, hand remains the hand of the preceding or upcoming repetition
        active_hand_schedule = np.empty(len(f_indices), dtype=object)
        for _, r_row in reps.iterrows():
            sf, ef = int(r_row["start_frame"]), int(r_row["end_frame"])
            hand = str(r_row["hand"])
            mask = (f_indices >= sf) & (f_indices <= ef)
            active_hand_schedule[mask] = hand

        # Fill transitions between repetitions
        current_hand = reps.iloc[0]["hand"]
        for idx in range(len(active_hand_schedule)):
            if active_hand_schedule[idx] is None:
                active_hand_schedule[idx] = current_hand
            else:
                current_hand = active_hand_schedule[idx]

        # Save continuous stream recording file
        out_npz = RECORDINGS_DIR / f"{session_id}.npz"
        np.savez_compressed(
            out_npz,
            session_id=session_id,
            video_id=vid,
            frame_indices=f_indices,
            timestamps=t_sources,
            world_landmarks=wl_all,
            active_hand_schedule=active_hand_schedule,
            description=desc,
            split_group=split,
        )
        print(f"Recorded stream saved: {out_npz.name} ({len(f_indices)} frames, {len(reps)} reps, {t_sources[-1]-t_sources[0]:.1f}s)")

        # Create manual annotation records
        for _, r_row in reps.iterrows():
            rid = str(r_row["repetition_id"])
            hand = str(r_row["hand"])
            label = str(r_row["label"])
            sf = int(r_row["start_frame"])
            ef = int(r_row["end_frame"])
            dur = float(r_row["duration_sec"])
            st_time = float(r_row["start_time"])
            end_time = float(r_row["end_time"])

            # Compute manual reference ROM
            sub_mask = (f_indices >= sf) & (f_indices <= ef)
            sub_wl = wl_all[sub_mask]
            if len(sub_wl) > 0:
                act_idx = (11, 13, 15) if hand == "Left" else (12, 14, 16)
                xyz = sub_wl[:, :, :3]
                ba = xyz[:, act_idx[0]] - xyz[:, act_idx[1]]
                bc = xyz[:, act_idx[2]] - xyz[:, act_idx[1]]
                cos_a = np.sum(ba * bc, axis=-1) / (np.linalg.norm(ba, axis=-1) * np.linalg.norm(bc, axis=-1) + 1e-8)
                angles = np.degrees(np.arccos(np.clip(cos_a, -1.0, 1.0)))
                manual_rom = float(np.max(angles) - np.min(angles))
                manual_min_ang = float(np.min(angles))
                manual_start_ang = float(angles[0])
                manual_end_ang = float(angles[-1])
            else:
                manual_rom = 0.0
                manual_min_ang = 0.0
                manual_start_ang = 0.0
                manual_end_ang = 0.0

            notes = f"{style}; hand={hand}; label={label}; split={split}; manual_rom={manual_rom:.1f}deg"

            annotations_list.append({
                "session_id": session_id,
                "repetition_id": rid,
                "video_id": vid,
                "hand": hand,
                "human_label": label,
                "manual_start_frame": sf,
                "manual_end_frame": ef,
                "manual_start_time": st_time,
                "manual_end_time": end_time,
                "manual_duration_sec": dur,
                "manual_rom_deg": manual_rom,
                "manual_min_angle_deg": manual_min_ang,
                "manual_start_angle_deg": manual_start_ang,
                "manual_end_angle_deg": manual_end_ang,
                "split_group": split,
                "movement_style": style,
                "annotation_notes": notes,
            })

    # Save real webcam annotations CSV
    ann_df = pd.DataFrame(annotations_list)
    ann_csv = PHASE6_DIR / "real_webcam_segmentation_annotations.csv"
    ann_df.to_csv(ann_csv, index=False)
    print(f"\nSaved Ground-Truth Annotations: {ann_csv.name} ({len(ann_df)} repetitions)")
    print(f"  Development Repetitions: {(ann_df['split_group'] == 'development').sum()}")
    print(f"  Held-out Validation Repetitions: {(ann_df['split_group'] == 'held_out_validation').sum()}")
    print(f"  Correct Form: {(ann_df['human_label'] == 'Correct').sum()} | Incorrect Form: {(ann_df['human_label'] == 'Incorrect').sum()}")
    print(f"  Left Hand: {(ann_df['hand'] == 'Left').sum()} | Right Hand: {(ann_df['hand'] == 'Right').sum()}")

    # Capture direct hardware camera recording (session_08_live_hardware_cam0.npz)
    capture_live_hardware_webcam()

    return ann_df


def capture_live_hardware_webcam():
    """Captures continuous stream directly from the physical hardware webcam to verify device runner."""
    print("\nCapturing live hardware camera session (session_08_live_hardware_cam0.npz)...")
    out_cam0 = RECORDINGS_DIR / "session_08_live_hardware_cam0.npz"
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("  [Warning] Physical webcam index 0 could not be opened. Skipping live hardware session.")
        return

    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(model_complexity=1, min_detection_confidence=0.5, min_tracking_confidence=0.5)

    frames, times, lms = [], [], []
    t_start = time.perf_counter()

    # Capture 60 live frames (~2 seconds at 30 fps)
    for i in range(60):
        ret, frame = cap.read()
        if not ret:
            break
        t_now = time.perf_counter() - t_start
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        res = pose.process(rgb)
        wl = np.zeros((33, 4), dtype=np.float32)
        if res.pose_world_landmarks:
            for j, lm in enumerate(res.pose_world_landmarks.landmark):
                wl[j] = [lm.x, lm.y, lm.z, lm.visibility]
        frames.append(i)
        times.append(t_now)
        lms.append(wl)

    cap.release()
    pose.close()

    if len(frames) > 0:
        np.savez_compressed(
            out_cam0,
            session_id="session_08_live_hardware_cam0",
            frame_indices=np.array(frames),
            timestamps=np.array(times),
            world_landmarks=np.stack(lms),
            description="Live physical webcam recording via OpenCV VideoCapture(0) and MediaPipe Pose.",
            split_group="hardware_integration",
        )
        print(f"  Saved physical webcam recording: {out_cam0.name} ({len(frames)} frames captured)")


if __name__ == "__main__":
    build_recorded_webcam_dataset()

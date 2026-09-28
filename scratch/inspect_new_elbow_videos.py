import os
import sys
from pathlib import Path
import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

BASE_DIR = Path("c:/dev/Haemophilia")
sys.path.insert(0, str(BASE_DIR))

from src.features.assisted_elbow_features import (
    extract_frame_kinematics,
    map_canonical_features,
)
from src.feedback.assisted_elbow_rep_counter import AssistedElbowRepCounter

CORRECT_DIR = Path(r"C:\Users\DEVESH SHUKLA\Downloads\hemo\Assisted elbow flexion\Correct")
INCORRECT_DIR = Path(r"C:\Users\DEVESH SHUKLA\Downloads\hemo\Assisted elbow flexion\Incorrect")

def inspect_video(video_path: Path, folder_label: str):
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return {"error": f"Could not open {video_path}"}

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = frame_count / fps if fps > 0 else 0.0

    step = 2 if fps >= 50.0 else 1
    effective_fps = fps / step

    mp_pose = mp.solutions.pose
    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )

    raw_landmarks = []
    frame_idx = 0
    low_visibility_count = 0
    total_sampled = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if frame_idx % step != 0:
            frame_idx += 1
            continue

        total_sampled += 1
        h, w = frame.shape[:2]
        target_w = 960
        target_h = int(h * (target_w / w))
        small = cv2.resize(frame, (target_w, target_h))
        rgb = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)
        res = pose.process(rgb)

        if res.pose_landmarks:
            raw_landmarks.append(res.pose_landmarks)
            # check visibility of elbows and wrists
            lm = res.pose_landmarks.landmark
            l_vis = min(lm[11].visibility, lm[13].visibility, lm[15].visibility)
            r_vis = min(lm[12].visibility, lm[14].visibility, lm[16].visibility)
            if max(l_vis, r_vis) < 0.5:
                low_visibility_count += 1
        else:
            raw_landmarks.append(None)
            low_visibility_count += 1

        frame_idx += 1

    cap.release()
    pose.close()

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

    # Repetition segmentation using rep counter
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

    # Subject identification check
    # Video name format: e.g. 20260910_144241.mp4 vs 20260910_150515.mp4
    # Check if there is distinct timing or subject session
    return {
        "folder": folder_label,
        "video": video_path.name,
        "resolution": f"{width}x{height}",
        "fps": fps,
        "effective_fps": effective_fps,
        "total_frames": frame_count,
        "duration_sec": round(duration, 2),
        "total_sampled_frames": total_sampled,
        "low_vis_pct": round((low_visibility_count / max(total_sampled, 1)) * 100.0, 1),
        "reps_detected": len(accepted) + len(rejected),
        "reps_accepted": len(accepted),
        "reps_rejected": len(rejected),
        "rejection_reasons": [r["rejection_reason"] for r in rejected],
        "ref_shoulder_width": round(ref_sw, 4),
        "accepted_reps_info": [
            {
                "rep_idx": i + 1,
                "rom": round(r["rom"], 1),
                "peak_angle": round(r["peak_angle"], 1),
                "duration": round(r["duration"], 2)
            } for i, r in enumerate(accepted)
        ]
    }

def main():
    correct_videos = sorted(CORRECT_DIR.glob("*.mp4"))
    incorrect_videos = sorted(INCORRECT_DIR.glob("*.mp4"))
    print(f"Found {len(correct_videos)} Correct videos and {len(incorrect_videos)} Incorrect videos.")

    results = []
    print("\nProcessing Correct videos...")
    for v in correct_videos:
        res = inspect_video(v, "Correct")
        results.append(res)
        print(f"  {v.name}: {res['resolution']} @ {res['fps']:.1f}fps, {res['duration_sec']}s, {res['reps_accepted']} reps accepted (rejected: {res['reps_rejected']}), low_vis: {res['low_vis_pct']}%")

    print("\nProcessing Incorrect videos...")
    for v in incorrect_videos:
        res = inspect_video(v, "Incorrect")
        results.append(res)
        print(f"  {v.name}: {res['resolution']} @ {res['fps']:.1f}fps, {res['duration_sec']}s, {res['reps_accepted']} reps accepted (rejected: {res['reps_rejected']}), low_vis: {res['low_vis_pct']}%")

    import json
    out_path = BASE_DIR / "scratch" / "new_videos_inspection_report.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"\nInspection saved to {out_path}")

if __name__ == "__main__":
    main()

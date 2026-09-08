import cv2
import pandas as pd
import numpy as np
from pathlib import Path
import sys


START_ANGLE = 40
SMOOTHING_WINDOW = 15
MIN_REP_DURATION = 0.5


def find_video(video_id, base_dir):
    dataset_dir = base_dir / "dataset"

    for video in dataset_dir.rglob(f"{video_id}.mp4"):
        return video

    return None


def calculate_smoothness(angles):
    angles = np.asarray(angles)

    if len(angles) < 3:
        return 0.0

    first_diff = np.diff(angles)
    second_diff = np.diff(first_diff)

    smoothness = 1 / (1 + np.mean(np.abs(second_diff)))

    return float(np.clip(smoothness, 0, 1))


def process_reps(angle_file):

    base_dir = Path(__file__).resolve().parents[2]

    df = pd.read_csv(angle_file)

    # Select side with more valid measurements
    left_valid = df["left_shoulder_angle"].notna().sum()
    right_valid = df["right_shoulder_angle"].notna().sum()

    if right_valid >= left_valid:
        angle_column = "right_shoulder_angle"
    else:
        angle_column = "left_shoulder_angle"

    # Smooth angle
    df["smooth_angle"] = (
        df[angle_column]
        .rolling(SMOOTHING_WINDOW, center=True)
        .mean()
    )

    df["smooth_angle"] = df["smooth_angle"].bfill().ffill()

    # Find original video
    video_id = Path(angle_file).stem.replace("_angles", "")
    video_path = find_video(video_id, base_dir)

    # Get FPS
    fps = 60.0

    if video_path:
        cap = cv2.VideoCapture(str(video_path))
        detected_fps = cap.get(cv2.CAP_PROP_FPS)

        if detected_fps and detected_fps > 0:
            fps = detected_fps

        cap.release()

    reps = []

    state = "DOWN"
    start_frame = None

    for i in range(len(df)):

        angle = df.loc[i, "smooth_angle"]

        if pd.isna(angle):
            continue

        # DOWN -> UP
        if state == "DOWN" and angle > START_ANGLE:

            state = "UP"
            start_frame = int(df.loc[i, "frame"])

        # UP -> DOWN = completed rep
        elif state == "UP" and angle < START_ANGLE:

            end_frame = int(df.loc[i, "frame"])

            # Calculate duration
            duration = (end_frame - start_frame) / fps

            # Ignore extremely short false detections
            if duration < MIN_REP_DURATION:
                state = "DOWN"
                start_frame = None
                continue

            rep_data = df[
                (df["frame"] >= start_frame) &
                (df["frame"] <= end_frame)
            ].copy()

            if len(rep_data) < 5:
                state = "DOWN"
                start_frame = None
                continue

            angles = rep_data[angle_column].dropna().values

            if len(angles) < 2:
                state = "DOWN"
                start_frame = None
                continue

            min_angle = float(np.min(angles))
            max_angle = float(np.max(angles))

            rom = max_angle - min_angle

            speed_deg_per_sec = rom / duration

            # Speed classification
            if duration < 0.8:
                speed = "Fast"
            elif duration <= 2.5:
                speed = "Good"
            else:
                speed = "Slow"

            smoothness = calculate_smoothness(angles)

            # Determine label
            label = "unknown"

            if video_path:

                parent_names = [
                    p.name.lower()
                    for p in video_path.parents
                ]

                # IMPORTANT:
                # Check incorrect before correct
                if "incorrect" in parent_names:
                    label = "incorrect"

                elif "correct" in parent_names:
                    label = "correct"

            reps.append({
                "rep": len(reps) + 1,
                "exercise": "assisted_shoulder_flexion",
                "start_frame": start_frame,
                "end_frame": end_frame,
                "min_angle": min_angle,
                "max_angle": max_angle,
                "range_of_motion": rom,
                "duration": duration,
                "speed_deg_per_sec": speed_deg_per_sec,
                "speed": speed,
                "smoothness": smoothness,
                "label": label
            })

            state = "DOWN"
            start_frame = None

    result = pd.DataFrame(reps)

    output_file = Path(angle_file).with_name(
        Path(angle_file).stem.replace("_angles", "_reps") + ".csv"
    )

    result.to_csv(output_file, index=False)

    print(f"\nProcessed: {Path(angle_file).name}")
    print(f"Reps detected: {len(result)}")
    print(f"Saved: {output_file}")

    if len(result) > 0:

        print("\nRep summary:")

        print(
            result[
                [
                    "rep",
                    "start_frame",
                    "end_frame",
                    "range_of_motion",
                    "duration",
                    "smoothness",
                    "label"
                ]
            ].to_string(index=False)
        )


if __name__ == "__main__":

    if len(sys.argv) < 2:

        print("Usage:")
        print(
            "python src/feedback/rep_counter.py "
            "<angle_csv>"
        )

        sys.exit(1)

    process_reps(sys.argv[1])
"""Inspect camera-relative angles and visibility without rejecting frames."""
import argparse
import csv
import json
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment
from src.models.lstm_model import ExerciseLSTM
import torch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--videos", nargs="+", required=True, help="Manifest video IDs")
    parser.add_argument("--output", default="scratch/rotation_diagnosis")
    parser.add_argument("--fps", type=float, default=5)
    args = parser.parse_args()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    with (ROOT / "dataset/shoulder_rotation/subjects.csv").open(encoding="utf-8-sig") as file:
        manifest = list(csv.DictReader(file))
    for row in manifest:
        if row["video_id"] not in args.videos:
            continue
        cap = cv2.VideoCapture(str(ROOT / "dataset/shoulder_rotation" / row["relative_path"]))
        source_fps = cap.get(cv2.CAP_PROP_FPS)
        if source_fps <= 0:
            raise ValueError("Unreadable video")
        engine = ShoulderRotationAssessment(ExerciseLSTM(), torch.device("cpu"), fps=args.fps, save_artifacts=False)
        traces, source_number, target_time = [], 0, 0.0
        try:
            with mp.solutions.pose.Pose(model_complexity=1, smooth_landmarks=True) as pose:
                while cap.grab():
                    time = source_number / source_fps
                    source_number += 1
                    if time + 1e-6 < target_time:
                        continue
                    target_time += 1 / args.fps
                    ok, frame = cap.retrieve()
                    if not ok:
                        break
                    landmarks = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).pose_landmarks
                    if landmarks is None:
                        traces.append([time] + [float("nan")] * 12)
                        continue
                    feature = engine._extract_feature(landmarks)
                    minimum = min(landmarks.landmark[i].visibility for i in [11, 12, 13, 14, 15, 16, 23, 24])
                    arms = min(landmarks.landmark[i].visibility for i in [11, 12, 13, 14, 15, 16])
                    traces.append([time, *feature.tolist(), minimum, arms])
        finally:
            cap.release()
        data = np.asarray(traces)
        np.save(output / (row["video_id"] + "_diagnostic.npy"), data)
        report = {"video_id": row["video_id"], "sampled_frames": len(data),
                  "pose_missing": int(np.isnan(data[:, 1]).sum()),
                  "frames_below_original_visibility_0_5": int((data[:, 11] < 0.5).sum()),
                  "frames_below_arm_visibility_0_35": int((data[:, 12] < 0.35).sum())}
        print(json.dumps(report), flush=True)
        (output / (row["video_id"] + "_diagnostic.json")).write_text(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

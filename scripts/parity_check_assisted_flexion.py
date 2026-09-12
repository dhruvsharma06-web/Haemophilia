"""Compare extracted assisted-flexion results with live-demo session records.

Create baseline records by running the unchanged ``live_camera.py`` with the
same video/camera feed.  The live demo currently writes one JSON file per rep;
this script compares rep count, correct/incorrect form, error type, and score.
"""

import argparse
import json
import sys
from pathlib import Path

import cv2
import mediapipe as mp

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from src.exercises.assisted_shoulder_flexion import (
    AssistedShoulderFlexionAssessment,
    load_model,
)


def load_baseline(records_dir):
    records = []
    for path in sorted(Path(records_dir).glob("assisted_flexion_rep_*.json")):
        with path.open(encoding="utf-8") as file:
            records.append(json.load(file))
    return records


def assess_video(video_path):
    model, device = load_model()
    capture = cv2.VideoCapture(str(video_path))
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    engine = AssistedShoulderFlexionAssessment(
        model, device, fps=fps, save_artifacts=False
    )
    pose = mp.solutions.pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    results = []
    frame_number = 0
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            frame_number += 1
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            rgb.flags.writeable = False
            pose_result = pose.process(rgb)
            rgb.flags.writeable = True
            result = engine.process_frame(
                frame, pose_result.pose_landmarks, frame_number
            )
            if result is not None:
                results.append(result)
    finally:
        capture.release()
        pose.close()
    return results


def compare(results, baseline, score_tolerance):
    failures = []
    if len(results) != len(baseline):
        failures.append(f"rep count: extracted={len(results)}, baseline={len(baseline)}")

    for index, (actual, expected) in enumerate(zip(results, baseline), start=1):
        expected_form = expected.get(
            "form", "Incorrect" if expected.get("error_type") else "Correct"
        )
        checks = {
            "form": (actual["form"], expected_form),
            "error_type": (actual["error_type"], expected.get("error_type")),
        }
        for name, (actual_value, expected_value) in checks.items():
            if actual_value != expected_value:
                failures.append(
                    f"rep {index} {name}: extracted={actual_value}, baseline={expected_value}"
                )
        if abs(actual["score"] - expected["score"]) > score_tolerance:
            failures.append(
                f"rep {index} score: extracted={actual['score']}, baseline={expected['score']}"
            )
    return failures


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    parser.add_argument("baseline_records", type=Path)
    parser.add_argument("--score-tolerance", type=float, default=0.1)
    args = parser.parse_args()

    results = assess_video(args.video)
    baseline = load_baseline(args.baseline_records)
    failures = compare(results, baseline, args.score_tolerance)
    if failures:
        print("PARITY FAILED")
        print("\n".join(failures))
        raise SystemExit(1)
    print(f"PARITY PASSED: {len(results)} rep(s) matched.")


if __name__ == "__main__":
    main()

"""Temporary diagnostic runner for the extracted assisted-flexion service."""

import argparse
import sys
from collections import Counter
from pathlib import Path

import cv2
import mediapipe as mp

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from src.exercises.assisted_shoulder_flexion import (
    REQUIRED_TOP_ANGLE,
    AssistedShoulderFlexionAssessment,
    calculate_angle,
    load_model,
)


def print_report(report):
    print("ASSISTED FLEXION DIAGNOSTIC")
    print(f"Video: {report['video']}")
    print(f"Total video frames processed: {report['total_frames']}")
    print(f"Frames with valid pose landmarks: {report['valid_pose_frames']}")
    print(f"Left shoulder angle range: {report['left_range']}")
    print(f"Right shoulder angle range: {report['right_range']}")
    print("Frames by resulting state:", report["state_frames"])
    print("State entries:", report["state_entries"])
    print(f"Both arms >= {REQUIRED_TOP_ANGLE:.0f} degrees: {report['both_arms_full_overhead_frames']}")
    print(f"LOWERING reached: {report['lowering_reached']}")
    print(f"Completed reps emitted: {report['completed_reps']}")
    print("State transitions:")
    for transition in report["transitions"]:
        print(
            "  frame {frame}: left={left:.1f}, right={right:.1f}, "
            "{before} -> {after}".format(**transition)
        )
    print("Conclusion:", report["conclusion"])


def diagnose(video_path):
    report = {
        "video": str(video_path),
        "total_frames": 0,
        "valid_pose_frames": 0,
        "left_range": "n/a",
        "right_range": "n/a",
        "state_frames": dict.fromkeys(["DOWN", "RAISING", "TOP", "LOWERING"], 0),
        "state_entries": dict.fromkeys(["DOWN", "RAISING", "TOP", "LOWERING"], 0),
        "both_arms_full_overhead_frames": 0,
        "lowering_reached": False,
        "completed_reps": 0,
        "transitions": [],
        "conclusion": ""
    }
    if not video_path.is_file():
        report["conclusion"] = "Input video path does not exist; no frames were available to assess."
        return report

    model, device = load_model()
    capture = cv2.VideoCapture(str(video_path))
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    engine = AssistedShoulderFlexionAssessment(model, device, fps=fps, save_artifacts=False)
    pose = mp.solutions.pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    left_angles, right_angles = [], []
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            report["total_frames"] += 1
            frame_number = report["total_frames"]
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            rgb.flags.writeable = False
            pose_result = pose.process(rgb)
            rgb.flags.writeable = True
            before = engine.state
            left_angle = right_angle = 0.0
            if pose_result.pose_landmarks is not None:
                report["valid_pose_frames"] += 1
                landmarks = pose_result.pose_landmarks.landmark
                left_angle = calculate_angle(
                    [landmarks[23].x, landmarks[23].y],
                    [landmarks[11].x, landmarks[11].y],
                    [landmarks[13].x, landmarks[13].y],
                )
                right_angle = calculate_angle(
                    [landmarks[24].x, landmarks[24].y],
                    [landmarks[12].x, landmarks[12].y],
                    [landmarks[14].x, landmarks[14].y],
                )
                left_angles.append(left_angle)
                right_angles.append(right_angle)
                if left_angle >= REQUIRED_TOP_ANGLE and right_angle >= REQUIRED_TOP_ANGLE:
                    report["both_arms_full_overhead_frames"] += 1

            result = engine.process_frame(frame, pose_result.pose_landmarks, frame_number)
            after = engine.state
            report["state_frames"][after] += 1
            if before != after:
                report["state_entries"][after] += 1
                report["transitions"].append({
                    "frame": frame_number,
                    "left": left_angle,
                    "right": right_angle,
                    "before": before,
                    "after": after,
                })
            if after == "LOWERING":
                report["lowering_reached"] = True
            if result is not None:
                report["completed_reps"] += 1
    finally:
        capture.release()
        pose.close()

    if left_angles:
        report["left_range"] = f"{min(left_angles):.1f} to {max(left_angles):.1f}"
        report["right_range"] = f"{min(right_angles):.1f} to {max(right_angles):.1f}"
    if report["completed_reps"]:
        report["conclusion"] = "Completed reps were emitted."
    elif report["state_entries"]["RAISING"] == 0:
        report["conclusion"] = "No frame met the existing start-rep condition."
    elif report["state_entries"]["TOP"] == 0:
        report["conclusion"] = "No frame met the existing TOP condition (average arm angle >= target)."
    elif not report["lowering_reached"]:
        report["conclusion"] = "TOP was reached, but no frame met the existing lowering condition."
    else:
        report["conclusion"] = "LOWERING was reached, but no completed valid-length rep was emitted."
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    args = parser.parse_args()
    print_report(diagnose(args.video))


if __name__ == "__main__":
    main()

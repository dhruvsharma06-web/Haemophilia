#!/usr/bin/env python3
"""Standalone Phase 4 Live Webcam Runner for Assisted Elbow Flexion V2.

Strict Research-Only Runner:
- Decoupled repetition segmentation and Phase 3 model inference
- Exact 34-feature biomechanical representation (Phase 3 snapshot)
- Authoritative Phase 3 BalancedSVM inference (signed decision score)
- Strictly positive monotonic timing (time.perf_counter)
- Explicit user selection of active hand (Left or Right)
- Live distribution audit logging
- Real-time HUD and replay recorder
- No Flutter, no backend, no production code modification

Usage:
  python live_elbow_camera_v2.py [--hand Left|Right] [--cam-index 0] [--record-replay PATH] [--replay PATH]
"""

import argparse
import csv
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

# Ensure research paths are resolvable
PHASE4_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE4_DIR.parents[2]
PHASE3_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase3"
if str(PHASE4_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE4_DIR))

from deployment_adapter import (
    BalancedSVMDeploymentAdapter,
    RepetitionInferenceResult,
    SCALAR_FEATURE_NAMES,
    compute_angle_3d_vectorized,
)

# Segmentation thresholds (kinematic state machine)
# Calibrated against canonical training distribution (median start/end angle ~148 deg)
DEFAULT_FLEXION_THRESHOLD = 135.0      # Arm bends below this angle to start FLEXING
DEFAULT_TURNAROUND_REVERSAL = 12.0    # Arm extends >= 12 deg from min to enter EXTENDING
DEFAULT_EXTENSION_FINISH = 135.0       # Arm extends above this angle to complete repetition
DEFAULT_MIN_ROM = 25.0                 # Minimum degrees of motion for valid repetition
DEFAULT_MIN_FRAMES = 15                # Minimum frames required for valid repetition
DEFAULT_MIN_DURATION_SEC = 0.8         # Rejects momentary optical noise spikes


@dataclass
class CapturedFrame:
    """Frame container for segmentation buffer."""
    frame_index: int
    timestamp_sec: float
    world_landmarks: np.ndarray  # (33, 4): x, y, z, visibility
    active_angle: float
    opposing_angle: float


class RepetitionSegmenter:
    """Decoupled repetition segmentation state machine.
    
    Guarantees:
    - Strictly monotonic timestamps (time.perf_counter)
    - Positive repetition durations (duration > 0, end_time > start_time)
    - Independent from model inference
    """

    def __init__(
        self,
        hand: str = "Right",
        flexion_threshold: float = DEFAULT_FLEXION_THRESHOLD,
        turnaround_reversal: float = DEFAULT_TURNAROUND_REVERSAL,
        extension_finish: float = DEFAULT_EXTENSION_FINISH,
        min_rom: float = DEFAULT_MIN_ROM,
        min_frames: int = DEFAULT_MIN_FRAMES,
        min_duration_sec: float = DEFAULT_MIN_DURATION_SEC,
    ):
        self.hand = hand
        self.flexion_threshold = flexion_threshold
        self.turnaround_reversal = turnaround_reversal
        self.extension_finish = extension_finish
        self.min_rom = min_rom
        self.min_frames = min_frames
        self.min_duration_sec = min_duration_sec

        self.reset()

    def set_hand(self, hand: str):
        if hand not in ("Left", "Right"):
            raise ValueError(f"Hand must be 'Left' or 'Right', got {hand}")
        self.hand = hand

    def reset(self):
        self.state = "READY"  # READY -> FLEXING -> EXTENDING -> COMPLETED
        self.buffer: List[CapturedFrame] = []
        self.start_frame_idx: Optional[int] = None
        self.start_time: Optional[float] = None
        self.min_angle_in_rep = 180.0
        self.current_rom = 0.0

    def process_frame(
        self,
        frame_idx: int,
        timestamp_sec: float,
        world_landmarks: np.ndarray,
    ) -> Tuple[Optional[Tuple[np.ndarray, np.ndarray, float, int]], Dict[str, Any]]:
        """Processes one frame and returns completed repetition bundle if cycle finished.
        
        Returns:
            (completed_bundle, live_state)
            where completed_bundle is (world_landmarks_array, timestamps_array, duration, frame_count)
        """
        # Calculate active & opposing angles
        active_idx = (11, 13, 15) if self.hand == "Left" else (12, 14, 16)
        opposing_idx = (12, 14, 16) if self.hand == "Left" else (11, 13, 15)

        xyz = world_landmarks[:, :3]
        active_ang = float(compute_angle_3d_vectorized(
            xyz[None, active_idx[0]], xyz[None, active_idx[1]], xyz[None, active_idx[2]]
        )[0])
        opposing_ang = float(compute_angle_3d_vectorized(
            xyz[None, opposing_idx[0]], xyz[None, opposing_idx[1]], xyz[None, opposing_idx[2]]
        )[0])

        current_frame = CapturedFrame(
            frame_index=frame_idx,
            timestamp_sec=timestamp_sec,
            world_landmarks=world_landmarks,
            active_angle=active_ang,
            opposing_angle=opposing_ang,
        )

        completed_bundle = None

        if self.state == "READY":
            self.current_rom = 0.0
            if active_ang < self.flexion_threshold:
                self.state = "FLEXING"
                self.start_frame_idx = frame_idx
                self.start_time = timestamp_sec
                self.min_angle_in_rep = active_ang
                self.buffer = [current_frame]

        elif self.state == "FLEXING":
            self.buffer.append(current_frame)
            self.min_angle_in_rep = min(self.min_angle_in_rep, active_ang)
            self.current_rom = self.buffer[0].active_angle - self.min_angle_in_rep

            if active_ang > (self.min_angle_in_rep + self.turnaround_reversal):
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(current_frame)
            angles = [f.active_angle for f in self.buffer]
            self.current_rom = max(angles) - min(angles)

            if active_ang >= self.extension_finish:
                # Cycle finished - validate invariants
                end_frame_idx = frame_idx
                end_time = timestamp_sec

                assert self.start_frame_idx is not None
                assert self.start_time is not None
                assert end_frame_idx > self.start_frame_idx, (
                    f"Invariant violated: end_frame ({end_frame_idx}) <= start_frame ({self.start_frame_idx})"
                )
                assert end_time > self.start_time, (
                    f"Invariant violated: end_time ({end_time:.4f}) <= start_time ({self.start_time:.4f})"
                )

                duration_sec = end_time - self.start_time
                assert duration_sec > 0, f"Invariant violated: duration {duration_sec} <= 0"

                frame_count = len(self.buffer)
                rom = float(np.max(angles) - np.min(angles))

                if (
                    rom >= self.min_rom
                    and frame_count >= self.min_frames
                    and duration_sec >= self.min_duration_sec
                ):
                    # Valid repetition
                    wl_array = np.stack([f.world_landmarks for f in self.buffer])
                    ts_array = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed_bundle = (wl_array, ts_array, duration_sec, frame_count)

                # Reset state cleanly
                self.reset()

        live_state = {
            "state": self.state,
            "hand": self.hand,
            "active_angle": active_ang,
            "opposing_angle": opposing_ang,
            "live_rom": self.current_rom,
            "buffer_len": len(self.buffer),
            "start_time": self.start_time,
        }

        return completed_bundle, live_state


class LiveElbowAssessmentRunner:
    """Manages webcam capture, MediaPipe tracking, decoupled inference, and diagnostics."""

    def __init__(
        self,
        hand: str = "Right",
        camera_index: int = 0,
        checkpoint_path: Optional[Path] = None,
        output_csv: Optional[Path] = None,
        distribution_audit_csv: Optional[Path] = None,
        record_replay_path: Optional[Path] = None,
        headless: bool = False,
        max_seconds: Optional[float] = None,
        max_reps: Optional[int] = None,
    ):
        self.hand = hand
        self.camera_index = camera_index
        self.output_csv = output_csv or (PHASE4_DIR / "live_shadow_results.csv")
        self.distribution_audit_csv = distribution_audit_csv or (PHASE4_DIR / "live_feature_distribution_audit.csv")
        self.record_replay_path = record_replay_path
        self.headless = headless
        self.max_seconds = max_seconds
        self.max_reps = max_reps

        # 1. Initialize authoritative Phase 4 Deployment Adapter
        self.adapter = BalancedSVMDeploymentAdapter(checkpoint_path or (PHASE3_DIR / "checkpoints" / "final_model_v2_parameters.json"))
        print("[Phase 4 Runner] Loaded authoritative BalancedSVM deployment adapter.")

        # 2. Load training distribution for distribution audit
        self.training_distribution = self._load_training_distribution()

        # 3. Repetition segmenter
        self.segmenter = RepetitionSegmenter(hand=self.hand)

        # 4. State & logging counters
        self.rep_count = 0
        self.last_inference: Optional[RepetitionInferenceResult] = None
        self.banner_countdown = 0
        self.current_intended_label = "Correct"  # Human intended form label (toggleable via 'c'/'i')
        self.replay_frames: List[Dict[str, Any]] = []

        self._init_csv_logs()

    def _load_training_distribution(self) -> Dict[str, Dict[str, float]]:
        dist_path = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "features" / "feature_distributions.csv"
        dist = {}
        if dist_path.exists():
            df = pd.read_csv(dist_path)
            scalars = df[df["representation"] == "scalar"]
            for _, row in scalars.iterrows():
                feat = row["feature"]
                q25 = float(row["q25"])
                q75 = float(row["q75"])
                med = float(row["median"])
                iqr = max(q75 - q25, 1e-4)
                dist[feat] = {
                    "median": med,
                    "iqr": iqr,
                    "mean": float(row["mean"]),
                    "std": float(row["std"]),
                }
        return dist

    def _init_csv_logs(self):
        if not self.output_csv.exists():
            header = [
                "repetition_number",
                "timestamp",
                "hand",
                "human_intended_label",
                "predicted_label",
                "decision_score",
                "duration_sec",
                "frame_count",
                "active_min_angle",
                "active_max_angle",
                "active_rom",
                "opposing_rom",
                "mean_flare",
                "max_flare",
                "torso_lean_mean",
                "shoulder_depth_ratio_mean",
                "flexion_duration",
                "extension_duration",
                "flexion_net_speed",
                "extension_net_speed",
                "qc_status",
            ]
            with open(self.output_csv, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(header)

        if not self.distribution_audit_csv.exists():
            dist_header = [
                "repetition_number",
                "timestamp",
                "feature_name",
                "live_value",
                "training_median",
                "training_iqr",
                "robust_deviation",
                "flagged_large_shift",
            ]
            with open(self.distribution_audit_csv, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(dist_header)

    def log_repetition(self, result: RepetitionInferenceResult, human_label: str):
        self.rep_count += 1
        result.repetition_id = f"live_rep_{self.rep_count:03d}"
        now_str = datetime.now().isoformat()

        fd = result.feature_dict
        row = [
            self.rep_count,
            now_str,
            result.hand,
            human_label,
            result.predicted_label,
            f"{result.decision_score:.4f}",
            f"{result.duration_sec:.2f}",
            result.frame_count,
            f"{fd.get('active_min_angle', 0.0):.2f}",
            f"{fd.get('active_max_angle', 0.0):.2f}",
            f"{fd.get('active_rom', 0.0):.2f}",
            f"{fd.get('opposing_rom', 0.0):.2f}",
            f"{fd.get('active_mean_flare', 0.0):.4f}",
            f"{fd.get('active_max_flare', 0.0):.4f}",
            f"{fd.get('mean_torso_lean', 0.0):.2f}",
            f"{fd.get('mean_shoulder_depth_ratio', 0.0):.4f}",
            f"{fd.get('flexion_duration', 0.0):.2f}",
            f"{fd.get('extension_duration', 0.0):.2f}",
            f"{fd.get('flexion_net_speed', 0.0):.2f}",
            f"{fd.get('extension_net_speed', 0.0):.2f}",
            "PASS" if not result.qc_flags.get("errors") else "FLAGGED",
        ]

        with open(self.output_csv, "a", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(row)

        # Log distribution audit rows
        with open(self.distribution_audit_csv, "a", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            for feat_name, live_val in fd.items():
                if feat_name in self.training_distribution:
                    t_med = self.training_distribution[feat_name]["median"]
                    t_iqr = self.training_distribution[feat_name]["iqr"]
                    robust_dev = (live_val - t_med) / t_iqr
                    flagged = abs(robust_dev) > 3.0
                    writer.writerow([
                        self.rep_count,
                        now_str,
                        feat_name,
                        f"{live_val:.4f}",
                        f"{t_med:.4f}",
                        f"{t_iqr:.4f}",
                        f"{robust_dev:.4f}",
                        "TRUE" if flagged else "FALSE",
                    ])

        print(f"\n[LIVE REP {self.rep_count}] Hand: {result.hand} | Prediction: {result.predicted_label}")
        print(f"  Decision Score: {result.decision_score:+.4f} (Rule: >0 => Incorrect, <=0 => Correct)")
        print(f"  Duration: {result.duration_sec:.2f} s | ROM: {fd.get('active_rom', 0.0):.1f}\u00b0 | Frames: {result.frame_count}")
        print(f"  Human Intended: {human_label} | Match: {result.predicted_label == human_label}")

    def run_live(self):
        """Runs the live webcam loop."""
        print("=" * 75)
        print("   Assisted Elbow Flexion V2 — Phase 4 Live Webcam Runner")
        print("   Authoritative Model: BalancedSVM (Frozen Phase 3 Parameters)")
        print(f"   Active Exercising Hand: {self.hand} (Press 'l' for Left, 'r' for Right)")
        print("   Human Intended Label: 'c' for Correct, 'i' for Incorrect")
        print("   Press 'q' in webcam window to quit.")
        print("=" * 75)

        cap = cv2.VideoCapture(self.camera_index, cv2.CAP_DSHOW)
        if not cap.isOpened():
            cap = cv2.VideoCapture(self.camera_index)

        if not cap.isOpened():
            print(f"[FATAL] Could not open camera on index {self.camera_index}")
            return

        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

        mp_pose = mp.solutions.pose
        mp_drawing = mp.solutions.drawing_utils
        pose = mp_pose.Pose(
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )

        frame_idx = 0
        start_wall_time = time.time()

        while True:
            ret, frame = cap.read()
            if not ret:
                print("Failed to read frame from camera.")
                break
            frame_idx += 1
            now_sec = time.perf_counter()

            if self.max_seconds and (time.time() - start_wall_time) >= self.max_seconds:
                print(f"Reached max duration of {self.max_seconds} seconds.")
                break

            # Flip horizontally for natural mirror feel
            frame = cv2.flip(frame, 1)
            h, w = frame.shape[:2]

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = pose.process(rgb)

            completed_bundle = None
            live_state = {"state": "NO_POSE", "active_angle": 0.0, "opposing_angle": 0.0, "live_rom": 0.0}

            if results.pose_world_landmarks:
                # Extract (33, 4) world landmarks
                wl = np.array([
                    [lm.x, lm.y, lm.z, lm.visibility]
                    for lm in results.pose_world_landmarks.landmark
                ], dtype=np.float32)

                completed_bundle, live_state = self.segmenter.process_frame(
                    frame_idx=frame_idx,
                    timestamp_sec=now_sec,
                    world_landmarks=wl,
                )

                if self.record_replay_path is not None:
                    self.replay_frames.append({
                        "frame_idx": frame_idx,
                        "timestamp_sec": now_sec,
                        "world_landmarks": wl,
                    })

            # Process completed repetition if emitted
            if completed_bundle is not None:
                wl_arr, ts_arr, dur, f_cnt = completed_bundle
                inference_res = self.adapter.predict(
                    world_landmarks=wl_arr,
                    timestamps=ts_arr,
                    hand=self.segmenter.hand,
                    duration=dur,
                )
                self.last_inference = inference_res
                self.banner_countdown = 60  # Flash HUD banner for ~2s
                self.log_repetition(inference_res, self.current_intended_label)

                if self.max_reps and self.rep_count >= self.max_reps:
                    print(f"Reached target {self.max_reps} repetitions.")
                    break

            # Render Diagnostic HUD if not headless
            if not self.headless:
                display = frame.copy()
                if results.pose_landmarks:
                    mp_drawing.draw_landmarks(
                        display,
                        results.pose_landmarks,
                        mp_pose.POSE_CONNECTIONS,
                        mp_drawing.DrawingSpec(color=(0, 200, 255), thickness=2, circle_radius=3),
                        mp_drawing.DrawingSpec(color=(0, 255, 128), thickness=2),
                    )

                self._draw_hud(display, live_state, w, h)
                cv2.imshow("Assisted Elbow Flexion V2 - Phase 4 Research Runner", display)

                key = cv2.waitKey(1) & 0xFF
                if key == ord('q'):
                    break
                elif key == ord('l'):
                    self.hand = "Left"
                    self.segmenter.set_hand("Left")
                    print("Switched Active Hand to: Left")
                elif key == ord('r'):
                    self.hand = "Right"
                    self.segmenter.set_hand("Right")
                    print("Switched Active Hand to: Right")
                elif key == ord('c'):
                    self.current_intended_label = "Correct"
                    print("Set Human Intended Label: Correct")
                elif key == ord('i'):
                    self.current_intended_label = "Incorrect"
                    print("Set Human Intended Label: Incorrect")

        cap.release()
        pose.close()
        if not self.headless:
            cv2.destroyAllWindows()

        if self.record_replay_path and self.replay_frames:
            self._save_replay()
        print("\nPhase 4 Live Runner closed cleanly.")

    def _draw_hud(self, display: np.ndarray, live_state: Dict[str, Any], w: int, h: int):
        # Header bar
        cv2.rectangle(display, (0, 0), (w, 80), (20, 24, 30), -1)
        cv2.putText(
            display,
            "Assisted Elbow Flexion V2 (Phase 4 Standalone)",
            (20, 32),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.75,
            (255, 255, 255),
            2,
        )

        st = live_state.get("state", "READY")
        st_color = (0, 255, 0) if st == "FLEXING" else ((0, 165, 255) if st == "EXTENDING" else (200, 200, 200))
        cv2.putText(
            display,
            f"STATE: {st}  |  ACTIVE HAND: {self.hand}  |  REPS: {self.rep_count}  |  INTENT: {self.current_intended_label}",
            (20, 65),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            st_color,
            2,
        )

        # Right side angle card
        act_ang = live_state.get("active_angle", 0.0)
        opp_ang = live_state.get("opposing_angle", 0.0)
        rom = live_state.get("live_rom", 0.0)

        cv2.rectangle(display, (w - 320, 10), (w - 15, 140), (30, 36, 45), -1)
        cv2.rectangle(display, (w - 320, 10), (w - 15, 140), (60, 70, 85), 2)
        cv2.putText(display, f"Active Arm: {act_ang:.1f}\u00b0", (w - 305, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 255, 255), 2)
        cv2.putText(display, f"Opposing Arm: {opp_ang:.1f}\u00b0", (w - 305, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (180, 180, 180), 2)
        cv2.putText(display, f"Live ROM: {rom:.1f}\u00b0", (w - 305, 100), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 255, 0), 2)
        cv2.putText(display, "Keys: [L]eft [R]ight [C]orrect [I]ncorrect [Q]uit", (w - 310, 128), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (160, 160, 160), 1)

        # Flash Banner for Completed Repetition
        if self.banner_countdown > 0 and self.last_inference is not None:
            self.banner_countdown -= 1
            res = self.last_inference
            col = (0, 200, 0) if res.predicted_label == "Correct" else (0, 0, 220)

            cv2.rectangle(display, (w // 2 - 280, 95), (w // 2 + 280, 185), (20, 24, 30), -1)
            cv2.rectangle(display, (w // 2 - 280, 95), (w // 2 + 280, 185), col, 3)

            cv2.putText(
                display,
                f"REP #{self.rep_count}: {res.predicted_label.upper()} (Hand: {res.hand})",
                (w // 2 - 260, 130),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.75,
                col,
                2,
            )
            cv2.putText(
                display,
                f"Score: {res.decision_score:+.4f} | Dur: {res.duration_sec:.2f}s | ROM: {res.feature_dict.get('active_rom', 0.0):.1f}\u00b0",
                (w // 2 - 260, 160),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (220, 220, 220),
                2,
            )

    def _save_replay(self):
        out_p = Path(self.record_replay_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        frame_indices = np.array([f["frame_idx"] for f in self.replay_frames])
        timestamps = np.array([f["timestamp_sec"] for f in self.replay_frames])
        world_lms = np.stack([f["world_landmarks"] for f in self.replay_frames])

        np.savez_compressed(
            out_p,
            frame_indices=frame_indices,
            timestamps=timestamps,
            world_landmarks=world_lms,
            hand=self.hand,
        )
        print(f"[Phase 4 Runner] Saved session replay to: {out_p}")


def replay_offline_session(replay_path: Path) -> List[RepetitionInferenceResult]:
    """Replays recorded webcam frames through the exact same Phase 4 pipeline offline (Step 13)."""
    print(f"[Phase 4 Replay] Loading replay file: {replay_path}")
    data = np.load(replay_path)
    frame_indices = data["frame_indices"]
    timestamps = data["timestamps"]
    world_landmarks = data["world_landmarks"]
    hand = str(data["hand"])

    adapter = BalancedSVMDeploymentAdapter()
    segmenter = RepetitionSegmenter(hand=hand)

    completed_results = []

    for idx, ts, wl in zip(frame_indices, timestamps, world_landmarks):
        completed_bundle, _ = segmenter.process_frame(
            frame_idx=int(idx),
            timestamp_sec=float(ts),
            world_landmarks=wl,
        )
        if completed_bundle is not None:
            wl_arr, ts_arr, dur, f_cnt = completed_bundle
            result = adapter.predict(
                world_landmarks=wl_arr,
                timestamps=ts_arr,
                hand=hand,
                duration=dur,
            )
            completed_results.append(result)
            print(f"[Replay Rep] {result.predicted_label} | Score: {result.decision_score:+.4f} | Dur: {dur:.2f}s | ROM: {result.feature_dict.get('active_rom', 0.0):.1f}\u00b0")

    return completed_results


def main():
    parser = argparse.ArgumentParser(description="Phase 4 Live Webcam Runner for Assisted Elbow Flexion V2")
    parser.add_argument("--hand", choices=["Left", "Right"], default="Right", help="Active arm being exercised")
    parser.add_argument("--cam-index", type=int, default=0, help="Camera index")
    parser.add_argument("--record-replay", type=str, default=None, help="Path to save replay npz")
    parser.add_argument("--replay", type=str, default=None, help="Path to replay npz offline")
    parser.add_argument("--headless", action="store_true", help="Run without graphical window")
    parser.add_argument("--max-seconds", type=float, default=None, help="Maximum session duration in seconds")
    parser.add_argument("--max-reps", type=int, default=None, help="Maximum number of repetitions to capture")
    args = parser.parse_args()

    if args.replay:
        replay_offline_session(Path(args.replay))
        return

    runner = LiveElbowAssessmentRunner(
        hand=args.hand,
        camera_index=args.cam_index,
        record_replay_path=args.record_replay,
        headless=args.headless,
        max_seconds=args.max_seconds,
        max_reps=args.max_reps,
    )
    runner.run_live()


if __name__ == "__main__":
    main()

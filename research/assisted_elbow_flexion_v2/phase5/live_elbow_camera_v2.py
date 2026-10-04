#!/usr/bin/env python3
"""Phase 5 Standalone Live Webcam Runner for Assisted Elbow Flexion V2.

Features the Authoritative Phase 5 Circular-Buffer Repetition Segmenter:
- Circular pre-roll buffer (20 frames) prepended upon flexion onset
- Post-roll settling buffer (20 frames) appended upon extension completion
- Strictly monotonic hardware timing (time.perf_counter)
- Positive duration invariants (end_time > start_time, duration > 0)
- Decoupled Phase 3 BalancedSVM inference (exact 34-feature extraction)
- Explicit user selection of active hand (Left or Right)
- Session recording and offline replay for bit-level determinism
- Real-time diagnostic HUD with signed decision scores

Usage:
  python live_elbow_camera_v2.py [--hand Left|Right] [--cam-index 0] [--record-replay PATH] [--replay PATH]
"""

import argparse
from collections import deque
import csv
from dataclasses import dataclass
from datetime import datetime
import json
from pathlib import Path
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd

PHASE5_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE5_DIR.parents[2]
PHASE4_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase4"
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(PHASE4_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE4_DIR))

from deployment_adapter import (
    BalancedSVMDeploymentAdapter,
    RepetitionInferenceResult,
    SCALAR_FEATURE_NAMES,
    compute_angle_3d_vectorized,
)

# Phase 5 Selected Segmentation Parameters
DEFAULT_FLEXION_THRESHOLD = 135.0
DEFAULT_TURNAROUND_REVERSAL = 12.0
DEFAULT_EXTENSION_FINISH = 135.0
DEFAULT_PRE_ROLL_FRAMES = 20
DEFAULT_POST_ROLL_FRAMES = 20
DEFAULT_MIN_ROM = 16.0
DEFAULT_MIN_FRAMES = 15
DEFAULT_MIN_DURATION_SEC = 0.8


@dataclass
class CapturedFrame:
    frame_index: int
    timestamp_sec: float
    world_landmarks: np.ndarray  # (33, 4)
    active_angle: float
    opposing_angle: float


class Phase5RepetitionSegmenter:
    """Authoritative Phase 5 Circular-Buffer Repetition Segmenter.
    
    Guarantees:
    - Prepend pre-roll buffer (20 frames) upon entering FLEXING
    - Append post-roll buffer (20 frames) upon entering POST_ROLL
    - Strictly positive duration (duration > 0, end_time > start_time)
    - Rejects sub-threshold optical noise
    """

    def __init__(
        self,
        hand: str = "Right",
        flexion_threshold: float = DEFAULT_FLEXION_THRESHOLD,
        turnaround_reversal: float = DEFAULT_TURNAROUND_REVERSAL,
        extension_finish: float = DEFAULT_EXTENSION_FINISH,
        pre_roll: int = DEFAULT_PRE_ROLL_FRAMES,
        post_roll: int = DEFAULT_POST_ROLL_FRAMES,
        min_rom: float = DEFAULT_MIN_ROM,
        min_frames: int = DEFAULT_MIN_FRAMES,
        min_duration_sec: float = DEFAULT_MIN_DURATION_SEC,
    ):
        self.hand = hand
        self.flexion_threshold = flexion_threshold
        self.turnaround_reversal = turnaround_reversal
        self.extension_finish = extension_finish
        self.pre_roll = pre_roll
        self.post_roll = post_roll
        self.min_rom = min_rom
        self.min_frames = min_frames
        self.min_duration_sec = min_duration_sec

        self.pre_buffer = deque(maxlen=pre_roll)
        self.reset()

    def set_hand(self, hand: str):
        if hand not in ("Left", "Right"):
            raise ValueError(f"Hand must be 'Left' or 'Right', got {hand}")
        self.hand = hand

    def reset(self):
        self.state = "READY"  # READY -> FLEXING -> EXTENDING -> POST_ROLL -> COMPLETED
        self.buffer: List[CapturedFrame] = []
        self.start_frame_idx: Optional[int] = None
        self.start_time: Optional[float] = None
        self.min_angle = 180.0
        self.current_rom = 0.0
        self.post_count = 0

    def process_frame(
        self,
        frame_idx: int,
        timestamp_sec: float,
        world_landmarks: np.ndarray,
    ) -> Tuple[Optional[Tuple[np.ndarray, np.ndarray, float, int, int, int]], Dict[str, Any]]:
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
            self.pre_buffer.append(current_frame)
            self.current_rom = 0.0
            if active_ang < self.flexion_threshold:
                self.state = "FLEXING"
                # Prepend continuous circular pre-roll buffer
                self.buffer = list(self.pre_buffer)
                self.start_frame_idx = self.buffer[0].frame_index
                self.start_time = self.buffer[0].timestamp_sec
                self.min_angle = active_ang

        elif self.state == "FLEXING":
            self.buffer.append(current_frame)
            self.min_angle = min(self.min_angle, active_ang)
            angles = [f.active_angle for f in self.buffer]
            self.current_rom = max(angles) - min(angles)

            if active_ang > (self.min_angle + self.turnaround_reversal):
                self.state = "EXTENDING"

        elif self.state == "EXTENDING":
            self.buffer.append(current_frame)
            angles = [f.active_angle for f in self.buffer]
            self.current_rom = max(angles) - min(angles)

            if active_ang >= self.extension_finish:
                self.state = "POST_ROLL"
                self.post_count = 0

        elif self.state == "POST_ROLL":
            self.buffer.append(current_frame)
            self.post_count += 1
            angles = [f.active_angle for f in self.buffer]
            self.current_rom = max(angles) - min(angles)

            if self.post_count >= self.post_roll:
                # Cycle complete - validate timing invariants
                end_frame_idx = self.buffer[-1].frame_index
                end_time = self.buffer[-1].timestamp_sec

                assert self.start_frame_idx is not None
                assert self.start_time is not None
                assert end_frame_idx > self.start_frame_idx, (
                    f"Timing violation: end_frame ({end_frame_idx}) <= start_frame ({self.start_frame_idx})"
                )
                assert end_time > self.start_time, (
                    f"Timing violation: end_time ({end_time:.4f}) <= start_time ({self.start_time:.4f})"
                )

                duration_sec = end_time - self.start_time
                assert duration_sec > 0.0, f"Duration violation: {duration_sec} <= 0"

                frame_count = len(self.buffer)
                rom = float(max(angles) - min(angles))

                if (
                    rom >= self.min_rom
                    and frame_count >= self.min_frames
                    and duration_sec >= self.min_duration_sec
                ):
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed_bundle = (
                        wl_arr,
                        ts_arr,
                        duration_sec,
                        frame_count,
                        self.start_frame_idx,
                        end_frame_idx,
                    )

                self.reset()

        live_state = {
            "state": self.state,
            "hand": self.hand,
            "active_angle": active_ang,
            "opposing_angle": opposing_ang,
            "live_rom": self.current_rom,
            "buffer_len": len(self.buffer),
            "start_time": self.start_time,
            "post_roll_count": self.post_count,
        }

        return completed_bundle, live_state


class Phase5LiveRunner:
    """Live webcam assessment engine using the Phase 5 Segmenter and Phase 3 BalancedSVM."""

    def __init__(
        self,
        hand: str = "Right",
        camera_index: int = 0,
        output_csv: Optional[Path] = None,
        record_replay_path: Optional[Path] = None,
        headless: bool = False,
        max_seconds: Optional[float] = None,
        max_reps: Optional[int] = None,
    ):
        self.hand = hand
        self.camera_index = camera_index
        self.output_csv = output_csv or (PHASE5_DIR / "live_shadow_results.csv")
        self.record_replay_path = record_replay_path
        self.headless = headless
        self.max_seconds = max_seconds
        self.max_reps = max_reps

        self.adapter = BalancedSVMDeploymentAdapter()
        self.segmenter = Phase5RepetitionSegmenter(hand=self.hand)

        self.rep_count = 0
        self.last_inference: Optional[RepetitionInferenceResult] = None
        self.banner_countdown = 0
        self.current_intended_label = "Correct"
        self.replay_frames: List[Dict[str, Any]] = []

        self._init_csv()

    def _init_csv(self):
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
                "start_angle",
                "end_angle",
                "min_angle",
                "active_rom",
                "opposing_rom",
                "segmentation_status",
                "prediction_matches_intent",
            ]
            with open(self.output_csv, "w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                writer.writerow(header)

    def log_repetition(self, result: RepetitionInferenceResult, human_label: str):
        self.rep_count += 1
        result.repetition_id = f"live_p5_rep_{self.rep_count:03d}"
        now_str = datetime.now().isoformat()
        fd = result.feature_dict

        matches = (result.predicted_label == human_label)
        row = [
            self.rep_count,
            now_str,
            result.hand,
            human_label,
            result.predicted_label,
            f"{result.decision_score:.4f}",
            f"{result.duration_sec:.2f}",
            result.frame_count,
            f"{fd.get('active_start_angle', 0.0):.1f}",
            f"{fd.get('active_end_angle', 0.0):.1f}",
            f"{fd.get('active_min_angle', 0.0):.1f}",
            f"{fd.get('active_rom', 0.0):.1f}",
            f"{fd.get('opposing_rom', 0.0):.1f}",
            "CIRCULAR_BUFFER_SEGMENTED",
            matches,
        ]

        with open(self.output_csv, "a", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(row)

        print(f"\n[PHASE 5 LIVE REP #{self.rep_count}] Hand: {result.hand} | Prediction: {result.predicted_label}")
        print(f"  Decision Score: {result.decision_score:+.4f} | Intended: {human_label} | Match: {matches}")
        print(f"  Duration: {result.duration_sec:.2f}s | ROM: {fd.get('active_rom', 0.0):.1f}\u00b0 | Start Ang: {fd.get('active_start_angle', 0.0):.1f}\u00b0 | End Ang: {fd.get('active_end_angle', 0.0):.1f}\u00b0")

    def run_live(self):
        print("=" * 75)
        print("   Assisted Elbow Flexion V2 — Phase 5 Live Camera Runner")
        print("   Segmenter: Pre/Post-Roll Circular Buffers (20 frames each)")
        print(f"   Active Arm: {self.hand} (Press 'l' for Left, 'r' for Right)")
        print("   Intended Label: 'c' for Correct, 'i' for Incorrect | 'q' to Quit")
        print("=" * 75)

        cap = cv2.VideoCapture(self.camera_index, cv2.CAP_DSHOW)
        if not cap.isOpened():
            cap = cv2.VideoCapture(self.camera_index)

        if not cap.isOpened():
            print(f"[FATAL] Cannot open camera on index {self.camera_index}")
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
                break
            frame_idx += 1
            now_sec = time.perf_counter()

            if self.max_seconds and (time.time() - start_wall_time) >= self.max_seconds:
                print(f"Reached max duration of {self.max_seconds} seconds.")
                break

            frame = cv2.flip(frame, 1)
            h, w = frame.shape[:2]

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = pose.process(rgb)

            completed_bundle = None
            live_state = {"state": "NO_POSE", "active_angle": 0.0, "opposing_angle": 0.0, "live_rom": 0.0}

            if results.pose_world_landmarks:
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

            if completed_bundle is not None:
                wl_arr, ts_arr, dur, f_cnt, s_f, e_f = completed_bundle
                inference_res = self.adapter.predict(
                    world_landmarks=wl_arr,
                    timestamps=ts_arr,
                    hand=self.segmenter.hand,
                    duration=dur,
                )
                self.last_inference = inference_res
                self.banner_countdown = 60
                self.log_repetition(inference_res, self.current_intended_label)

                if self.max_reps and self.rep_count >= self.max_reps:
                    print(f"Reached max repetitions: {self.max_reps}")
                    break

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
                cv2.imshow("Assisted Elbow Flexion V2 - Phase 5 Segmenter", display)

                key = cv2.waitKey(1) & 0xFF
                if key == ord('q'):
                    break
                elif key == ord('l'):
                    self.hand = "Left"
                    self.segmenter.set_hand("Left")
                    print("Active Hand -> Left")
                elif key == ord('r'):
                    self.hand = "Right"
                    self.segmenter.set_hand("Right")
                    print("Active Hand -> Right")
                elif key == ord('c'):
                    self.current_intended_label = "Correct"
                    print("Intent -> Correct")
                elif key == ord('i'):
                    self.current_intended_label = "Incorrect"
                    print("Intent -> Incorrect")

        cap.release()
        pose.close()
        if not self.headless:
            cv2.destroyAllWindows()

        if self.record_replay_path and self.replay_frames:
            self._save_replay()
        print("\nPhase 5 Live Runner closed cleanly.")

    def _draw_hud(self, display: np.ndarray, live_state: Dict[str, Any], w: int, h: int):
        cv2.rectangle(display, (0, 0), (w, 80), (20, 24, 30), -1)
        cv2.putText(
            display,
            "Assisted Elbow Flexion V2 — Phase 5 Segmenter",
            (20, 32),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.75,
            (255, 255, 255),
            2,
        )

        st = live_state.get("state", "READY")
        st_col = (0, 255, 0) if st == "FLEXING" else ((0, 165, 255) if st in ("EXTENDING", "POST_ROLL") else (200, 200, 200))
        cv2.putText(
            display,
            f"STATE: {st}  |  ARM: {self.hand}  |  REPS: {self.rep_count}  |  INTENT: {self.current_intended_label}",
            (20, 65),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            st_col,
            2,
        )

        act_ang = live_state.get("active_angle", 0.0)
        opp_ang = live_state.get("opposing_angle", 0.0)
        rom = live_state.get("live_rom", 0.0)

        cv2.rectangle(display, (w - 320, 10), (w - 15, 140), (30, 36, 45), -1)
        cv2.rectangle(display, (w - 320, 10), (w - 15, 140), (60, 70, 85), 2)
        cv2.putText(display, f"Active Arm: {act_ang:.1f}\u00b0", (w - 305, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 255, 255), 2)
        cv2.putText(display, f"Opposing Arm: {opp_ang:.1f}\u00b0", (w - 305, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (180, 180, 180), 2)
        cv2.putText(display, f"Live ROM: {rom:.1f}\u00b0", (w - 305, 100), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 255, 0), 2)
        cv2.putText(display, "Keys: [L]eft [R]ight [C]orrect [I]ncorrect [Q]uit", (w - 310, 128), cv2.FONT_HERSHEY_SIMPLEX, 0.38, (160, 160, 160), 1)

        if self.banner_countdown > 0 and self.last_inference is not None:
            self.banner_countdown -= 1
            res = self.last_inference
            col = (0, 200, 0) if res.predicted_label == "Correct" else (0, 0, 220)
            cv2.rectangle(display, (w // 2 - 280, 95), (w // 2 + 280, 185), (20, 24, 30), -1)
            cv2.rectangle(display, (w // 2 - 280, 95), (w // 2 + 280, 185), col, 3)
            cv2.putText(
                display,
                f"REP #{self.rep_count}: {res.predicted_label.upper()} ({res.hand})",
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
        print(f"[Phase 5 Runner] Saved continuous session replay to: {out_p}")


def replay_offline_session(replay_path: Path) -> List[RepetitionInferenceResult]:
    """Replays recorded webcam frames through the exact Phase 5 segmenter offline."""
    print(f"[Phase 5 Replay] Replaying offline session: {replay_path}")
    data = np.load(replay_path)
    frame_indices = data["frame_indices"]
    timestamps = data["timestamps"]
    world_landmarks = data["world_landmarks"]
    hand = str(data["hand"])

    adapter = BalancedSVMDeploymentAdapter()
    segmenter = Phase5RepetitionSegmenter(hand=hand)

    completed_results = []
    for idx, ts, wl in zip(frame_indices, timestamps, world_landmarks):
        completed_bundle, _ = segmenter.process_frame(
            frame_idx=int(idx),
            timestamp_sec=float(ts),
            world_landmarks=wl,
        )
        if completed_bundle is not None:
            wl_arr, ts_arr, dur, f_cnt, s_f, e_f = completed_bundle
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
    parser = argparse.ArgumentParser(description="Phase 5 Live Camera Runner for Assisted Elbow Flexion V2")
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

    runner = Phase5LiveRunner(
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

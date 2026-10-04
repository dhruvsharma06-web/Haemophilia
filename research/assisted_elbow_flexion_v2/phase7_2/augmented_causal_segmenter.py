#!/usr/bin/env python3
"""Phase 7.2: Augmented Causal Cycle Segmenter for Assisted Elbow Flexion V2.

Research-only candidate building on Phase 7 CausalCycleSegmenter with configurable
pre-roll lookback (to preserve natural resting posture before flexion onset) and
post-roll settling (to capture full extension recovery and late compensatory motion).

Operates 100% causally forward in time without future lookahead.
"""

from collections import deque
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

PHASE7_2_DIR = Path(__file__).resolve().parent
REPO_ROOT = PHASE7_2_DIR.parents[2]
PHASE4_DIR = REPO_ROOT / "research" / "assisted_elbow_flexion_v2" / "phase4"

if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(PHASE4_DIR) not in sys.path:
    sys.path.insert(0, str(PHASE4_DIR))

from deployment_adapter import compute_angle_3d_vectorized


@dataclass
class CycleFrameItem:
    frame_idx: int
    timestamp_sec: float
    world_landmarks: np.ndarray  # (33, 4)
    active_angle: float
    opposing_angle: float
    velocity_deg_s: float


class AugmentedCausalSegmenter:
    """Augmented Causal Cycle-Based Repetition Segmenter.
    
    Causal state machine:
      REST -> FLEXING -> EXTENDING -> POST_ROLL -> COMPLETED
    
    Parameters:
      hand: Monitored arm ("Left" or "Right")
      min_rom: Minimum range of motion in degrees (default: 15.0)
      onset_delta: Threshold departure from baseline in degrees (default: 8.0)
      reversal_delta: Threshold reversal for turnaround in degrees (default: 8.0)
      pre_roll: Frames of pre-onset posture preserved (e.g. 10, 15)
      post_roll: Frames of post-extension settling preserved (e.g. 10, 15, 20)
      min_frames: Minimum frame count for a valid repetition (default: 15)
      min_duration_sec: Minimum repetition duration in seconds (default: 0.8)
    """

    def __init__(
        self,
        hand: str = "Right",
        min_rom: float = 15.0,
        onset_delta: float = 8.0,
        reversal_delta: float = 8.0,
        pre_roll: int = 15,
        post_roll: int = 15,
        min_frames: int = 15,
        min_duration_sec: float = 0.8,
    ):
        self.hand = hand
        self.min_rom = min_rom
        self.onset_delta = onset_delta
        self.reversal_delta = reversal_delta
        self.pre_roll = pre_roll
        self.post_roll = post_roll
        self.min_frames = min_frames
        self.min_duration_sec = min_duration_sec

        # Extension baseline tracking
        self.baseline = 148.0
        self.locked_baseline = 148.0
        self.baseline_history = deque(maxlen=30)
        self.vel_window = deque(maxlen=3)

        self.reset()

    def set_hand(self, hand: str):
        """Switches active monitored hand with strict state isolation."""
        if hand not in ("Left", "Right"):
            raise ValueError(f"Hand must be 'Left' or 'Right', got: {hand}")
        if hand != self.hand:
            self.hand = hand
            self.reset()
            self.baseline = 148.0
            self.locked_baseline = 148.0
            self.baseline_history.clear()
            self.vel_window.clear()

    def reset(self):
        """Resets the segmenter state machine and buffers cleanly."""
        self.state = "REST"
        self.buffer: List[CycleFrameItem] = []
        self.pre_buffer = deque(maxlen=self.pre_roll)
        self.min_angle = 180.0
        self.post_count = 0
        self.prev_ang: Optional[float] = None
        self.prev_time: Optional[float] = None

    def process_frame(
        self,
        frame_idx: int,
        timestamp_sec: float,
        world_landmarks: np.ndarray,
    ) -> Tuple[Optional[Tuple[np.ndarray, np.ndarray, float, int, int, int]], Dict[str, Any]]:
        """Processes a single frame causally.
        
        Returns:
            (completed_bundle, telemetry_dict)
            completed_bundle: (world_landmarks, timestamps, duration, frame_count, start_frame, end_frame) or None
        """
        active_idx = (11, 13, 15) if self.hand == "Left" else (12, 14, 16)
        opposing_idx = (12, 14, 16) if self.hand == "Left" else (11, 13, 15)

        xyz = world_landmarks[:, :3]
        active_ang = float(compute_angle_3d_vectorized(
            xyz[None, active_idx[0]], xyz[None, active_idx[1]], xyz[None, active_idx[2]]
        )[0])
        opposing_ang = float(compute_angle_3d_vectorized(
            xyz[None, opposing_idx[0]], xyz[None, opposing_idx[1]], xyz[None, opposing_idx[2]]
        )[0])

        # Causal angular velocity (deg/s)
        if self.prev_time is not None and timestamp_sec > self.prev_time:
            dt = timestamp_sec - self.prev_time
            inst_vel = (active_ang - self.prev_ang) / max(dt, 1e-4)
        else:
            inst_vel = 0.0
        self.prev_ang = active_ang
        self.prev_time = timestamp_sec

        self.vel_window.append(inst_vel)
        smooth_vel = float(np.median(self.vel_window))

        item = CycleFrameItem(
            frame_idx=frame_idx,
            timestamp_sec=timestamp_sec,
            world_landmarks=world_landmarks,
            active_angle=active_ang,
            opposing_angle=opposing_ang,
            velocity_deg_s=smooth_vel,
        )

        completed_bundle = None

        # -------------------------------------------------------------
        # STATE: REST (Quiescent Extension Baseline & Flexion Onset)
        # -------------------------------------------------------------
        if self.state == "REST":
            self.pre_buffer.append(item)

            # Update adaptive baseline only during quiescent extended rest
            if active_ang >= 135.0 and abs(smooth_vel) < 12.0:
                self.baseline_history.append(active_ang)
                if len(self.baseline_history) >= 5:
                    self.baseline = float(np.clip(np.median(self.baseline_history), 136.0, 168.0))

            # Flexion onset condition: departure from baseline + sustained flexion velocity
            onset_threshold = min(self.baseline - self.onset_delta, 138.0)
            if active_ang < onset_threshold and smooth_vel < -6.0:
                self.state = "FLEXING"
                self.locked_baseline = self.baseline
                # Preserve pre-roll lookback window
                self.buffer = list(self.pre_buffer)
                self.min_angle = active_ang

        # -------------------------------------------------------------
        # STATE: FLEXING (Tracking Peak Flexion / Turnaround)
        # -------------------------------------------------------------
        elif self.state == "FLEXING":
            self.buffer.append(item)
            self.min_angle = min(self.min_angle, active_ang)

            angles = [f.active_angle for f in self.buffer]
            current_rom = max(angles) - self.min_angle

            # Turnaround detection: reversal from minimum + positive extension velocity
            rev_requirement = max(self.reversal_delta, 0.15 * current_rom)
            if active_ang >= (self.min_angle + rev_requirement) and smooth_vel > 4.0:
                self.state = "EXTENDING"

        # -------------------------------------------------------------
        # STATE: EXTENDING (Recovery toward Natural Extension)
        # -------------------------------------------------------------
        elif self.state == "EXTENDING":
            self.buffer.append(item)
            angles = [f.active_angle for f in self.buffer]
            current_rom = max(angles) - self.min_angle

            # Extension finish condition:
            # 1. Near locked baseline: theta >= locked_baseline - 5.0 (capped at 138 deg)
            # 2. Contracture settling: recovered >= 80% of ROM and velocity settled near zero
            near_baseline = active_ang >= min(self.locked_baseline - 5.0, 138.0)
            contracture_settled = (
                current_rom >= self.min_rom
                and active_ang >= (self.min_angle + 0.80 * current_rom)
                and abs(smooth_vel) < 10.0
                and active_ang >= 126.0
            )

            if near_baseline or contracture_settled:
                self.state = "POST_ROLL"
                self.post_count = 0

        # -------------------------------------------------------------
        # STATE: POST_ROLL (Bounded Extension Settling)
        # -------------------------------------------------------------
        elif self.state == "POST_ROLL":
            self.buffer.append(item)
            self.post_count += 1

            if self.post_count >= self.post_roll:
                start_frame = self.buffer[0].frame_idx
                end_frame = self.buffer[-1].frame_idx
                start_time = self.buffer[0].timestamp_sec
                end_time = self.buffer[-1].timestamp_sec
                duration_sec = end_time - start_time

                # Invariant assertions
                assert end_frame > start_frame, f"Frame order invariant violated: {end_frame} <= {start_frame}"
                assert end_time > start_time, f"Monotonic time invariant violated: {end_time} <= {start_time}"
                assert duration_sec > 0.0, f"Duration invariant violated: {duration_sec} <= 0"

                angles = [f.active_angle for f in self.buffer]
                rom = float(max(angles) - min(angles))
                fc = len(self.buffer)

                if rom >= self.min_rom and fc >= self.min_frames and duration_sec >= self.min_duration_sec:
                    wl_arr = np.stack([f.world_landmarks for f in self.buffer])
                    ts_arr = np.array([f.timestamp_sec for f in self.buffer], dtype=np.float64)
                    completed_bundle = (
                        wl_arr,
                        ts_arr,
                        duration_sec,
                        fc,
                        start_frame,
                        end_frame,
                    )

                self.reset()

        telemetry = {
            "state": self.state,
            "active_angle": active_ang,
            "opposing_angle": opposing_ang,
            "velocity": smooth_vel,
            "baseline": self.baseline,
            "min_angle": self.min_angle,
            "hand": self.hand,
        }

        return completed_bundle, telemetry

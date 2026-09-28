"""Authoritative WebSocket and batch adapter for the haemophilia-final Elbow Flexion & Extension AI model."""

from collections import deque
from pathlib import Path
from typing import Dict, List, Optional

import cv2
import numpy as np
import torch

from src.features.elbow_features import build_features, resample
from src.models.elbow_lstm import ElbowLSTM


def _extract_row(landmarks) -> Dict[str, float]:
    row: Dict[str, float] = {}
    for i in range(33):
        lm = landmarks.landmark[i]
        row[f"landmark_{i}_x"] = float(lm.x)
        row[f"landmark_{i}_y"] = float(lm.y)
        row[f"landmark_{i}_z"] = float(lm.z)
        row[f"landmark_{i}_visibility"] = float(getattr(lm, "visibility", 1.0))
    return row


def _get_joint_angle(a, b, c) -> float:
    a, b, c = np.array(a), np.array(b), np.array(c)
    ba = a - b
    bc = c - b
    norm_ba = np.linalg.norm(ba)
    norm_bc = np.linalg.norm(bc)
    if norm_ba * norm_bc <= 1e-6:
        return 0.0
    cosine = np.clip(np.dot(ba, bc) / (norm_ba * norm_bc), -1.0, 1.0)
    return float(np.degrees(np.arccos(cosine)))


def _classify_rep(pred: float, angles: List[float], wrist_path: List[List[float]]):
    angles_arr = np.array(angles, dtype=np.float32)
    range_motion = float(np.max(angles_arr) - np.min(angles_arr))
    peak = float(np.max(angles_arr))
    valley = float(np.min(angles_arr))

    velocity = np.diff(angles_arr)
    smoothness = float(np.std(velocity)) if len(velocity) > 0 else 0.0

    wrist_arr = np.array(wrist_path, dtype=np.float32)
    if len(wrist_arr) > 1:
        wrist_movement = float(np.linalg.norm(wrist_arr[1:] - wrist_arr[:-1], axis=1).mean())
    else:
        wrist_movement = 0.0

    # Hard penalty conditions
    penalty = 0.0
    if range_motion < 25.0:
        penalty += 0.25
    if peak < 125.0:
        penalty += 0.20
    if smoothness > 20.0:
        penalty += 0.15
    if wrist_movement > 0.04:
        penalty += 0.15

    # Balanced score
    range_score = min(1.0, range_motion / 70.0)
    smooth_score = max(0.0, 1.0 - smoothness / 25.0)

    base_score = (
        0.6 * pred +
        0.2 * range_score +
        0.2 * smooth_score
    )

    final_score = base_score - penalty

    return final_score, range_motion, smoothness, peak, valley, wrist_movement


class ElbowFlexionAssessment:
    """Real-time and batch assessment engine for Elbow Flexion & Extension."""

    def __init__(
        self,
        model=None,
        device=None,
        fps: float = 20.0,
        data_dir: str = "data",
        save_artifacts: bool = True,
    ):
        self.fps = fps
        self.save_artifacts = save_artifacts

        if device is not None:
            self.device = device
        else:
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        if model is not None:
            self.model = model
        else:
            model_path = Path(__file__).resolve().parents[2] / "models" / "elbow_lstm.pth"
            if not model_path.exists():
                raise FileNotFoundError(f"haemophilia-final elbow model not found: {model_path}")

            self.model = ElbowLSTM(input_size=8, hidden_size=128, num_layers=2)
            self.model.load_state_dict(
                torch.load(model_path, map_location=self.device, weights_only=True)
            )
            self.model.to(self.device)
            self.model.eval()

        # Tracking state
        self.ema_angle: Optional[float] = None
        self.alpha = 0.25
        self.angle_buffer = deque(maxlen=5)
        self.prev_angle: Optional[float] = None

        self.state = "READY"
        self.rep_active = False
        self.rep_angles: List[float] = []
        self.rep_rows: List[Dict[str, float]] = []
        self.wrist_path: List[List[float]] = []

        self.rep_count = 0
        self.cooldown = 0
        self.min_flexion_reached = 180.0

        self.last_angle = 0.0
        self.last_rom = 0.0
        self.last_score = 0.0
        self.last_form = "Waiting"
        self.last_confidence = 0.0
        self.last_completed_rep: Optional[Dict] = None

    def process_frame(
        self,
        frame,
        pose_landmarks,
        frame_number: int = 0,
    ) -> Optional[Dict]:
        """Process a single frame and return completed rep dictionary if completed."""
        if pose_landmarks is None:
            return None

        # Select arm with higher visibility: right (12, 14, 16) vs left (11, 13, 15)
        lms = pose_landmarks.landmark
        r_vis = float(getattr(lms[14], "visibility", 0.5))
        l_vis = float(getattr(lms[13], "visibility", 0.5))

        if r_vis >= l_vis:
            s_idx, e_idx, w_idx = 12, 14, 16
        else:
            s_idx, e_idx, w_idx = 11, 13, 15

        shoulder = [lms[s_idx].x, lms[s_idx].y, lms[s_idx].z]
        elbow = [lms[e_idx].x, lms[e_idx].y, lms[e_idx].z]
        wrist = [lms[w_idx].x, lms[w_idx].y, lms[w_idx].z]

        raw_angle = _get_joint_angle(shoulder, elbow, wrist)

        # EMA smoothing + buffer
        if self.ema_angle is None:
            self.ema_angle = raw_angle
        else:
            self.ema_angle = self.alpha * raw_angle + (1.0 - self.alpha) * self.ema_angle

        self.angle_buffer.append(self.ema_angle)
        angle = float(np.mean(self.angle_buffer))
        self.last_angle = angle

        # State delta
        if self.prev_angle is None:
            delta = 0.0
        else:
            delta = angle - self.prev_angle
        self.prev_angle = angle

        # State classification via hysteresis
        if delta < -0.8:
            new_state = "FLEXING"
        elif delta > 0.8:
            new_state = "EXTENDING"
        elif abs(delta) < 0.3:
            new_state = "TOP" if (self.rep_active and angle < 110.0) else "READY"
        else:
            new_state = self.state

        self.state = new_state

        if self.cooldown > 0:
            self.cooldown -= 1

        # Rep begin condition
        if new_state == "FLEXING" and not self.rep_active and self.cooldown == 0:
            self.rep_active = True
            self.rep_angles = [angle]
            self.rep_rows = [_extract_row(pose_landmarks)]
            self.wrist_path = [wrist]
            self.min_flexion_reached = angle

        # Accumulate ongoing rep frames
        if self.rep_active:
            self.rep_angles.append(angle)
            self.rep_rows.append(_extract_row(pose_landmarks))
            self.wrist_path.append(wrist)
            if angle < self.min_flexion_reached:
                self.min_flexion_reached = angle

            # Rep completion condition:
            # 1. Arm was actively flexing and reached sufficient flexion (< 120°)
            # 2. Arm has returned towards extension (> 125° or > peak - 10°)
            # 3. Sufficient frames (>= 15) and cooldown is 0
            has_sufficient_flexion = (self.min_flexion_reached < 120.0)
            has_extended_back = (angle >= 125.0 or (len(self.rep_angles) > 20 and new_state != "FLEXING" and angle > self.min_flexion_reached + 25.0))
            rom_so_far = max(self.rep_angles) - min(self.rep_angles)

            if len(self.rep_angles) >= 15 and has_sufficient_flexion and has_extended_back and rom_so_far >= 20.0:
                self.rep_active = False
                self.rep_count += 1
                self.cooldown = 10

                return self._finalize_rep(self.rep_angles, self.rep_rows, self.wrist_path)

        return None

    def _finalize_rep(
        self,
        angles: List[float],
        rows: List[Dict[str, float]],
        wrist_path: List[List[float]],
    ) -> Dict:
        """Run LSTM inference and return completed rep contract."""
        feat, _ = build_features(rows, fps=self.fps, angle_series=angles)
        if len(feat) != 128:
            feat = resample(feat, 128)

        x = torch.tensor(feat, dtype=torch.float32).unsqueeze(0).to(self.device)

        with torch.no_grad():
            logit = self.model(x)
            pred = float(torch.sigmoid(logit).item())

        final_score, range_motion, smoothness, peak, valley, wrist_movement = _classify_rep(
            pred, angles, wrist_path
        )

        score_100 = float(round(max(0.0, min(100.0, final_score * 100.0)), 1))
        is_correct = final_score > 0.58
        form = "Correct" if is_correct else "Incorrect"

        duration = float(round(len(angles) / max(self.fps, 1.0), 2))
        speed_val = (range_motion / duration) if duration > 0 else 0.0
        speed_str = "Fast" if speed_val > 65.0 else ("Slow" if speed_val < 20.0 else "Good")

        if range_motion < 25.0:
            error_type = "INSUFFICIENT_ROM"
            feedback = "Increase range of motion"
        elif peak < 125.0:
            error_type = "INSUFFICIENT_EXTENSION"
            feedback = "Extend elbow fully at bottom"
        elif smoothness > 18.0:
            error_type = "JERKY_MOVEMENT"
            feedback = "Move arm more smoothly"
        elif wrist_movement > 0.03:
            error_type = "ARM_INSTABILITY"
            feedback = "Keep upper arm stable"
        else:
            error_type = ""
            feedback = "Good form! Excellent control."

        confidence_pct = float(round(pred * 100.0, 1))

        self.last_rom = range_motion
        self.last_score = score_100
        self.last_form = form
        self.last_confidence = confidence_pct

        completed = {
            "rep_number": self.rep_count,
            "form": form,
            "score": score_100,
            "range_of_motion": float(round(range_motion, 1)),
            "rom": float(round(range_motion, 1)),
            "speed": speed_str,
            "smoothness": float(round(smoothness, 2)),
            "smoothness_raw": float(round(smoothness, 2)),
            "duration": duration,
            "confidence": confidence_pct,
            "lstm_confidence": confidence_pct,
            "error_type": error_type,
            "feedback": feedback,
            "status": "COMPLETED",
            "rep_status": "COMPLETED",
            "angle": float(round(self.last_angle, 1)),
        }

        self.last_completed_rep = completed
        print(
            f"[ELBOW AI] REP #{self.rep_count}: "
            f"ROM={range_motion:.1f}°, "
            f"FORM={form}, "
            f"SCORE={score_100:.1f} (pred={pred:.3f})"
        )

        return completed

    def get_live_state(self, pose_landmarks=None) -> Dict:
        """Produce the real-time frame dictionary matching the Flutter client schema."""
        landmarks = []
        if pose_landmarks is not None:
            for lm in pose_landmarks.landmark:
                landmarks.append({
                    "x": float(lm.x),
                    "y": float(lm.y),
                    "z": float(lm.z),
                    "visibility": float(getattr(lm, "visibility", 1.0)),
                })

        return {
            "exercise": "Elbow Flexion & Extension",
            "state": self.state,
            "rep_count": self.rep_count,
            "form": self.last_form,
            "confidence": self.last_confidence,
            "angle": float(round(self.last_angle, 1)),
            "score": self.last_score,
            "range_of_motion": float(round(self.last_rom, 1)),
            "speed": "Good" if self.rep_count > 0 else "Waiting",
            "smoothness": 0.0,
            "error_type": "",
            "feedback": "",
            "landmarks": landmarks,
            "calibrated": True,
        }
"""Assisted Elbow Flexion live assessment engine and state machine.

Dual-Assessment Architecture:
1. Biomechanical / Rule-Based Assessment (Production Baseline):
   - Evaluates transparent, deterministic biomechanical criteria derived empirically from
     training-set LOSO folds (Persons 1 & 2):
     * Minimum elbow flexion angle <= 101.0° (training fold boundary: 100.2° - 101.6°)
     * Maximum active elbow flare <= 0.30 (training fold boundary: 0.27 - 0.34)
     * Minimum range of motion >= 25.0°
   - Produces interpretable, explainable feedback ("insufficient elbow flexion", "excessive elbow flare", "acceptable movement").
   - NOTE: These thresholds represent empirical engineering boundaries derived from training folds;
     they are not clinically validated medical diagnosis.

2. Learned ML Prediction (Research / Experimental):
   - Resamples repetition kinematics into a canonical 128-frame 8-feature representation.
   - Evaluates the AssistedElbowLSTM (2-layer, 64 hidden units).
   - Reports model predicted class and softmax confidence for research logging.
   - NOTE: Cross-subject LOSO evaluation demonstrates that on the current 3-subject dataset,
     the LSTM suffers from subject-specific overfitting (51.1% balanced accuracy).

Both assessments are kept explicitly separate in every repetition record.
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
import torch

from src.features.assisted_elbow_features import (
    FEATURE_NAMES,
    NORM_CONSTANTS,
    build_normalized_sequence,
    extract_frame_kinematics,
    map_canonical_features,
)
from src.models.lstm_model import ExerciseLSTM

HUMAN_VERIFIED_MODEL_PATH = (
    Path(__file__).resolve().parents[2]
    / "models"
    / "assisted_elbow_lstm_human_verified.pth"
)
EXPERIMENTAL_MODEL_PATH = (
    Path(__file__).resolve().parents[2]
    / "models"
    / "assisted_elbow_lstm.pth"
)
MODEL_PATH = HUMAN_VERIFIED_MODEL_PATH if HUMAN_VERIFIED_MODEL_PATH.exists() else EXPERIMENTAL_MODEL_PATH

SEQUENCE_LENGTH = 128

# Configurable kinematic segmentation parameters
DEFAULT_START_EXTEND_ANGLE = 120.0
DEFAULT_FLEXION_THRESHOLD = 110.0
DEFAULT_MIN_ROM = 20.0
DEFAULT_MIN_REP_FRAMES = 15

# Configurable biomechanical evaluation thresholds
# Empirically calibrated from Persons 1 & 2 training folds:
DEFAULT_MAX_FLEXION_ANGLE = 101.0  # Flexion depth must reach <= 101.0°
DEFAULT_MAX_ELBOW_FLARE = 0.30     # Active elbow flare relative to W_ref must be <= 0.30
DEFAULT_MIN_ROM_EVAL = 25.0        # Range of motion must be >= 25.0°
DEFAULT_MAX_TORSO_ROTATION = 20.0  # Max torso rotation angle (deg) - Phase 8A frozen spec

mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils


def load_model(model_path=MODEL_PATH):
    """Load the Assisted Elbow LSTM model for research/experimental inference."""
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    model = ExerciseLSTM(
        input_size=len(FEATURE_NAMES),
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3,
    )

    if model_path.exists():
        model.load_state_dict(
            torch.load(
                model_path,
                map_location=device,
                weights_only=True,
            )
        )
    model.to(device)
    model.eval()
    return model, device


def save_elbow_error_frame(
    frame: np.ndarray,
    pose_landmarks,
    error_type: str,
    rep_number: int,
    frame_number: int,
    output_dir: str,
) -> str:
    """Save an annotated visual artifact highlighting the form compensation."""
    os.makedirs(output_dir, exist_ok=True)
    annotated = frame.copy()
    red = (0, 0, 255)
    yellow = (0, 255, 255)

    mp_drawing.draw_landmarks(
        annotated,
        pose_landmarks,
        mp_pose.POSE_CONNECTIONS,
        mp_drawing.DrawingSpec(color=red, thickness=2, circle_radius=2),
        mp_drawing.DrawingSpec(color=red, thickness=2),
    )

    h, w = annotated.shape[:2]
    lm = pose_landmarks.landmark

    # Highlight affected joints
    if "FLARE" in error_type:
        highlight_joints = [11, 13, 15, 12, 14, 16]
    elif "TILT" in error_type:
        highlight_joints = [11, 12, 24, 23]
    else:
        highlight_joints = [13, 14]

    for j in highlight_joints:
        cx, cy = int(lm[j].x * w), int(lm[j].y * h)
        cv2.circle(annotated, (cx, cy), 8, yellow, -1)

    cv2.putText(
        annotated,
        f"FORM ERROR: {error_type}",
        (30, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        red,
        2,
    )

    filename = f"assisted_elbow_rep_{rep_number:02d}_{error_type}_f{frame_number}.jpg"
    path = os.path.join(output_dir, filename)
    cv2.imwrite(path, annotated)
    return path


class AssistedElbowFlexionAssessment:
    """Live assessment engine for Assisted Elbow Flexion.
    
    Exposes separate Biomechanical/Rule-based evaluation and Learned ML prediction.
    """

    def __init__(
        self,
        model=None,
        device=None,
        fps: float = 30.0,
        assistance_type: str = "both_hand_assisted",
        data_dir: str = "data",
        save_artifacts: bool = True,
        # Biomechanical evaluation thresholds (configurable)
        max_flexion_angle_threshold: float = DEFAULT_MAX_FLEXION_ANGLE,
        max_elbow_flare_threshold: float = DEFAULT_MAX_ELBOW_FLARE,
        min_rom_threshold: float = DEFAULT_MIN_ROM_EVAL,
        max_torso_rotation_threshold: float = DEFAULT_MAX_TORSO_ROTATION,
        primary_evaluator: str = "biomechanical_rules",  # "biomechanical_rules" or "ml_model"
    ):
        self.fps = max(fps, 1.0)
        self.assistance_type = assistance_type
        self.data_dir = data_dir
        self.save_artifacts = save_artifacts

        # Biomechanical thresholds (frozen production specification)
        self.max_flexion_angle_threshold = max_flexion_angle_threshold
        self.max_elbow_flare_threshold = max_elbow_flare_threshold
        self.min_rom_threshold = min_rom_threshold
        self.max_torso_rotation_threshold = max_torso_rotation_threshold
        self.primary_evaluator = primary_evaluator

        self.error_frames_dir = os.path.join(data_dir, "error_frames")
        self.session_records_dir = os.path.join(data_dir, "session_records")

        # Optional ML model initialization
        self.model = None
        self.device = device or torch.device("cpu")
        if model is not None:
            self.model = model
            self.device = device or torch.device("cpu")
        else:
            try:
                self.model, self.device = load_model(MODEL_PATH)
            except Exception:
                self.model = None

        self.reset_session()

    @classmethod
    def from_model_path(cls, model_path=MODEL_PATH, **kwargs):
        model, device = load_model(Path(model_path))
        return cls(model=model, device=device, **kwargs)

    def reset_session(self):
        self.state = "EXTENDED"
        self.rep_count = 0
        self.frame_number = 0
        self.rep_start_frame = None
        self.min_angle_in_rep = 180.0
        self.current_angle = 180.0
        self.current_left_angle = 180.0
        self.current_right_angle = 180.0
        self.current_detected_mode = "Both Arms (Ready)"
        self.last_rep_mode = "both"
        self.current_feedback = "Ready: Bend your elbow(s) to begin."
        self.last_result = {}

        self.rep_kinematics_buffer = []
        self.active_error = None
        self.error_frame_path = None

        # Independent per-arm state tracking
        self.arm_states = {
            "left": {
                "state": "EXTENDED",
                "start_frame": None,
                "min_angle": 180.0,
                "raw_buffer": [],
                "rom": 0.0,
            },
            "right": {
                "state": "EXTENDED",
                "start_frame": None,
                "min_angle": 180.0,
                "raw_buffer": [],
                "rom": 0.0,
            },
        }
        self.pending_candidate = None

    def _update_arm_state(self, side: str, raw_k: Dict, angle: float):
        tracker = self.arm_states[side]
        st = tracker["state"]

        if st == "EXTENDED":
            if angle < DEFAULT_FLEXION_THRESHOLD:
                tracker["state"] = "FLEXING"
                tracker["start_frame"] = self.frame_number
                tracker["min_angle"] = angle
                tracker["raw_buffer"] = [raw_k]
        elif st == "FLEXING":
            tracker["raw_buffer"].append(raw_k)
            tracker["min_angle"] = min(tracker["min_angle"], angle)
            if angle > (tracker["min_angle"] + 12.0):
                tracker["state"] = "EXTENDING"
        elif st == "EXTENDING":
            tracker["raw_buffer"].append(raw_k)
            if angle >= DEFAULT_START_EXTEND_ANGLE:
                angles = [k[f"{side}_angle"] for k in tracker["raw_buffer"]]
                rom = float(np.max(angles) - np.min(angles)) if angles else 0.0
                tracker["rom"] = rom
                if rom >= self.min_rom_threshold and len(tracker["raw_buffer"]) >= DEFAULT_MIN_REP_FRAMES:
                    tracker["state"] = "COMPLETED_CANDIDATE"
                else:
                    tracker["state"] = "EXTENDED"
                    tracker["raw_buffer"] = []

    def _check_and_resolve_candidates(self) -> Optional[Dict]:
        l_ready = (
            self.arm_states["left"]["state"] == "COMPLETED_CANDIDATE"
            and self.arm_states["left"]["rom"] >= self.min_rom_threshold
            and len(self.arm_states["left"]["raw_buffer"]) >= DEFAULT_MIN_REP_FRAMES
        )
        r_ready = (
            self.arm_states["right"]["state"] == "COMPLETED_CANDIDATE"
            and self.arm_states["right"]["rom"] >= self.min_rom_threshold
            and len(self.arm_states["right"]["raw_buffer"]) >= DEFAULT_MIN_REP_FRAMES
        )

        # 1. Both arms finished their cycle together
        if l_ready and r_ready:
            self.pending_candidate = None
            return self._finalize_repetition(mode="both")

        # 2. Left arm finished; check if right arm is participating
        if l_ready and not r_ready:
            r_st = self.arm_states["right"]["state"]
            if r_st in ("FLEXING", "EXTENDING"):
                if self.pending_candidate is None:
                    self.pending_candidate = {"primary": "left", "frame": self.frame_number}
            else:
                self.pending_candidate = None
                return self._finalize_repetition(mode="left")

        # 3. Right arm finished; check if left arm is participating
        if r_ready and not l_ready:
            l_st = self.arm_states["left"]["state"]
            if l_st in ("FLEXING", "EXTENDING"):
                if self.pending_candidate is None:
                    self.pending_candidate = {"primary": "right", "frame": self.frame_number}
            else:
                self.pending_candidate = None
                return self._finalize_repetition(mode="right")

        # 4. Handle pending candidate synchronization timeout or partner arrival
        if self.pending_candidate is not None:
            prim = self.pending_candidate["primary"]
            other = "right" if prim == "left" else "left"
            other_ready = (
                self.arm_states[other]["state"] == "COMPLETED_CANDIDATE"
                and self.arm_states[other]["rom"] >= self.min_rom_threshold
                and len(self.arm_states[other]["raw_buffer"]) >= DEFAULT_MIN_REP_FRAMES
            )
            if other_ready:
                self.pending_candidate = None
                return self._finalize_repetition(mode="both")

            elapsed_frames = self.frame_number - self.pending_candidate["frame"]
            max_wait_frames = int(self.fps * 0.75)  # 0.75s grace window
            if elapsed_frames > max_wait_frames:
                mode = prim
                self.pending_candidate = None
                return self._finalize_repetition(mode=mode)

        return None

    def _finalize_repetition(self, mode: str) -> Optional[Dict]:
        self.rep_count += 1
        self.last_rep_mode = mode

        # Collect raw kinematics for this repetition
        if mode == "both":
            l_buf = self.arm_states["left"]["raw_buffer"]
            r_buf = self.arm_states["right"]["raw_buffer"]
            raw_buf = l_buf if len(l_buf) >= len(r_buf) else r_buf
            rep_k = [map_canonical_features(rk, "both_hand_assisted") for rk in raw_buf]
        elif mode == "left":
            raw_buf = self.arm_states["left"]["raw_buffer"]
            rep_k = [map_canonical_features(rk, "left_hand_assisted") for rk in raw_buf]
        else:
            raw_buf = self.arm_states["right"]["raw_buffer"]
            rep_k = [map_canonical_features(rk, "right_hand_assisted") for rk in raw_buf]

        # Reset trackers
        self.arm_states["left"]["state"] = "EXTENDED"
        self.arm_states["left"]["raw_buffer"] = []
        self.arm_states["right"]["state"] = "EXTENDED"
        self.arm_states["right"]["raw_buffer"] = []
        self.state = "EXTENDED"
        self.rep_start_frame = None

        if len(rep_k) < DEFAULT_MIN_REP_FRAMES:
            return None

        self.rep_kinematics_buffer = rep_k
        duration = len(rep_k) / self.fps

        if mode == "both":
            l_angles = np.array([rk["left_angle"] for rk in raw_buf])
            r_angles = np.array([rk["right_angle"] for rk in raw_buf])
            rom = float(min(np.max(l_angles) - np.min(l_angles), np.max(r_angles) - np.min(r_angles)))
            active_angles = (l_angles + r_angles) / 2.0
        elif mode == "left":
            active_angles = np.array([rk["left_angle"] for rk in raw_buf])
            rom = float(np.max(active_angles) - np.min(active_angles))
        else:
            active_angles = np.array([rk["right_angle"] for rk in raw_buf])
            rom = float(np.max(active_angles) - np.min(active_angles))

        if len(active_angles) >= 3:
            smoothness = float(1.0 / (1.0 + np.mean(np.abs(np.diff(active_angles, n=2)))))
        else:
            smoothness = 0.0

        biomech_eval = self.evaluate_biomechanics_multilateral(
            raw_buf=raw_buf,
            mode=mode,
            rom=rom,
            duration=duration,
            smoothness=smoothness,
        )

        ml_prediction = {
            "available": False,
            "predicted_class": "Not Evaluated",
            "confidence_pct": 0.0,
            "model_architecture": "ExerciseLSTM (2-layer, 8-feature)",
            "evaluation_note": "ML model retained for research; true LOSO demonstrates 58.30% balanced accuracy on human-verified labels across 3 subjects.",
        }

        if self.model is not None:
            try:
                seq_matrix = build_normalized_sequence(
                    rep_k,
                    target_length=SEQUENCE_LENGTH,
                )
                seq_tensor = (
                    torch.tensor(seq_matrix, dtype=torch.float32)
                    .unsqueeze(0)
                    .to(self.device)
                )
                with torch.no_grad():
                    logits = self.model(seq_tensor)
                    probs = torch.softmax(logits, dim=1).cpu().numpy()[0]
                    pred_class_idx = int(np.argmax(probs))
                    confidence = float(probs[pred_class_idx])

                ml_prediction["available"] = True
                ml_prediction["predicted_class"] = "Correct" if pred_class_idx == 0 else "Incorrect"
                ml_prediction["confidence_pct"] = round(confidence * 100.0, 2)
            except Exception as e:
                ml_prediction["error"] = str(e)

        if self.primary_evaluator == "ml_model" and ml_prediction["available"]:
            primary_form = ml_prediction["predicted_class"]
            primary_feedback = (
                f"ML Prediction: {primary_form} ({ml_prediction['confidence_pct']}% confidence). "
                + biomech_eval["feedback"]
            )
        else:
            primary_form = biomech_eval["status"]
            primary_feedback = biomech_eval["feedback"]

        if primary_form == "Correct":
            score = float(np.clip(70.0 + min(rom, 60.0) * 0.3 + smoothness * 12.0, 70.0, 100.0))
        else:
            score = float(np.clip(30.0 + min(rom, 40.0) * 0.4, 0.0, 65.0))

        mode_desc = "Both-Hand Assisted" if mode == "both" else ("Left-Hand Assisted" if mode == "left" else "Right-Hand Assisted")
        rep_record = {
            "exercise": "Assisted Elbow Flexion",
            "rep_number": self.rep_count,
            "primary_assessment_method": self.primary_evaluator,
            "form": primary_form,
            "score": round(score, 1),
            "feedback": primary_feedback,
            "detected_mode": mode_desc,
            "biomechanical_assessment": biomech_eval,
            "learned_ml_prediction": ml_prediction,
            "range_of_motion": round(rom, 1),
            "duration": round(duration, 2),
            "smoothness": round(smoothness, 3),
            "error_type": self.active_error,
            "error_frame_path": self.error_frame_path,
            "assistance_type": mode_desc,
            "timestamp": datetime.now().isoformat(),
        }

        if self.save_artifacts:
            os.makedirs(self.session_records_dir, exist_ok=True)
            record_path = os.path.join(
                self.session_records_dir,
                f"assisted_elbow_rep_{self.rep_count:02d}.json",
            )
            with open(record_path, "w", encoding="utf-8") as f:
                json.dump(rep_record, f, indent=2)

        self.last_result = rep_record
        return rep_record

    def evaluate_biomechanics_multilateral(
        self,
        raw_buf: List[Dict[str, float]],
        mode: str,
        rom: float,
        duration: float,
        smoothness: float,
    ) -> Dict:
        """Evaluate repetition against frozen deterministic biomechanical criteria.
        
        Rules:
        - Minimum elbow angle <= 101.0° (checked on active arm(s); in bilateral, left arm is not ignored)
        - Active elbow flare <= 0.30
        - Range of motion >= 25.0°
        - Torso rotation <= 20.0°
        """
        tilts = np.array([rk["torso_tilt"] for rk in raw_buf])
        rotations = np.array([abs(rk["torso_rotation"]) for rk in raw_buf])
        peak_tilt = float(np.max(tilts)) if len(tilts) > 0 else 0.0
        peak_rotation = float(np.max(rotations)) if len(rotations) > 0 else 0.0

        violations = []
        feedback_notes = []

        if mode == "both":
            l_ang = np.array([rk["left_angle"] for rk in raw_buf])
            r_ang = np.array([rk["right_angle"] for rk in raw_buf])
            min_l, min_r = float(np.min(l_ang)), float(np.min(r_ang))
            max_l, max_r = float(np.max(l_ang)), float(np.max(r_ang))
            l_rom, r_rom = max_l - min_l, max_r - min_r
            l_flare = np.array([rk["left_flare"] for rk in raw_buf])
            r_flare = np.array([rk["right_flare"] for rk in raw_buf])
            peak_flare = float(max(np.max(l_flare), np.max(r_flare)))
            mean_flare = float((np.mean(l_flare) + np.mean(r_flare)) / 2.0)
            min_angle = max(min_l, min_r)

            # 1. Flexion Depth Check (both arms evaluated)
            if min_l > self.max_flexion_angle_threshold and min_r > self.max_flexion_angle_threshold:
                violations.append("insufficient_elbow_flexion")
                feedback_notes.append(
                    f"Insufficient flexion in both elbows (L: {min_l:.1f}°, R: {min_r:.1f}°, required <= {self.max_flexion_angle_threshold:.1f}°)."
                )
            elif min_l > self.max_flexion_angle_threshold:
                violations.append("insufficient_left_elbow_flexion")
                feedback_notes.append(
                    f"Left elbow insufficient flexion (achieved {min_l:.1f}°, required <= {self.max_flexion_angle_threshold:.1f}°)."
                )
            elif min_r > self.max_flexion_angle_threshold:
                violations.append("insufficient_right_elbow_flexion")
                feedback_notes.append(
                    f"Right elbow insufficient flexion (achieved {min_r:.1f}°, required <= {self.max_flexion_angle_threshold:.1f}°)."
                )

            # 2. Elbow Flare Check
            if peak_flare > self.max_elbow_flare_threshold:
                violations.append("excessive_elbow_flare")
                feedback_notes.append(
                    f"Excessive elbow flare (peak {peak_flare:.2f}, limit <= {self.max_elbow_flare_threshold:.2f}). Keep elbows close to torso."
                )

            # 3. Minimum ROM Check
            if min(l_rom, r_rom) < self.min_rom_threshold:
                violations.append("insufficient_rom")
                feedback_notes.append(
                    f"Insufficient range of motion (L: {l_rom:.1f}°, R: {r_rom:.1f}°, required >= {self.min_rom_threshold:.1f}°)."
                )

        else:
            side = mode
            ang = np.array([rk[f"{side}_angle"] for rk in raw_buf])
            min_angle = float(np.min(ang))
            flare_arr = np.array([rk[f"{side}_flare"] for rk in raw_buf])
            peak_flare = float(np.max(flare_arr))
            mean_flare = float(np.mean(flare_arr))

            # 1. Flexion Depth
            if min_angle > self.max_flexion_angle_threshold:
                violations.append(f"insufficient_{side}_elbow_flexion")
                feedback_notes.append(
                    f"Insufficient {side} elbow flexion (achieved {min_angle:.1f}°, required <= {self.max_flexion_angle_threshold:.1f}°)."
                )

            # 2. Flare
            if peak_flare > self.max_elbow_flare_threshold:
                violations.append("excessive_elbow_flare")
                feedback_notes.append(
                    f"Excessive elbow flare (peak {peak_flare:.2f}, limit <= {self.max_elbow_flare_threshold:.2f}). Keep elbow close to torso."
                )

            # 3. Minimum ROM
            if rom < self.min_rom_threshold:
                violations.append("insufficient_rom")
                feedback_notes.append(
                    f"Insufficient range of motion ({rom:.1f}°, required >= {self.min_rom_threshold:.1f}°)."
                )

        # 4. Torso Compensation Check (Transverse Rotation)
        if peak_rotation > self.max_torso_rotation_threshold:
            violations.append("excessive_torso_rotation")
            feedback_notes.append(
                f"Torso rotation detected ({peak_rotation:.1f}°, limit <= {self.max_torso_rotation_threshold:.1f}°). Keep shoulders square."
            )

        rule_passed = len(violations) == 0
        if rule_passed:
            status = "Correct"
            summary_feedback = f"Acceptable {mode} movement: good flexion depth and controlled alignment."
        else:
            status = "Incorrect"
            summary_feedback = "Form adjustment needed: " + " ".join(feedback_notes)

        return {
            "status": status,
            "rule_passed": rule_passed,
            "violations": violations,
            "feedback": summary_feedback,
            "metrics": {
                "detected_mode": mode,
                "min_elbow_angle": round(min_angle, 1),
                "rom": round(rom, 1),
                "peak_elbow_flare": round(peak_flare, 3),
                "mean_elbow_flare": round(mean_flare, 3),
                "peak_torso_tilt": round(peak_tilt, 1),
                "peak_torso_rotation": round(peak_rotation, 1),
                "duration": round(duration, 2),
                "smoothness": round(smoothness, 3),
            },
            "thresholds_used": {
                "max_flexion_angle": self.max_flexion_angle_threshold,
                "max_elbow_flare": self.max_elbow_flare_threshold,
                "min_rom": self.min_rom_threshold,
                "max_torso_rotation": self.max_torso_rotation_threshold,
            },
            "evaluation_note": (
                "Authoritative active biomechanical assessment engine for user scoring and form feedback."
            ),
        }

    def evaluate_biomechanics(
        self,
        rep_kinematics: List[Dict[str, float]],
        rom: float,
        duration: float,
        smoothness: float,
    ) -> Dict:
        """Legacy compatibility wrapper for evaluate_biomechanics."""
        angles = np.array([k["active_elbow_angle"] for k in rep_kinematics])
        flares = np.array([k["active_elbow_flare"] for k in rep_kinematics])
        tilts = np.array([k["torso_tilt"] for k in rep_kinematics])
        rotations = np.array([k["torso_rotation"] for k in rep_kinematics])

        min_angle = float(np.min(angles))
        max_angle = float(np.max(angles))
        peak_flare = float(np.max(flares))
        mean_flare = float(np.mean(flares))
        peak_tilt = float(np.max(tilts))
        peak_rotation = float(np.max(np.abs(rotations)))

        violations = []
        feedback_notes = []

        if min_angle > self.max_flexion_angle_threshold:
            violations.append("insufficient_elbow_flexion")
            feedback_notes.append(
                f"Insufficient elbow flexion (achieved {min_angle:.1f}°, required <= {self.max_flexion_angle_threshold:.1f}°)."
            )
        if peak_flare > self.max_elbow_flare_threshold:
            violations.append("excessive_elbow_flare")
            feedback_notes.append(
                f"Excessive elbow flare (peak {peak_flare:.2f}, limit <= {self.max_elbow_flare_threshold:.2f}). Keep elbow close to torso."
            )
        if rom < self.min_rom_threshold:
            violations.append("insufficient_rom")
            feedback_notes.append(
                f"Insufficient range of motion ({rom:.1f}°, required >= {self.min_rom_threshold:.1f}°)."
            )
        if peak_rotation > self.max_torso_rotation_threshold:
            violations.append("excessive_torso_rotation")
            feedback_notes.append(
                f"Torso rotation detected ({peak_rotation:.1f}°, required <= {self.max_torso_rotation_threshold:.1f}°). Keep shoulders square."
            )

        rule_passed = len(violations) == 0
        status = "Correct" if rule_passed else "Incorrect"
        summary_feedback = (
            "Acceptable movement: good flexion depth and controlled elbow alignment."
            if rule_passed
            else "Form adjustment needed: " + " ".join(feedback_notes)
        )

        return {
            "status": status,
            "rule_passed": rule_passed,
            "violations": violations,
            "feedback": summary_feedback,
            "metrics": {
                "min_elbow_angle": round(min_angle, 1),
                "max_elbow_angle": round(max_angle, 1),
                "rom": round(rom, 1),
                "peak_elbow_flare": round(peak_flare, 3),
                "mean_elbow_flare": round(mean_flare, 3),
                "peak_torso_tilt": round(peak_tilt, 1),
                "peak_torso_rotation": round(peak_rotation, 1),
                "duration": round(duration, 2),
                "smoothness": round(smoothness, 3),
            },
            "thresholds_used": {
                "max_flexion_angle": self.max_flexion_angle_threshold,
                "max_elbow_flare": self.max_elbow_flare_threshold,
                "min_rom": self.min_rom_threshold,
                "max_torso_rotation": self.max_torso_rotation_threshold,
            },
            "evaluation_note": (
                "Authoritative active biomechanical assessment engine for user scoring and form feedback."
            ),
        }

    def process_frame(
        self,
        frame: np.ndarray,
        pose_landmarks,
        frame_number: Optional[int] = None,
    ) -> Optional[Dict]:
        """Process one frame and return completed repetition result if a rep ended."""
        self.frame_number = (
            self.frame_number + 1 if frame_number is None else frame_number
        )

        if pose_landmarks is None:
            self.current_feedback = "Position yourself in camera view."
            return None

        raw_k = extract_frame_kinematics(pose_landmarks)
        left_angle = raw_k["left_angle"]
        right_angle = raw_k["right_angle"]
        left_flare = raw_k["left_flare"]
        right_flare = raw_k["right_flare"]
        rot = abs(raw_k["torso_rotation"])

        self.current_left_angle = left_angle
        self.current_right_angle = right_angle
        self.current_angle = min(left_angle, right_angle)

        # Real-time visual cue detection during frame
        rule_error = None
        peak_flare_inst = max(left_flare, right_flare)
        if peak_flare_inst > self.max_elbow_flare_threshold:
            rule_error = "ELBOW_FLARE_DETECTED"
            self.current_feedback = "Keep your elbow(s) tucked close to your torso."
        elif rot > self.max_torso_rotation_threshold:
            rule_error = "TORSO_ROTATION_DETECTED"
            self.current_feedback = "Keep your shoulders square without twisting."

        if rule_error and self.active_error is None:
            self.active_error = rule_error
            if self.save_artifacts:
                self.error_frame_path = save_elbow_error_frame(
                    frame,
                    pose_landmarks,
                    rule_error,
                    self.rep_count + 1,
                    self.frame_number,
                    self.error_frames_dir,
                )

        # Update per-arm state machines
        self._update_arm_state("left", raw_k, left_angle)
        self._update_arm_state("right", raw_k, right_angle)

        # Check for completed repetition(s)
        completed_rep = self._check_and_resolve_candidates()

        # Update unified live movement state
        l_st = self.arm_states["left"]["state"]
        r_st = self.arm_states["right"]["state"]

        if l_st == "FLEXING" and r_st == "FLEXING":
            self.state = "FLEXING"
            self.current_detected_mode = "Both Arms (Bilateral)"
            if not rule_error:
                self.current_feedback = "Flexing: Lift both arms smoothly towards shoulders."
        elif l_st == "FLEXING":
            self.state = "FLEXING"
            self.current_detected_mode = "Left Arm"
            if not rule_error:
                self.current_feedback = "Flexing: Lift left arm smoothly towards shoulder."
        elif r_st == "FLEXING":
            self.state = "FLEXING"
            self.current_detected_mode = "Right Arm"
            if not rule_error:
                self.current_feedback = "Flexing: Lift right arm smoothly towards shoulder."
        elif l_st == "EXTENDING" and r_st == "EXTENDING":
            self.state = "EXTENDING"
            self.current_detected_mode = "Both Arms (Bilateral)"
            if not rule_error:
                self.current_feedback = "Extending: Lower both arms slowly and with control."
        elif l_st == "EXTENDING":
            self.state = "EXTENDING"
            self.current_detected_mode = "Left Arm"
            if not rule_error:
                self.current_feedback = "Extending: Lower left arm slowly and with control."
        elif r_st == "EXTENDING":
            self.state = "EXTENDING"
            self.current_detected_mode = "Right Arm"
            if not rule_error:
                self.current_feedback = "Extending: Lower right arm slowly and with control."
        else:
            self.state = "EXTENDED"
            self.current_detected_mode = "Both Arms (Ready)"
            if self.rep_count == 0 and not rule_error:
                self.current_feedback = "Ready: Bend your elbow(s) to begin."

        return completed_rep

    def get_live_state(
        self,
        pose_landmarks=None,
    ) -> Dict:
        """Return the current assessment state for a live client."""
        landmarks_output = []
        if pose_landmarks is not None:
            for landmark in pose_landmarks.landmark:
                landmarks_output.append(
                    {
                        "x": float(landmark.x),
                        "y": float(landmark.y),
                        "z": float(landmark.z),
                        "visibility": float(landmark.visibility),
                    }
                )

        if self.state == "EXTENDED":
            if self.rep_count > 0:
                form = str(self.last_result.get("form", "Waiting")).lower()
                feedback = self.last_result.get("feedback", self.current_feedback)
                score = self.last_result.get("score", 0.0)
                rom = self.last_result.get("range_of_motion", 0.0)
                speed = self.last_result.get("speed", "Waiting")
                smoothness = self.last_result.get("smoothness", 0.0)
            else:
                form = "waiting"
                feedback = self.current_feedback
                score = 0.0
                rom = 0.0
                speed = "Waiting"
                smoothness = 0.0
        else:
            if self.active_error is not None:
                form = "incorrect"
            else:
                form = "correct"
            feedback = self.current_feedback
            score = self.last_result.get("score", 0.0)
            if len(self.rep_kinematics_buffer) > 0:
                angles = [k["active_elbow_angle"] for k in self.rep_kinematics_buffer]
                rom = float(np.max(angles) - np.min(angles))
            else:
                rom = 0.0

            if self.rep_start_frame is not None:
                elapsed = (self.frame_number - self.rep_start_frame) / self.fps
                if elapsed < 1.2:
                    speed = "Fast"
                elif elapsed <= 3.5:
                    speed = "Good"
                else:
                    speed = "Slow"
            else:
                speed = "Waiting"

            if len(self.rep_kinematics_buffer) >= 3:
                angles_arr = np.array([k["active_elbow_angle"] for k in self.rep_kinematics_buffer])
                smoothness = float(1.0 / (1.0 + np.mean(np.abs(np.diff(angles_arr, n=2))))) * 100.0
            else:
                smoothness = 0.0

        return {
            "exercise": "Assisted Elbow Flexion",
            "state": self.state,
            "rep_count": int(self.rep_count),
            "form": form,
            "error_type": self.active_error,
            "feedback": feedback,
            "score": float(score) if score is not None else 0.0,
            "range_of_motion": float(rom) if rom is not None else 0.0,
            "speed": speed,
            "smoothness": float(smoothness),
            "angle": float(getattr(self, "current_angle", 0.0)),
            "left_angle": float(getattr(self, "current_left_angle", 0.0)),
            "right_angle": float(getattr(self, "current_right_angle", 0.0)),
            "detected_mode": getattr(self, "current_detected_mode", "Both Arms (Ready)"),
            "landmarks": landmarks_output,
        }

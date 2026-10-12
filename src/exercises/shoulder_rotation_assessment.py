from datetime import datetime
from pathlib import Path
import json
from uuid import uuid4

import cv2
import numpy as np
import torch

from src.models.lstm_model import ExerciseLSTM
from src.feedback.rotation_cycle_detector import RotationCycleDetector
from src.exercises.shoulder_rotation import (
    INPUT_SIZE,
    SEQUENCE_LENGTH,
    ANGLE_SCALE,
    ANGULAR_VELOCITY_SCALE,
    TORSO_TILT_SCALE,
    MIN_ROTATION_EXCURSION_DEG,
    MIN_REP_FRAMES,
    MIN_REP_DURATION,
    SIDE_EXCURSION_DEG,
    CENTRE_RETURN_BAND_DEG,
    REP_DEFINITION,
)
from src.features.shoulder_rotation_features import (
    angle3,
    forearm_rotation_angle,
)


class ShoulderRotationAssessment:
    """
    Count centre -> extreme -> centre -> opposite extreme, then require reset.

    Classification uses the configured trained model; detection applies engineering
    motion thresholds and does not decide clinical correctness.
    """

    DIRECTION_CONFIRM_FRAMES = 3
    SMOOTH_WINDOW = 3

    def __init__(
        self,
        model,
        device,
        fps=20.0,
        data_dir="data",
        save_artifacts=True,
    ):
        self.model = model
        self.device = device
        self.fps = float(fps) if fps and fps > 0 else 30.0
        self.dt = 1.0 / self.fps

        self.data_dir = Path(data_dir)
        self.save_artifacts = save_artifacts
        self.session_id = uuid4().hex
        self._timestamp_origin = None
        self._previous_timestamp = None
        self._previous_observation = None
        self._next_sample = 0
        self._previous_sample = None

        self.error_frames_dir = self.data_dir / "error_frames"
        self.session_records_dir = self.data_dir / "session_records"

        if self.save_artifacts:
            self.error_frames_dir.mkdir(parents=True, exist_ok=True)
            self.session_records_dir.mkdir(parents=True, exist_ok=True)

        # Exact live state used by friend's deployment.
        self.previous_right = None
        self.previous_left = None

        self.smooth_signal = []
        self.previous_smoothed = None

        self.current_direction = 0
        self.candidate_direction = 0
        self.candidate_count = 0

        self.last_extreme_value = None
        self.last_extreme_frame = None

        self.cycle_start_extreme = None
        self.cycle_start_direction = None

        # Friend implementation collects features continuously, including
        # before the first detected turning point.
        self.rep_features = []
        self.feature_frames = []
        self.cycle_detector = RotationCycleDetector(
            excursion=SIDE_EXCURSION_DEG, return_band=CENTRE_RETURN_BAND_DEG,
            min_frames=MIN_REP_FRAMES,
            max_frames=int(self.fps * 25),
            calibration_frames=max(1, round(self.fps * 0.5)),
            confirm_frames=max(1, round(self.fps * 0.15)),
        )

        self.frame_number = 0
        self.rep_count = 0

        self.last_form = "WAITING"
        self.last_confidence = 0.0
        self.last_prediction = None
        self.last_probabilities = [0.0, 0.0]

        self.last_result = {}
        self.current_feedback = "Get ready for shoulder rotation."

        self.live_right_angle = 0.0
        self.live_left_angle = 0.0
        self.live_torso_tilt = 0.0
        self.live_torso_rotation = 0.0
        self.live_rotation_signal = 0.0
        self.tracking_ok = False

    @staticmethod
    def _point(landmarks, index):
        lm = landmarks.landmark[index]
        return np.array([lm.x, lm.y, lm.z], dtype=np.float32)

    @staticmethod
    def _visibility(landmarks, index):
        return float(getattr(landmarks.landmark[index], "visibility", 0.0))

    @staticmethod
    def _resize_signal(values, length=SEQUENCE_LENGTH):
        values = np.asarray(values, dtype=np.float32)

        if len(values) <= 1:
            return np.zeros(length, dtype=np.float32)

        old_x = np.linspace(0.0, 1.0, len(values))
        new_x = np.linspace(0.0, 1.0, length)

        return np.interp(new_x, old_x, values).astype(np.float32)

    @staticmethod
    def _normalize_sequence(sequence):
        sequence = np.asarray(sequence, dtype=np.float32)

        sequence[:, 0:2] /= ANGLE_SCALE
        sequence[:, 2:4] /= ANGULAR_VELOCITY_SCALE
        sequence[:, 4:6] /= ANGLE_SCALE
        sequence[:, 8] /= TORSO_TILT_SCALE

        return np.nan_to_num(
            sequence,
            nan=0.0,
            posinf=0.0,
            neginf=0.0,
        )

    def _extract_feature(self, landmarks):
        left_shoulder = self._point(landmarks, 11)
        right_shoulder = self._point(landmarks, 12)
        left_elbow = self._point(landmarks, 13)
        right_elbow = self._point(landmarks, 14)
        left_wrist = self._point(landmarks, 15)
        right_wrist = self._point(landmarks, 16)
        left_hip = self._point(landmarks, 23)
        right_hip = self._point(landmarks, 24)

        shoulder_mid = (
            left_shoulder + right_shoulder
        ) / 2.0

        hip_mid = (
            left_hip + right_hip
        ) / 2.0

        torso = shoulder_mid - hip_mid

        right_rotation = forearm_rotation_angle(
            right_elbow,
            right_wrist,
        )
        left_rotation = forearm_rotation_angle(
            left_elbow,
            left_wrist,
        )

        # Unwrap each observed azimuth relative to the preceding observation.
        # These remain the legacy LSTM features; counting uses bilateral lateral
        # hand displacement instead of averaging noisy/cancelling depth angles.
        if self.previous_right is not None:
            right_rotation = self.previous_right + (right_rotation - self.previous_right + 180) % 360 - 180
            left_rotation = self.previous_left + (left_rotation - self.previous_left + 180) % 360 - 180

        if self.previous_right is None:
            right_velocity = 0.0
            left_velocity = 0.0
        else:
            right_velocity = (
                right_rotation - self.previous_right
            ) / self.dt

            left_velocity = (
                left_rotation - self.previous_left
            ) / self.dt

        self.previous_right = right_rotation
        self.previous_left = left_rotation

        torso_tilt = np.degrees(
            np.arctan2(
                abs(torso[0]),
                abs(torso[1]) + 1e-8,
            )
        )

        shoulder_width = np.linalg.norm(
            (right_shoulder - left_shoulder)[:2]
        )

        torso_rotation = (
            right_shoulder[2] - left_shoulder[2]
        ) / (shoulder_width + 1e-8)

        feature = np.asarray(
            [
                right_rotation,
                left_rotation,
                right_velocity,
                left_velocity,
                angle3(
                    right_shoulder,
                    right_elbow,
                    right_wrist,
                ),
                angle3(
                    left_shoulder,
                    left_elbow,
                    left_wrist,
                ),
                min(
                    self._visibility(landmarks, i)
                    for i in [12, 14, 16]
                ),
                min(
                    self._visibility(landmarks, i)
                    for i in [11, 13, 15]
                ),
                torso_tilt,
                torso_rotation,
            ],
            dtype=np.float32,
        )

        width = float(shoulder_width)
        if width < 0.08 or abs(right_shoulder[0] - left_shoulder[0]) / max(width, 1e-8) < 0.7:
            return np.full(14, np.nan, dtype=np.float32)
        # Wrists aligned ahead of their respective elbows define centre in a
        # frontal view. Both must reach the same side; one arm cannot count.
        movement = [(right_wrist[0] - right_elbow[0]) / width * 90,
                    (left_wrist[0] - left_elbow[0]) / width * 90]
        # Distance perpendicular to the torso axis, avoiding the old metric
        # which treated normal upper-arm length as elbow drift.
        axis = torso[:2] / max(np.linalg.norm(torso[:2]), 1e-8)
        perpendicular = np.array([-axis[1], axis[0]])
        upper_arm = [abs(np.dot((right_elbow - right_shoulder)[:2], perpendicular)) / width,
                     abs(np.dot((left_elbow - left_shoulder)[:2], perpendicular)) / width]
        return np.concatenate([feature, movement, upper_arm]).astype(np.float32)

    def _classify_rep(self, features):
        data = np.asarray(features, dtype=np.float32)

        matrix = np.column_stack(
            [
                self._resize_signal(data[:, j])
                for j in range(INPUT_SIZE)
            ]
        )

        matrix = self._normalize_sequence(matrix)

        x = torch.tensor(
            matrix,
            dtype=torch.float32,
        ).unsqueeze(0).to(self.device)

        with torch.no_grad():
            output = self.model(x)
            probabilities = torch.softmax(output, dim=1)[0]

        prediction = int(
            torch.argmax(probabilities).item()
        )
        confidence = float(
            probabilities[prediction].item()
        )

        return (
            prediction,
            confidence,
            probabilities.detach().cpu().numpy(),
        )

    def _save_error_frame(self, frame):
        if not self.save_artifacts or frame is None:
            return None

        filename = (
            f"shoulder_rotation_{self.session_id}_rep_{self.rep_count}_"
            f"incorrect_frame_{self.frame_number}.jpg"
        )

        path = self.error_frames_dir / filename

        if cv2.imwrite(str(path), frame):
            return str(path)

        return None

    def _complete_rep(self, frame):
        prediction, confidence, probabilities = (
            self._classify_rep(self.rep_features)
        )

        self.rep_count += 1

        self.last_prediction = prediction
        self.last_confidence = confidence
        self.last_probabilities = probabilities.tolist()

        self.last_form = (
            "CORRECT"
            if prediction == 0
            else "INCORRECT"
        )

        form = (
            "Correct"
            if prediction == 0
            else "Incorrect"
        )

        data = np.asarray(
            self.rep_features,
            dtype=np.float32,
        )

        errors = []
        # Require a sustained fraction of a rep, rather than rejecting jitter.
        if np.mean(np.any(np.abs(data[:, 4:6] - 90) > 30, axis=1)) >= 0.2:
            errors.append(("ELBOW_ANGLE", "Keep both elbows bent approximately 90 degrees."))
        if np.mean(data[:, 8] > 12) >= 0.2:
            errors.append(("TORSO_COMPENSATION", "Keep your torso upright during the movement."))
        twist = np.abs(data[:, 9] - np.median(data[:min(5, len(data)), 9]))
        if np.mean(twist > 0.3) >= 0.2:
            errors.append(("TORSO_TWIST", "Keep your chest facing the camera instead of twisting with the wand."))
        if data.shape[1] >= 14 and np.mean(np.any(data[:, 12:14] > 0.35, axis=1)) >= 0.2:
            errors.append(("UPPER_ARM_POSITION", "Keep your upper arms near your torso."))
        if data.shape[1] >= 12 and np.mean(np.abs(data[:, 10] - data[:, 11]) > 20) >= 0.2:
            errors.append(("HAND_COORDINATION", "Move both hands together and keep the wand level."))
        if errors:
            prediction, form, self.last_form = 1, "Incorrect", "INCORRECT"
        # Preserve the model prediction/probabilities separately from rules.
        self.last_prediction = prediction

        right = np.nan_to_num(data[:, 0])
        left = np.nan_to_num(data[:, 1])

        right_rom = float(
            np.max(right) - np.min(right)
        )
        left_rom = float(
            np.max(left) - np.min(left)
        )
        rom = float(
            (right_rom + left_rom) / 2.0
        )

        duration = float(
            max(0, len(self.rep_features) - 1) / self.fps
        )

        speed = float(
            rom / (duration + 1e-8)
        )

        feedback = (
            "Good shoulder rotation. Keep the movement "
            "smooth and controlled."
            if prediction == 0
            else
            "Incorrect shoulder rotation. Repeat the movement "
            "with controlled forearm rotation."
        )
        if errors:
            feedback = " ".join(message for _, message in errors)
        velocities = np.diff(data[:, :2], axis=0) * self.fps
        path_speed = float(np.mean(np.abs(velocities))) if len(velocities) else 0.0
        acceleration = np.diff(velocities, axis=0) * self.fps
        smoothness = float(1 / (1 + np.mean(np.abs(acceleration)) / 360)) if len(acceleration) else 0.0
        # Independent engineering form score: measured posture deviations.
        # It is neither classifier probability nor evaluated model accuracy.
        penalties = [np.mean(np.clip(np.max(np.abs(data[:, 4:6] - 90), axis=1) / 60, 0, 1)),
                     np.mean(np.clip(data[:, 8] / 24, 0, 1)),
                     np.mean(np.clip(twist / .6, 0, 1))]
        if data.shape[1] >= 14:
            penalties.extend([np.mean(np.clip(np.max(data[:, 12:14], axis=1) / .7, 0, 1)),
                              np.mean(np.clip(np.abs(data[:, 10] - data[:, 11]) / 40, 0, 1))])
        form_score = round(float(100 * (1 - np.mean(penalties))), 1)
        speed = path_speed

        error_frame_path = None
        if prediction == 1:
            error_frame_path = self._save_error_frame(frame)

        result = {
            "exercise": "shoulder_rotation",
            "rep_number": self.rep_count,
            "form": form,
            "confidence": round(confidence * 100.0, 1),
            "correct_probability": round(
                float(probabilities[0]) * 100.0,
                1,
            ),
            "incorrect_probability": round(
                float(probabilities[1]) * 100.0,
                1,
            ),
            "range_of_motion": round(rom, 1),
            "right_rom": round(right_rom, 1),
            "left_rom": round(left_rom, 1),
            "duration": round(duration, 2),
            "speed_deg_per_sec": round(speed, 1),
            "speed": f"{speed:.1f} deg/s",
            "score": form_score,
            "score_type": "observable_form_rules",
            "model_prediction": int(np.argmax(probabilities)),
            "form_errors": [code for code, _ in errors],
            "smoothness": round(smoothness, 3),
            "mean_speed_deg_per_sec": round(path_speed, 1),
            "rom_measurement": "camera_relative_forearm_azimuth_not_clinical_shoulder_rotation",
            "bilateral_rom_difference": round(abs(right_rom - left_rom), 1),
            "motion_control_acceleration": round(float(np.mean(np.abs(acceleration))) if len(acceleration) else 0, 1),
            "hand_range_engineering_units": np.ptp(data[:, 10:12], axis=0).tolist() if data.shape[1] >= 12 else None,
            "confidence_calibrated": False,
            "model_requires_retraining": getattr(self.model, "training_rep_definition", REP_DEFINITION) != REP_DEFINITION,
            "rep_definition": "centre -> one extreme -> centre -> opposite extreme",
            "feedback": feedback,
            "error_type": (
                errors[0][0] if errors else "GENERAL_FORM_ERROR"
                if prediction == 1
                else None
            ),
            "error_frame_path": error_frame_path,
            "rep_start_frame": max(
                1,
                self.frame_number - len(self.rep_features) + 1,
            ),
            "rep_end_frame": self.frame_number,
        }

        record = {
            "timestamp": datetime.now().astimezone().isoformat(),
            "exercise": "shoulder_rotation",
            "rep_number": self.rep_count,
            "session_id": self.session_id,
            "predicted_label": form.lower(),
            "confidence": confidence * 100.0,
            "correct_probability": float(probabilities[0]) * 100.0,
            "incorrect_probability": float(probabilities[1]) * 100.0,
            "range_of_motion": rom,
            "right_rom": right_rom,
            "left_rom": left_rom,
            "duration": duration,
            "speed_deg_per_sec": speed,
            "speed": f"{speed:.1f} deg/s",
            "score": form_score,
            "score_type": "observable_form_rules",
            "error_frame_path": error_frame_path,
            "ai_generated_review_required": True,
        }

        result["session_record"] = record

        if self.save_artifacts:
            path = (
                self.session_records_dir
                / f"shoulder_rotation_{self.session_id}_rep_{self.rep_count}.json"
            )

            with open(
                path,
                "w",
                encoding="utf-8",
            ) as file:
                json.dump(
                    record,
                    file,
                    indent=2,
                    default=str,
                )

            result["session_record_path"] = str(path)

        self.last_result = result
        self.current_feedback = feedback

        return result

    def reset_incomplete_rep(self):
        """Drop an interrupted movement while preserving completed counts and centre."""
        self.rep_features.clear()
        self.feature_frames.clear()
        self.smooth_signal.clear()
        self.previous_right = self.previous_left = None
        self._previous_timestamp = self._previous_observation = self._previous_sample = None
        self.cycle_detector.reset()
        self.current_direction = 0
        self.last_extreme_value = None

    def process_frame(self, frame, pose_landmarks, frame_number=None, timestamp_ms=None):
        if pose_landmarks is None:
            self.tracking_ok = False
            self.reset_incomplete_rep()
            self.current_feedback = "Move fully into the camera view."
            return None
        landmarks = getattr(pose_landmarks, "landmark", None)
        if landmarks is not None and (len(landmarks) < 25 or any(
                not all(np.isfinite(getattr(landmarks[i], key, np.nan)) for key in ["x", "y", "z", "visibility"])
                or landmarks[i].visibility < 0.5 for i in [11, 12, 13, 14, 15, 16, 23, 24])):
            self.tracking_ok = False
            self.reset_incomplete_rep()
            self.current_feedback = "Keep both arms and your torso visible."
            return None
        timestamp = None if timestamp_ms is None else float(timestamp_ms) / 1000
        if timestamp is not None:
            if not np.isfinite(timestamp):
                raise ValueError("Camera timestamp must be finite.")
            if self._previous_timestamp is not None:
                interval = timestamp - self._previous_timestamp
                if interval <= 0:
                    return None
                if interval > 0.5:
                    self.reset_incomplete_rep()
                else:
                    self.dt = interval
        feature = self._extract_feature(pose_landmarks)
        if not np.isfinite(feature).all():
            self.tracking_ok = False
            self.reset_incomplete_rep()
            self.current_feedback = "Face the camera and keep shoulders, elbows, hands and hips visible."
            return None
        self.tracking_ok = True
        self.dt = 1 / self.fps
        if timestamp is None:
            number = int(frame_number) if frame_number is not None else self.frame_number + 1
            return self._process_feature(frame, feature, number)
        # Resample observed motion onto the same 20 Hz grid used for training.
        # Large gaps and visibility failures reset the incomplete movement.
        if self._timestamp_origin is None:
            self._timestamp_origin = timestamp
        completed = None
        if self._previous_timestamp is None:
            self._next_sample = max(self._next_sample,
                int(np.ceil((timestamp - self._timestamp_origin) * self.fps - 1e-5)))
            feature[2:4] = 0
        while self._timestamp_origin + self._next_sample / self.fps <= timestamp + 1e-6:
            sample_time = self._timestamp_origin + self._next_sample / self.fps
            if self._previous_timestamp is None:
                sampled = feature.copy()
            else:
                fraction = (sample_time - self._previous_timestamp) / (timestamp - self._previous_timestamp)
                sampled = self._previous_observation + np.clip(fraction, 0, 1) * (feature - self._previous_observation)
            sampled[2:4] = (0 if self._previous_sample is None else
                (sampled[:2] - self._previous_sample[:2]) * self.fps)
            self._previous_sample = sampled.copy()
            result = self._process_feature(frame, sampled, self._next_sample + 1)
            if result is not None:
                completed = result
            self._next_sample += 1
        self._previous_timestamp, self._previous_observation = timestamp, feature.copy()
        return completed

    def _process_feature(self, frame, feature, frame_number):
        self.frame_number = frame_number
        self.live_right_angle, self.live_left_angle = map(float, feature[:2])
        self.live_torso_tilt, self.live_torso_rotation = map(float, feature[8:10])
        signal = float(np.mean(feature[:2]))
        self.live_rotation_signal = signal
        self.rep_features.append(feature.tolist())
        self.feature_frames.append(self.frame_number)
        self.smooth_signal.append(signal)
        self.smooth_signal = self.smooth_signal[-self.SMOOTH_WINDOW:]
        smoothed = float(np.mean(self.smooth_signal))
        # Smooth the observed hand signals only over this uninterrupted segment.
        recent = np.asarray(self.rep_features[-self.SMOOTH_WINDOW:])
        hands = tuple(np.mean(recent[:, 10:12], axis=0)) if recent.shape[1] >= 12 else tuple(np.mean(recent[:, :2], axis=0))
        bounds = self.cycle_detector.update(hands, self.frame_number)
        self.current_direction = self.cycle_detector.direction
        self.last_extreme_value = self.cycle_detector.extreme
        if bounds is not None:
            start, end = bounds
            selected = [i for i, n in enumerate(self.feature_frames) if start <= n <= end]
            if len(selected) >= MIN_REP_FRAMES:
                accumulated = self.rep_features
                self.rep_features = [accumulated[i] for i in selected]
                result = self._complete_rep(frame)
                result["rep_start_frame"], result["rep_end_frame"] = start, end
                # Keep the endpoint and the confirmation frames for the next cycle.
                retained = [i for i, n in enumerate(self.feature_frames) if n >= end]
                self.rep_features = [accumulated[i] for i in retained]
                self.feature_frames = [self.feature_frames[i] for i in retained]
                self.current_feedback = result["feedback"]
                return result
        # Bound storage even when no complete cycle is detected.
        self.rep_features = self.rep_features[-self.cycle_detector.max_frames:]
        self.feature_frames = self.feature_frames[-self.cycle_detector.max_frames:]
        self.current_feedback = (
            "Hold the stick at centre for calibration."
            if self.cycle_detector.centre is None else
            "Centre, one side, centre, then the opposite side. Return to centre after each count."
        )
        return None

    def get_live_state(self, pose_landmarks=None):
        landmarks = []

        if pose_landmarks is not None and self.tracking_ok:
            for landmark in pose_landmarks.landmark:
                landmarks.append(
                    {
                        "x": float(landmark.x),
                        "y": float(landmark.y),
                        "z": float(landmark.z),
                        "visibility": float(
                            landmark.visibility
                        ),
                    }
                )

        if not self.tracking_ok or self.last_prediction is None:
            form = "waiting"
        else:
            form = self.last_result.get(
                "form",
                "waiting",
            )

        return {
            "state": (
                "active"
                if self.last_extreme_value is not None
                else "waiting"
            ),
            "rep_count": int(self.rep_count),
            "form": form,
            "error_type": (
                self.last_result.get("error_type")
                if self.tracking_ok and self.last_prediction == 1
                else None
            ),
            "feedback": self.current_feedback,
            "score": self.last_result.get("score", 0.0),
            "confidence": (
                round(self.last_confidence * 100.0, 1)
            ),
            "range_of_motion": (
                self.last_result.get("range_of_motion", 0.0)
            ),
            "speed": self.last_result.get(
                "speed",
                "Waiting",
            ),
            "smoothness": self.last_result.get("smoothness", 0.0),
            "rep_definition": "centre -> one extreme -> centre -> opposite extreme",
            "tracking_ok": self.tracking_ok,
            "model_requires_retraining": getattr(self.model, "training_rep_definition", REP_DEFINITION) != REP_DEFINITION,
            "debug": {"rep_state": self.cycle_detector.state,
                      "centre": self.cycle_detector.centre,
                      "hand_centres": self.cycle_detector.hand_centres,
                      "centre_band": self.cycle_detector.return_band,
                      "calibration_band": self.cycle_detector.calibration_band,
                      "minimum_visibility": min((item["visibility"] for i, item in enumerate(landmarks)
                                                  if i in [11,12,13,14,15,16,23,24]), default=0),
                      "extreme_threshold": self.cycle_detector.excursion,
                      "hand_displacements": self.rep_features[-1][10:12] if self.rep_features else [],
                      "model_probabilities": self.last_probabilities},
            "confidence_calibrated": False,
            "right_rotation_angle": (
                self.live_right_angle
            ),
            "left_rotation_angle": (
                self.live_left_angle
            ),
            "rotation_signal": (
                self.live_rotation_signal
            ),
            "torso_tilt": (
                self.live_torso_tilt
            ),
            "torso_rotation": (
                self.live_torso_rotation
            ),
            "direction": int(
                self.current_direction
            ),
            "landmarks": landmarks,
        }

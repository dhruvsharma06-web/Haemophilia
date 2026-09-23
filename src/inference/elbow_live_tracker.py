"""Stable real-time elbow flexion/extension tracker."""

from collections import deque
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

from src.features.elbow_features import build_features
from src.inference.elbow_inference import ElbowInference
from src.pose.elbow_pose_extraction import extract_frame_landmarks

SEQUENCE_LENGTH = 128


# ============================================================
# TUNING
# ============================================================

ANGLE_EMA_ALPHA = 0.20
ANGLE_DEADZONE = 1.5

CALIBRATION_FRAMES = 45
MIN_CALIBRATION_ROM = 25.0

# A threshold must be crossed for several consecutive frames.
FLEX_CONFIRM_FRAMES = 4
EXTEND_CONFIRM_FRAMES = 4

# Prevent tiny/noisy movements from becoming repetitions.
MIN_REP_FRAMES = 15
MIN_REP_ROM = 30.0

# Prevent immediate duplicate repetitions.
REP_COOLDOWN = 15

PROB_SMOOTH = 10

# ============================================================


class LiveRepTracker:

    def __init__(self):
        self.angle_series = deque(maxlen=SEQUENCE_LENGTH)
        self.rows = deque(maxlen=SEQUENCE_LENGTH)
        self.sequence = deque(maxlen=SEQUENCE_LENGTH)

        # Angle smoothing
        self.ema_angle = None
        self.last_angle = None

        # Calibration
        self.calibration = []
        self.calibrated = False
        self.flexion = None
        self.extension = None

        # State machine
        self.state = "DOWN"

        self.flex_confirm_count = 0
        self.extend_confirm_count = 0

        self.rep_count = 0
        self.rep_frames = 0

        self.rep_angles = []
        self.rep_velocities = []

        self.cooldown = 0

        # Model
        self.prob_buffer = deque(maxlen=PROB_SMOOTH)
        self.last_prob = 0.5

        # Form
        self.form = "WAITING"
        self.form_locked = False
        self.frozen_form = "WAITING"

        # Last result
        self.last_rep_score = None
        self.last_rep_status = "WAITING"

    # ========================================================
    # ANGLE
    # ========================================================

    def smooth_angle(self, shoulder, elbow, wrist):

        a = np.asarray(shoulder, dtype=np.float32)
        b = np.asarray(elbow, dtype=np.float32)
        c = np.asarray(wrist, dtype=np.float32)

        ba = a - b
        bc = c - b

        denominator = (
            np.linalg.norm(ba) *
            np.linalg.norm(bc) +
            1e-6
        )

        cosine_angle = np.dot(ba, bc) / denominator

        cosine_angle = np.clip(
            cosine_angle,
            -1.0,
            1.0,
        )

        angle = float(
            np.degrees(
                np.arccos(cosine_angle)
            )
        )

        angle = float(
            np.clip(angle, 40.0, 170.0)
        )

        if self.ema_angle is None:
            self.ema_angle = angle
        else:
            self.ema_angle = (
                ANGLE_EMA_ALPHA * angle
                + (1.0 - ANGLE_EMA_ALPHA)
                * self.ema_angle
            )

        if (
            self.last_angle is not None
            and abs(self.ema_angle - self.last_angle)
            < ANGLE_DEADZONE
        ):
            return self.last_angle

        self.last_angle = self.ema_angle

        return self.last_angle

    # ========================================================
    # UPDATE
    # ========================================================

    def update(self, row, predictor=None):

        if row is None:
            return self.result()

        shoulder = _p(row, 12)
        elbow = _p(row, 14)
        wrist = _p(row, 16)

        angle = self.smooth_angle(
            shoulder,
            elbow,
            wrist,
        )

        self.angle_series.append(angle)
        self.rows.append(row)

        # ----------------------------------------------------
        # CALIBRATION
        # ----------------------------------------------------

        if not self.calibrated:

            self.calibration.append(angle)

            if len(self.calibration) >= CALIBRATION_FRAMES:

                mn = min(self.calibration)
                mx = max(self.calibration)

                calibration_rom = mx - mn

                if calibration_rom >= MIN_CALIBRATION_ROM:

                    self.flexion = (
                        mn
                        + 0.40 * calibration_rom
                    )

                    self.extension = (
                        mx
                        - 0.25 * calibration_rom
                    )

                    self.calibrated = True

                    print(
                        "Elbow calibration complete: "
                        f"min={mn:.1f}, "
                        f"max={mx:.1f}, "
                        f"flexion={self.flexion:.1f}, "
                        f"extension={self.extension:.1f}"
                    )

            return self.result()

        # ----------------------------------------------------
        # FEATURES
        # ----------------------------------------------------

        features, _ = build_features(
            list(self.rows),
            30,
            angle_series=np.asarray(
                self.angle_series,
                dtype=np.float32,
            ),
        )

        self.sequence.append(features[-1])

        velocity = float(features[-1][1])

        # ----------------------------------------------------
        # THRESHOLD CONFIRMATION
        # ----------------------------------------------------

        if angle < self.flexion:

            self.flex_confirm_count += 1
            self.extend_confirm_count = 0

        elif angle > self.extension:

            self.extend_confirm_count += 1
            self.flex_confirm_count = 0

        else:

            self.flex_confirm_count = 0
            self.extend_confirm_count = 0

        # ----------------------------------------------------
        # START FLEXION
        # ----------------------------------------------------

        if (
            self.state == "DOWN"
            and self.cooldown == 0
            and self.flex_confirm_count
            >= FLEX_CONFIRM_FRAMES
        ):

            self.state = "UP"

            self.rep_frames = 0
            self.rep_angles = []
            self.rep_velocities = []

            self.form_locked = False

        # ----------------------------------------------------
        # ACTIVE REP
        # ----------------------------------------------------

        if self.state == "UP":

            self.rep_frames += 1

            self.rep_angles.append(angle)

            self.rep_velocities.append(
                abs(velocity)
            )

        # ----------------------------------------------------
        # COMPLETE REP
        # ----------------------------------------------------

        if (
            self.state == "UP"
            and self.extend_confirm_count
            >= EXTEND_CONFIRM_FRAMES
            and self.rep_frames >= MIN_REP_FRAMES
        ):

            if self.rep_angles:

                rom = (
                    max(self.rep_angles)
                    - min(self.rep_angles)
                )

            else:
                rom = 0.0

            # Strong protection against random small cycles.
            if rom >= MIN_REP_ROM:

                self.rep_count += 1

                # --------------------------------------------
                # FORM
                # --------------------------------------------

                if rom >= 75:

                    self.form = "Correct"

                elif rom <= 55:

                    self.form = "Incorrect"

                else:

                    if self.last_prob > 0.55:
                        self.form = "Correct"
                    else:
                        self.form = "Incorrect"

                self.frozen_form = self.form
                self.form_locked = True

                # --------------------------------------------
                # SCORE
                # --------------------------------------------

                avg_velocity = (
                    float(
                        np.mean(
                            self.rep_velocities
                        )
                    )
                    if self.rep_velocities
                    else 0.0
                )

                score = self.score_rep(
                    rom,
                    avg_velocity,
                )

                self.last_rep_score = score

                if score > 80:
                    self.last_rep_status = "EXCELLENT"
                elif score > 55:
                    self.last_rep_status = "GOOD"
                else:
                    self.last_rep_status = "BAD"

                print(
                    f"ELBOW REP {self.rep_count}: "
                    f"ROM={rom:.1f}, "
                    f"FORM={self.form}, "
                    f"SCORE={score}"
                )

                self.cooldown = REP_COOLDOWN

            # Reset regardless of whether it was a valid rep.
            self.state = "DOWN"
            self.rep_frames = 0
            self.rep_angles = []
            self.rep_velocities = []

            self.flex_confirm_count = 0
            self.extend_confirm_count = 0

        # ----------------------------------------------------
        # COOLDOWN
        # ----------------------------------------------------

        if self.cooldown > 0:
            self.cooldown -= 1

        # ----------------------------------------------------
        # MODEL
        # ----------------------------------------------------

        if (
            predictor
            and len(self.sequence)
            == SEQUENCE_LENGTH
        ):

            _, prob = predictor.predict_probability(
                np.asarray(
                    self.sequence,
                    dtype=np.float32,
                )
            )

            self.prob_buffer.append(prob)

            self.last_prob = float(
                np.mean(self.prob_buffer)
            )

        # ----------------------------------------------------
        # FORM LOCK
        # ----------------------------------------------------

        if self.form_locked:
            self.form = self.frozen_form

        return self.result()

    # ========================================================
    # SCORE
    # ========================================================

    def score_rep(self, rom, velocity):

        score = 0

        if rom > 100:
            score += 60

        elif rom > 80:
            score += 45

        elif rom > 60:
            score += 25

        else:
            score += 10

        if velocity < 0.03:
            score += 30

        elif velocity < 0.06:
            score += 20

        else:
            score += 10

        return min(score, 100)

    # ========================================================
    # OUTPUT
    # ========================================================

    def result(self):

        return {
            "state": self.state,
            "reps": self.rep_count,
            "form": self.form,
            "prob": self.last_prob,
            "angle": (
                self.last_angle
                if self.last_angle is not None
                else 0
            ),
            "rep_score": self.last_rep_score,
            "rep_status": self.last_rep_status,
            "calibrated": self.calibrated,
            "flexion_threshold": self.flexion,
            "extension_threshold": self.extension,
        }


# ============================================================
# HELPERS
# ============================================================

def _p(row, i):

    return np.asarray(
        [
            row.get(
                f"landmark_{i}_x",
                0,
            ),
            row.get(
                f"landmark_{i}_y",
                0,
            ),
            row.get(
                f"landmark_{i}_z",
                0,
            ),
        ],
        dtype=np.float32,
    )


# ============================================================
# ORIGINAL LOCAL CAMERA DEMO
# ============================================================

def run_live_camera(model_path):

    predictor = ElbowInference(model_path)

    tracker = LiveRepTracker()

    cap = cv2.VideoCapture(0)

    mp_pose = mp.solutions.pose
    drawing = mp.solutions.drawing_utils

    with mp_pose.Pose(
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:

        while cap.isOpened():

            ret, frame = cap.read()

            if not ret:
                break

            row, res = extract_frame_landmarks(
                frame,
                pose,
            )

            if res.pose_landmarks:

                drawing.draw_landmarks(
                    frame,
                    res.pose_landmarks,
                    mp_pose.POSE_CONNECTIONS,
                )

            result = tracker.update(
                row,
                predictor,
            )

            _draw(
                frame,
                result,
            )

            cv2.imshow(
                "Elbow AI",
                frame,
            )

            if (
                cv2.waitKey(1) & 0xFF
                == ord("q")
            ):
                break

    cap.release()
    cv2.destroyAllWindows()


def _draw(frame, result):

    if result["form"] == "Correct":
        color = (0, 255, 0)

    elif result["form"] == "Incorrect":
        color = (0, 0, 255)

    else:
        color = (0, 255, 255)

    cv2.putText(
        frame,
        f"Reps: {result['reps']}",
        (20, 40),
        0,
        0.8,
        color,
        2,
    )

    cv2.putText(
        frame,
        f"Form: {result['form']}",
        (20, 70),
        0,
        0.7,
        color,
        2,
    )

    cv2.putText(
        frame,
        f"Angle: {result['angle']:.1f}",
        (20, 100),
        0,
        0.7,
        (255, 255, 255),
        2,
    )

    cv2.putText(
        frame,
        f"State: {result['state']}",
        (20, 130),
        0,
        0.7,
        (255, 255, 255),
        2,
    )

    if result["rep_status"] != "WAITING":

        cv2.putText(
            frame,
            f"{result['rep_status']} "
            f"({result['rep_score']})",
            (20, 200),
            0,
            0.8,
            (0, 255, 255),
            2,
        )


if __name__ == "__main__":

    run_live_camera(
        Path(__file__).resolve().parents[2]
        / "models"
        / "elbow_flexion_lstm.pth"
    )
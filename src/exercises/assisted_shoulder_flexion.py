"""Reusable assisted shoulder flexion assessment engine.

This module intentionally mirrors the working assessment logic in
``src/inference/live_camera.py``.  It owns no camera, OpenCV window, or
MediaPipe Pose instance: callers provide each BGR frame and its already
processed MediaPipe pose landmarks.
"""

import json
import os
from datetime import datetime
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
import torch

from src.models.lstm_model import ExerciseLSTM


MODEL_PATH = (
    Path(__file__).resolve().parents[2]
    / "models"
    / "assisted_shoulder_lstm.pth"
)

SEQUENCE_LENGTH = 128

START_ANGLE = 40.0
END_ANGLE = 55.0

REQUIRED_TOP_ANGLE = 150.0
MIN_ARM_TOP_ANGLE = 145.0

MAX_RELATIVE_TORSO_TILT = 8.0
MAX_ARM_ASYMMETRY = 18.0
MAX_WRIST_HEIGHT_DIFF = 0.18
MAX_ARM_TRAJECTORY = 0.70

ERROR_CONFIRM_FRAMES = 5
UPWARD_MOVEMENT_THRESHOLD = 0.25
MIN_REP_FRAMES = 20


mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils


def load_model(model_path=MODEL_PATH):
    """Load the exact 10-feature LSTM used by the live assessment."""

    device = torch.device(
        "cuda" if torch.cuda.is_available() else "cpu"
    )

    model = ExerciseLSTM(
        input_size=10,
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3,
    )

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


def calculate_angle(a, b, c):
    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    c = np.array(c, dtype=np.float32)

    ba = a - b
    bc = c - b

    denominator = (
        np.linalg.norm(ba)
        * np.linalg.norm(bc)
    )

    if denominator < 1e-8:
        return 0.0

    cosine_angle = np.clip(
        np.dot(ba, bc) / denominator,
        -1.0,
        1.0,
    )

    return float(
        np.degrees(
            np.arccos(cosine_angle)
        )
    )


def calculate_torso_features(landmarks):
    ls, rs = landmarks[11], landmarks[12]
    lh, rh = landmarks[23], landmarks[24]

    sx = (ls.x + rs.x) / 2.0
    sy = (ls.y + rs.y) / 2.0

    hx = (lh.x + rh.x) / 2.0
    hy = (lh.y + rh.y) / 2.0

    torso_tilt = np.degrees(
        np.arctan2(
            abs(sx - hx),
            abs(sy - hy) + 1e-8,
        )
    )

    shoulder_width = np.sqrt(
        (rs.x - ls.x) ** 2
        + (rs.y - ls.y) ** 2
        + 1e-8
    )

    torso_rotation = (
        rs.z - ls.z
    ) / (shoulder_width + 1e-8)

    return (
        float(torso_tilt),
        float(torso_rotation),
    )


def calculate_arm_trajectory(landmarks):
    ls, rs = landmarks[11], landmarks[12]
    le, re = landmarks[13], landmarks[14]
    lh, rh = landmarks[23], landmarks[24]

    sx = (ls.x + rs.x) / 2.0
    sy = (ls.y + rs.y) / 2.0

    hx = (lh.x + rh.x) / 2.0
    hy = (lh.y + rh.y) / 2.0

    torso_length = max(
        np.sqrt(
            (sx - hx) ** 2
            + (sy - hy) ** 2
        ),
        1e-6,
    )

    left_trajectory = (
        le.x - ls.x
    ) / torso_length

    right_trajectory = (
        re.x - rs.x
    ) / torso_length

    return (
        float(left_trajectory),
        float(right_trajectory),
    )


def get_rule_error(
    left_angle,
    right_angle,
    torso_tilt,
    baseline_torso_tilt,
    left_trajectory,
    right_trajectory,
    wrist_height_diff,
):
    relative_tilt = abs(
        torso_tilt
        - baseline_torso_tilt
    )

    if relative_tilt > MAX_RELATIVE_TORSO_TILT:
        return (
            "torso_tilt",
            "Incorrect: your body tilted during "
            "the repetition. Keep your torso upright.",
        )

    if abs(left_angle - right_angle) > MAX_ARM_ASYMMETRY:
        return (
            "arm_asymmetry",
            "Incorrect: both arms must move together. "
            "One arm is lagging or tilting.",
        )

    if wrist_height_diff > MAX_WRIST_HEIGHT_DIFF:
        return (
            "bar_tilt",
            "Incorrect: keep the bar level and "
            "raise both arms evenly.",
        )

    if (
        abs(left_trajectory) > MAX_ARM_TRAJECTORY
        or abs(right_trajectory) > MAX_ARM_TRAJECTORY
    ):
        return (
            "arm_path",
            "Incorrect: keep both arms on a straight, "
            "controlled path while raising the bar.",
        )

    return None, None


def get_advanced_error_type(error):
    error_type = error["type"]

    if error_type == "incomplete_arm":
        return (
            "LEFT_ARM_LOW"
            if error.get("bad_arm") == "left"
            else "RIGHT_ARM_LOW"
        )

    if error_type == "torso_tilt":
        return "BODY_TILT"

    if error_type in (
        "arm_asymmetry",
        "bar_tilt",
    ):
        return "ARM_ASYMMETRY"

    return "GENERAL_FORM_ERROR"


def get_error_label(error_type):
    return {
        "RIGHT_ARM_LOW": "RIGHT ARM TOO LOW",
        "LEFT_ARM_LOW": "LEFT ARM TOO LOW",
        "ARM_ASYMMETRY": "ARMS NOT SYMMETRIC",
        "BODY_TILT": "BODY TILT DETECTED",
        "GENERAL_FORM_ERROR": "GENERAL FORM ERROR",
    }[error_type]


def save_error_frame(
    frame,
    pose_landmarks,
    error_type,
    rep_number,
    frame_number,
    error_frames_dir,
):
    """Write the same red-skeleton, highlighted error artifact as the demo."""

    os.makedirs(
        error_frames_dir,
        exist_ok=True,
    )

    annotated_frame = frame.copy()

    red = (0, 0, 255)
    highlight = (0, 255, 255)

    mp_drawing.draw_landmarks(
        annotated_frame,
        pose_landmarks,
        mp_pose.POSE_CONNECTIONS,
        mp_drawing.DrawingSpec(
            color=red
        ),
        mp_drawing.DrawingSpec(
            color=red
        ),
    )

    regions = {
        "RIGHT_ARM_LOW": [
            [12, 14, 16]
        ],
        "LEFT_ARM_LOW": [
            [11, 13, 15]
        ],
        "ARM_ASYMMETRY": [
            [11, 13, 15],
            [12, 14, 16],
        ],
        "BODY_TILT": [
            [11, 12, 24, 23, 11]
        ],
        "GENERAL_FORM_ERROR": [
            [11, 13, 15],
            [12, 14, 16],
            [11, 12, 24, 23, 11],
        ],
    }

    height, width = annotated_frame.shape[:2]
    landmarks = pose_landmarks.landmark

    for region in regions[error_type]:

        points = [
            (
                int(landmarks[i].x * width),
                int(landmarks[i].y * height),
            )
            for i in region
        ]

        for start, end in zip(
            points,
            points[1:],
        ):
            cv2.line(
                annotated_frame,
                start,
                end,
                highlight,
                4,
            )

        for point in points:
            cv2.circle(
                annotated_frame,
                point,
                7,
                highlight,
                -1,
            )

    cv2.putText(
        annotated_frame,
        get_error_label(error_type),
        (30, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.9,
        red,
        3,
    )

    filename = (
        f"assisted_flexion_rep_"
        f"{rep_number:02d}_"
        f"{error_type}_"
        f"frame_{frame_number}.jpg"
    )

    path = os.path.join(
        error_frames_dir,
        filename,
    )

    cv2.imwrite(
        path,
        annotated_frame,
    )

    return path


def save_session_record(
    record,
    session_records_dir,
):
    os.makedirs(
        session_records_dir,
        exist_ok=True,
    )

    path = os.path.join(
        session_records_dir,
        f"assisted_flexion_rep_"
        f"{record['rep_number']:02d}.json",
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
        )

    return path


class AssistedShoulderFlexionAssessment:
    """Per-video/per-session state machine for the working assisted-flexion demo."""

    def __init__(
        self,
        model,
        device,
        fps=30.0,
        data_dir="data",
        save_artifacts=True,
    ):
        self.model = model
        self.device = device

        self.fps = (
            fps
            if fps > 0
            else 30.0
        )

        self.error_frames_dir = os.path.join(
            data_dir,
            "error_frames",
        )

        self.session_records_dir = os.path.join(
            data_dir,
            "session_records",
        )

        self.save_artifacts = save_artifacts

        self.last_result = {
            "form": "Waiting",
            "confidence": 0,
            "range_of_motion": 0,
            "duration": 0,
            "speed": "Waiting",
            "smoothness": 0,
            "score": 0,
            "feedback": "Perform a repetition.",
        }

        self.reset_session()

    @classmethod
    def from_model_path(
        cls,
        model_path=MODEL_PATH,
        **kwargs,
    ):
        model, device = load_model(
            model_path
        )

        return cls(
            model,
            device,
            **kwargs,
        )

    def reset_session(self):
        self.state = "DOWN"
        self.rep_count = 0
        self.frame_number = 0

        self.previous_angle = None

        self.rep_start_frame = None

        self.max_angle_so_far = 0.0

        self.height_reached = False

        self.down_torso_history = []

        self.baseline_torso_tilt = 0.0

        self.current_feedback = (
            "Get ready — raise your arm."
        )

        self._reset_rep_state()

    def _reset_rep_buffers(self):
        self.rep_angles_right = []
        self.rep_angles_left = []

        self.rep_visibility_right = []
        self.rep_visibility_left = []

        self.rep_torso_tilt = []
        self.rep_torso_rotation = []

        self.rep_left_trajectory = []
        self.rep_right_trajectory = []

        # Retained to keep parity with
        # the live demo's state layout.
        self.rep_error_frames = []
        self.rep_feedback_history = []

    def _reset_rep_state(self):
        self._reset_rep_buffers()

        self.active_error = None
        self.active_error_count = 0

        self.first_error = None

        self.error_frame_path = None
        self.error_frame_number = None

    def process_frame(
        self,
        frame,
        pose_landmarks,
        frame_number=None,
    ):
        """Process one BGR frame and its MediaPipe pose landmarks.

        Returns a completed-rep dictionary only on the frame
        that completes a valid-length rep; otherwise returns None.
        """

        self.frame_number = (
            self.frame_number + 1
            if frame_number is None
            else frame_number
        )

        if pose_landmarks is None:
            self.current_feedback = (
                "Move into the camera view."
            )

            self.previous_angle = None

            return None

        landmarks = pose_landmarks.landmark

        lh, ls, le = (
            landmarks[23],
            landmarks[11],
            landmarks[13],
        )

        rh, rs, re = (
            landmarks[24],
            landmarks[12],
            landmarks[14],
        )

        lw, rw = (
            landmarks[15],
            landmarks[16],
        )

        left_angle = calculate_angle(
            [lh.x, lh.y],
            [ls.x, ls.y],
            [le.x, le.y],
        )

        right_angle = calculate_angle(
            [rh.x, rh.y],
            [rs.x, rs.y],
            [re.x, re.y],
        )

        left_visibility = float(
            ls.visibility
        )

        right_visibility = float(
            rs.visibility
        )

        current_angle = (
            left_angle + right_angle
        ) / 2.0

        torso_tilt, torso_rotation = (
            calculate_torso_features(
                landmarks
            )
        )

        (
            left_trajectory,
            right_trajectory,
        ) = calculate_arm_trajectory(
            landmarks
        )

        shoulder_width = max(
            abs(rs.x - ls.x),
            1e-6,
        )

        wrist_height_diff = (
            abs(lw.y - rw.y)
            / shoulder_width
        )

        if (
            self.state == "DOWN"
            and current_angle < END_ANGLE
        ):
            self.down_torso_history.append(
                torso_tilt
            )

            if len(
                self.down_torso_history
            ) > 30:
                self.down_torso_history.pop(
                    0
                )

            if len(
                self.down_torso_history
            ) >= 8:
                self.baseline_torso_tilt = float(
                    np.median(
                        self.down_torso_history
                    )
                )

        angle_change = (
            current_angle
            - self.previous_angle
            if self.previous_angle is not None
            else 0.0
        )

        if (
            self.state == "DOWN"
            and current_angle > START_ANGLE
            and angle_change > UPWARD_MOVEMENT_THRESHOLD
        ):
            self.state = "RAISING"

            self.rep_start_frame = (
                self.frame_number
            )

            self._reset_rep_state()

            self.max_angle_so_far = (
                current_angle
            )

            self.height_reached = False

            self.current_feedback = (
                "Raise your arm higher."
            )

        if self.state in (
            "RAISING",
            "TOP",
            "LOWERING",
        ):
            self._collect_frame(
                frame,
                pose_landmarks,
                left_angle,
                right_angle,
                left_visibility,
                right_visibility,
                current_angle,
                torso_tilt,
                torso_rotation,
                left_trajectory,
                right_trajectory,
                wrist_height_diff,
                angle_change,
            )

        result = None

        if (
            self.state in (
                "RAISING",
                "TOP",
                "LOWERING",
            )
            and current_angle < END_ANGLE
            and self.rep_start_frame is not None
        ):
            result = self._complete_rep(
                frame,
                pose_landmarks,
            )

            self.state = "DOWN"

            self.rep_start_frame = None

            self.max_angle_so_far = 0.0

            self.height_reached = False

            self._reset_rep_state()

            self.current_feedback = (
                "Get ready — raise your arm."
            )

        self.previous_angle = current_angle

        return result

    def _collect_frame(
        self,
        frame,
        pose_landmarks,
        left_angle,
        right_angle,
        left_visibility,
        right_visibility,
        current_angle,
        torso_tilt,
        torso_rotation,
        left_trajectory,
        right_trajectory,
        wrist_height_diff,
        angle_change,
    ):
        self.rep_angles_right.append(
            right_angle
        )

        self.rep_angles_left.append(
            left_angle
        )

        self.rep_visibility_right.append(
            right_visibility
        )

        self.rep_visibility_left.append(
            left_visibility
        )

        self.rep_torso_tilt.append(
            torso_tilt
        )

        self.rep_torso_rotation.append(
            torso_rotation
        )

        self.rep_left_trajectory.append(
            left_trajectory
        )

        self.rep_right_trajectory.append(
            right_trajectory
        )

        self.max_angle_so_far = max(
            self.max_angle_so_far,
            current_angle,
        )

        (
            error_type,
            error_message,
        ) = get_rule_error(
            left_angle,
            right_angle,
            torso_tilt,
            self.baseline_torso_tilt,
            left_trajectory,
            right_trajectory,
            wrist_height_diff,
        )

        if error_type is not None:

            if self.active_error == error_type:
                self.active_error_count += 1

            else:
                self.active_error = error_type
                self.active_error_count = 1

            if (
                self.active_error_count
                >= ERROR_CONFIRM_FRAMES
                and self.first_error is None
            ):
                self.first_error = {
                    "type": error_type,
                    "frame": self.frame_number,
                    "feedback": error_message,
                    "angle": current_angle,
                    "torso_tilt": torso_tilt,
                    "relative_torso_tilt": abs(
                        torso_tilt
                        - self.baseline_torso_tilt
                    ),
                    "torso_rotation": torso_rotation,
                    "wrist_height_diff": wrist_height_diff,
                    "arm_asymmetry": abs(
                        left_angle
                        - right_angle
                    ),
                }

                if self.save_artifacts:

                    self.error_frame_path = (
                        save_error_frame(
                            frame,
                            pose_landmarks,
                            get_advanced_error_type(
                                self.first_error
                            ),
                            self.rep_count + 1,
                            self.frame_number,
                            self.error_frames_dir,
                        )
                    )

                    self.error_frame_number = (
                        self.frame_number
                    )

        else:
            self.active_error = None
            self.active_error_count = 0

        if self.state == "RAISING":

            if self.first_error is not None:
                self.current_feedback = (
                    self.first_error[
                        "feedback"
                    ]
                )

            elif current_angle < 80:
                self.current_feedback = (
                    "Raise your arm higher."
                )

            elif current_angle < 100:
                self.current_feedback = (
                    "Good, keep raising your arm higher."
                )

            elif current_angle < REQUIRED_TOP_ANGLE:
                self.current_feedback = (
                    "Almost there — raise your arm "
                    "a little higher."
                )

            else:
                self.height_reached = True
                self.state = "TOP"

                self.current_feedback = (
                    "Good height — now lower your arm slowly."
                )

        elif self.state == "TOP":

            if self.first_error is not None:
                self.current_feedback = (
                    self.first_error[
                        "feedback"
                    ]
                )

            else:
                self.current_feedback = (
                    "Good height — now lower your arm slowly."
                )

            if angle_change < -0.35:
                self.state = "LOWERING"

        elif self.state == "LOWERING":

            self.current_feedback = (
                self.first_error["feedback"]
                if self.first_error is not None
                else "Lower your arm slowly."
            )

    def _make_sequence(
        self,
        right_array,
        left_array,
    ):
        visibility_right = np.array(
            self.rep_visibility_right,
            dtype=np.float32,
        )

        visibility_left = np.array(
            self.rep_visibility_left,
            dtype=np.float32,
        )

        torso_tilt_array = np.array(
            self.rep_torso_tilt,
            dtype=np.float32,
        )

        torso_rotation_array = np.array(
            self.rep_torso_rotation,
            dtype=np.float32,
        )

        left_trajectory_array = np.array(
            self.rep_left_trajectory,
            dtype=np.float32,
        )

        right_trajectory_array = np.array(
            self.rep_right_trajectory,
            dtype=np.float32,
        )

        velocity_right, velocity_left = (
            np.gradient(right_array),
            np.gradient(left_array),
        )

        old_x = np.linspace(
            0,
            1,
            len(right_array),
        )

        new_x = np.linspace(
            0,
            1,
            SEQUENCE_LENGTH,
        )

        interp = lambda array: np.interp(
            new_x,
            old_x,
            array,
        )

        right_angle_seq = interp(
            right_array
        )

        left_angle_seq = interp(
            left_array
        )

        right_velocity_seq = interp(
            velocity_right
        )

        left_velocity_seq = interp(
            velocity_left
        )

        right_visibility_seq = interp(
            visibility_right
        )

        left_visibility_seq = interp(
            visibility_left
        )

        torso_tilt_seq = interp(
            torso_tilt_array
        )

        torso_rotation_seq = interp(
            torso_rotation_array
        )

        left_trajectory_seq = interp(
            left_trajectory_array
        )

        right_trajectory_seq = interp(
            right_trajectory_array
        )

        right_angle_seq /= 180.0
        left_angle_seq /= 180.0

        right_velocity_seq /= 10.0
        left_velocity_seq /= 10.0

        torso_tilt_seq /= 90.0

        return np.nan_to_num(
            np.stack(
                [
                    right_angle_seq,
                    left_angle_seq,
                    right_velocity_seq,
                    left_velocity_seq,
                    right_visibility_seq,
                    left_visibility_seq,
                    torso_tilt_seq,
                    torso_rotation_seq,
                    left_trajectory_seq,
                    right_trajectory_seq,
                ],
                axis=1,
            ),
            nan=0.0,
            posinf=0.0,
            neginf=0.0,
        )

    def _complete_rep(
        self,
        frame,
        pose_landmarks,
    ):
        end_frame = self.frame_number

        duration = (
            end_frame
            - self.rep_start_frame
        ) / self.fps

        if len(
            self.rep_angles_right
        ) < MIN_REP_FRAMES:
            return None

        self.rep_count += 1

        right_array = np.array(
            self.rep_angles_right,
            dtype=np.float32,
        )

        left_array = np.array(
            self.rep_angles_left,
            dtype=np.float32,
        )

        range_of_motion = (
            max(right_array)
            - min(right_array)
            + max(left_array)
            - min(left_array)
        ) / 2.0

        if len(right_array) >= 3:

            second_diff = np.concatenate(
                [
                    np.diff(
                        right_array,
                        n=2,
                    ),
                    np.diff(
                        left_array,
                        n=2,
                    ),
                ]
            )

            smoothness_raw = (
                1.0
                / (
                    1.0
                    + np.mean(
                        np.abs(
                            second_diff
                        )
                    )
                )
            )

        else:
            smoothness_raw = 0.0

        sequence = self._make_sequence(
            right_array,
            left_array,
        )

        sequence_tensor = (
            torch.tensor(
                sequence,
                dtype=torch.float32,
            )
            .unsqueeze(0)
            .to(self.device)
        )

        with torch.no_grad():

            probabilities = torch.softmax(
                self.model(
                    sequence_tensor
                ),
                dim=1,
            )

            predicted_class = (
                torch.argmax(
                    probabilities,
                    dim=1,
                ).item()
            )

            confidence = (
                probabilities[0][
                    predicted_class
                ].item()
                * 100.0
            )

        prediction = (
            "correct"
            if predicted_class == 0
            else "incorrect"
        )

        left_max_angle = (
            float(
                np.max(left_array)
            )
            if len(left_array)
            else 0.0
        )

        right_max_angle = (
            float(
                np.max(right_array)
            )
            if len(right_array)
            else 0.0
        )

        weaker_arm_max = min(
            left_max_angle,
            right_max_angle,
        )

        torso_values = np.array(
            self.rep_torso_tilt,
            dtype=np.float32,
        )

        robust_relative_tilt = (
            float(
                np.percentile(
                    np.abs(
                        torso_values
                        - self.baseline_torso_tilt
                    ),
                    90,
                )
            )
            if len(torso_values)
            else 0.0
        )

        left_arr = np.array(
            self.rep_angles_left,
            dtype=np.float32,
        )

        right_arr = np.array(
            self.rep_angles_right,
            dtype=np.float32,
        )

        n = min(
            len(left_arr),
            len(right_arr),
        )

        peak_asymmetry = (
            float(
                np.percentile(
                    np.abs(
                        left_arr[
                            max(
                                0,
                                int(n * 0.60),
                            ):
                        ]
                        - right_arr[
                            max(
                                0,
                                int(n * 0.60),
                            ):
                        ]
                    ),
                    80,
                )
            )
            if n
            else 0.0
        )

        final_error = self.first_error

        if weaker_arm_max < MIN_ARM_TOP_ANGLE:

            final_error = (
                self._incomplete_arm_error(
                    left_max_angle,
                    right_max_angle,
                    end_frame,
                    "did not go fully overhead. "
                    "Raise both arms completely above your head.",
                )
            )

        elif weaker_arm_max < REQUIRED_TOP_ANGLE:

            final_error = (
                self._incomplete_arm_error(
                    left_max_angle,
                    right_max_angle,
                    end_frame,
                    "stopped short. Both arms must "
                    "reach the full overhead position.",
                )
            )

        elif (
            robust_relative_tilt
            > MAX_RELATIVE_TORSO_TILT
        ):

            final_error = {
                "type": "torso_tilt",
                "frame": end_frame,
                "feedback": (
                    "Incorrect: your body tilted "
                    "during the repetition. Keep "
                    "your torso upright throughout "
                    "the movement."
                ),
            }

        elif (
            peak_asymmetry
            > MAX_ARM_ASYMMETRY
        ):

            final_error = {
                "type": "arm_asymmetry",
                "frame": end_frame,
                "feedback": (
                    "Incorrect: one arm did not "
                    "stay level with the other. "
                    "Raise both arms together "
                    "without tilting the bar."
                ),
            }

        advanced_error_type = (
            get_advanced_error_type(
                final_error
            )
            if final_error is not None
            else None
        )

        if (
            final_error is not None
            and self.error_frame_path is None
            and self.save_artifacts
        ):

            self.error_frame_path = (
                save_error_frame(
                    frame,
                    pose_landmarks,
                    advanced_error_type,
                    self.rep_count,
                    self.frame_number,
                    self.error_frames_dir,
                )
            )

            self.error_frame_number = (
                self.frame_number
            )

        form = (
            "Incorrect"
            if final_error is not None
            else "Correct"
        )

        if weaker_arm_max >= 165.0:
            rom_score = 95.0

        elif weaker_arm_max >= 150.0:
            rom_score = (
                82.0
                + (
                    weaker_arm_max
                    - 150.0
                )
                / 15.0
                * 13.0
            )

        elif weaker_arm_max >= 140.0:
            rom_score = (
                68.0
                + (
                    weaker_arm_max
                    - 140.0
                )
                / 10.0
                * 14.0
            )

        else:
            rom_score = max(
                0.0,
                weaker_arm_max
                / 140.0
                * 68.0,
            )

        speed_score = (
            92.0
            if 1.5 <= duration <= 2.7
            else 84.0
            if (
                1.2 <= duration < 1.5
                or 2.7 < duration <= 3.2
            )
            else 72.0
        )

        smoothness_score = float(
            np.clip(
                72.0
                + smoothness_raw * 20.0,
                72.0,
                92.0,
            )
        )

        form_score = max(
            50.0,
            95.0
            - min(
                18.0,
                robust_relative_tilt * 1.5,
            )
            - min(
                18.0,
                peak_asymmetry * 0.7,
            ),
        )

        score = float(
            np.clip(
                rom_score * 0.50
                + speed_score * 0.15
                + smoothness_score * 0.10
                + form_score * 0.25,
                0.0,
                100.0,
            )
        )

        if final_error is not None:
            score = min(
                score,
                59.0,
            )

        if final_error is not None:
            feedback = final_error[
                "feedback"
            ]

        elif score >= 90.0:
            feedback = (
                "Excellent movement. Both arms "
                "reached the range with good control."
            )

        elif score >= 80.0:
            feedback = (
                "Good movement. Keep both arms "
                "even and your torso upright."
            )

        elif score >= 70.0:
            feedback = (
                "Good repetition. Try to make "
                "the movement smoother and more "
                "controlled."
            )

        else:
            feedback = (
                "Movement completed. Improve "
                "your range and control next time."
            )

        self.last_result = {
            "form": form,
            "confidence": confidence,
            "range_of_motion": range_of_motion,
            "duration": duration,
            "speed": (
                "Fast"
                if duration < 1.2
                else "Good"
                if duration <= 2.7
                else "Slow"
            ),
            "smoothness": (
                smoothness_raw * 100.0
            ),
            "score": round(
                score,
                1,
            ),
            "feedback": feedback,
            "error_type": advanced_error_type,
            "error_frame_path": (
                self.error_frame_path
            ),
        }

        record = {
            "timestamp": (
                datetime.now()
                .astimezone()
                .isoformat()
            ),
            "exercise": (
                "assisted_shoulder_flexion"
            ),
            "rep_number": self.rep_count,
            "predicted_label": prediction,
            "score": self.last_result[
                "score"
            ],
            "error_type": advanced_error_type,
            "error_frame_path": (
                self.error_frame_path
            ),
            "frame_number": (
                self.error_frame_number
            ),
            "relevant_measurements": {
                "left_max_angle": float(
                    left_max_angle
                ),
                "right_max_angle": float(
                    right_max_angle
                ),
                "weaker_arm_max": float(
                    weaker_arm_max
                ),
                "relative_torso_tilt": float(
                    robust_relative_tilt
                ),
                "peak_arm_asymmetry": float(
                    peak_asymmetry
                ),
                "duration": float(
                    duration
                ),
                "range_of_motion": float(
                    range_of_motion
                ),
                "smoothness": float(
                    smoothness_raw * 100.0
                ),
            },
            "ai_generated_review_required": True,
        }

        if self.save_artifacts:

            self.last_result[
                "session_record_path"
            ] = save_session_record(
                record,
                self.session_records_dir,
            )

        self.last_result[
            "session_record"
        ] = record

        return self.last_result

    @staticmethod
    def _incomplete_arm_error(
        left_max_angle,
        right_max_angle,
        end_frame,
        message,
    ):
        bad_arm = (
            "left"
            if left_max_angle < right_max_angle
            else "right"
        )

        return {
            "type": "incomplete_arm",
            "frame": end_frame,
            "bad_arm": bad_arm,
            "feedback": (
                f"Incorrect: your {bad_arm} arm "
                f"{message}"
            ),
        }

    # ============================================================
    # LIVE CAMERA API
    # ============================================================

    def get_live_state(
        self,
        pose_landmarks=None,
    ):
        """
        Return the current assessment state for a live client.

        This method does not perform pose detection itself.
        The caller supplies the already processed MediaPipe
        pose landmarks.

        The returned dictionary is JSON serializable and is
        intended for the FastAPI WebSocket endpoint.
        """

        landmarks_output = []

        # --------------------------------------------------------
        # MediaPipe 33-landmark skeleton
        # --------------------------------------------------------
        if pose_landmarks is not None:

            for landmark in pose_landmarks.landmark:

                landmarks_output.append(
                    {
                        "x": float(
                            landmark.x
                        ),
                        "y": float(
                            landmark.y
                        ),
                        "z": float(
                            landmark.z
                        ),
                        "visibility": float(
                            landmark.visibility
                        ),
                    }
                )

        # --------------------------------------------------------
        # Current form and metrics
        # --------------------------------------------------------
        if self.state == "DOWN":

            if self.rep_count > 0:

                form = str(
                    self.last_result.get(
                        "form",
                        "Waiting",
                    )
                ).lower()

                feedback = self.last_result.get(
                    "feedback",
                    "Get ready — raise your arm.",
                )

                score = self.last_result.get(
                    "score",
                    0,
                )

                rom = self.last_result.get(
                    "range_of_motion",
                    0,
                )

                speed = self.last_result.get(
                    "speed",
                    "Waiting",
                )

                smoothness = self.last_result.get(
                    "smoothness",
                    0,
                )

            else:

                form = "waiting"

                feedback = (
                    "Get ready — raise your arm."
                )

                score = 0
                rom = 0
                speed = "Waiting"
                smoothness = 0

        else:

            # An error has been confirmed during
            # the current repetition.
            if self.first_error is not None:
                form = "incorrect"
            else:
                form = "correct"

            feedback = (
                self.current_feedback
            )

            score = self.last_result.get(
                "score",
                0,
            )

            # Live maximum angle.
            if self.max_angle_so_far > 0:

                rom = float(
                    self.max_angle_so_far
                )

            else:

                rom = self.last_result.get(
                    "range_of_motion",
                    0,
                )

            # ----------------------------------------------------
            # Live speed
            # ----------------------------------------------------
            if self.rep_start_frame is not None:

                elapsed = (
                    self.frame_number
                    - self.rep_start_frame
                ) / self.fps

                if elapsed < 1.2:
                    speed = "Fast"

                elif elapsed <= 2.7:
                    speed = "Good"

                else:
                    speed = "Slow"

            else:
                speed = "Waiting"

            # ----------------------------------------------------
            # Live smoothness
            # ----------------------------------------------------
            if len(
                self.rep_angles_right
            ) >= 3:

                right = np.array(
                    self.rep_angles_right,
                    dtype=np.float32,
                )

                left = np.array(
                    self.rep_angles_left,
                    dtype=np.float32,
                )

                second_diff = np.concatenate(
                    [
                        np.diff(
                            right,
                            n=2,
                        ),
                        np.diff(
                            left,
                            n=2,
                        ),
                    ]
                )

                if len(second_diff) > 0:

                    smoothness = (
                        1.0
                        / (
                            1.0
                            + np.mean(
                                np.abs(
                                    second_diff
                                )
                            )
                        )
                    ) * 100.0

                else:
                    smoothness = 0.0

            else:
                smoothness = 0.0

        # --------------------------------------------------------
        # Advanced error type
        # --------------------------------------------------------
        error_type = None

        if self.first_error is not None:

            error_type = (
                get_advanced_error_type(
                    self.first_error
                )
            )

        # --------------------------------------------------------
        # JSON response
        # --------------------------------------------------------
        return {
            "state": self.state,

            "rep_count": int(
                self.rep_count
            ),

            "form": form,

            "error_type": error_type,

            "feedback": feedback,

            "score": (
                float(score)
                if score is not None
                else None
            ),

            "range_of_motion": (
                float(rom)
                if rom is not None
                else None
            ),

            "speed": speed,

            "smoothness": float(
                smoothness
            ),

            "landmarks": landmarks_output,
        }
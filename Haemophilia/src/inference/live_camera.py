import cv2
import mediapipe as mp
import numpy as np
import torch
import sys
import os

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from models.lstm_model import ExerciseLSTM
from feedback.score_feedback import analyze_rep


# ============================================================
# SETTINGS
# ============================================================

MODEL_PATH = "models/assisted_shoulder_lstm.pth"
SEQUENCE_LENGTH = 128

START_ANGLE = 40.0
REQUIRED_TOP_ANGLE = 110.0

# Tolerant form rules. These are used mainly for feedback, not
# automatic rejection. Camera pose estimation is noisy, so avoid
# failing a rep for small posture/asymmetry variations.
MAX_TORSO_TILT = 25.0
MAX_ARM_ASYMMETRY = 45.0
MAX_ARM_TRAJECTORY = 0.85

# Keep the quality threshold forgiving. Height is the main hard check.
MIN_ACCEPTABLE_SCORE = 50.0

# Require a violation for several consecutive frames before showing
# posture feedback.
ERROR_CONFIRM_FRAMES = 8

UPWARD_MOVEMENT_THRESHOLD = 0.25
MIN_REP_FRAMES = 20

# ============================================================
# DEVICE
# ============================================================

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print("Device:", device)

if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))


# ============================================================
# MODEL
# ============================================================

model = ExerciseLSTM(
    input_size=10,
    hidden_size=64,
    num_layers=2,
    num_classes=2,
    dropout=0.3
)

model.load_state_dict(
    torch.load(
        MODEL_PATH,
        map_location=device,
        weights_only=True
    )
)

model.to(device)
model.eval()

print("Model loaded successfully.")


# ============================================================
# MEDIAPIPE
# ============================================================

mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils

pose = mp_pose.Pose(
    static_image_mode=False,
    model_complexity=1,
    smooth_landmarks=True,
    enable_segmentation=False,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)


# ============================================================
# HELPERS
# ============================================================

def calculate_angle(a, b, c):
    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    c = np.array(c, dtype=np.float32)

    ba = a - b
    bc = c - b

    denominator = np.linalg.norm(ba) * np.linalg.norm(bc)

    if denominator < 1e-8:
        return 0.0

    cosine_angle = np.dot(ba, bc) / denominator
    cosine_angle = np.clip(cosine_angle, -1.0, 1.0)

    return float(np.degrees(np.arccos(cosine_angle)))


def calculate_torso_features(landmarks):
    ls, rs = landmarks[11], landmarks[12]
    lh, rh = landmarks[23], landmarks[24]

    sx = (ls.x + rs.x) / 2.0
    sy = (ls.y + rs.y) / 2.0

    hx = (lh.x + rh.x) / 2.0
    hy = (lh.y + rh.y) / 2.0

    torso_dx = sx - hx
    torso_dy = sy - hy

    torso_tilt = np.degrees(
        np.arctan2(abs(torso_dx), abs(torso_dy) + 1e-8)
    )

    shoulder_width = np.sqrt(
        (rs.x - ls.x) ** 2 +
        (rs.y - ls.y) ** 2 +
        1e-8
    )

    torso_rotation = (rs.z - ls.z) / (shoulder_width + 1e-8)

    return float(torso_tilt), float(torso_rotation)


def calculate_arm_trajectory(landmarks):
    ls, rs = landmarks[11], landmarks[12]
    le, re = landmarks[13], landmarks[14]
    lh, rh = landmarks[23], landmarks[24]

    sx = (ls.x + rs.x) / 2.0
    sy = (ls.y + rs.y) / 2.0
    hx = (lh.x + rh.x) / 2.0
    hy = (lh.y + rh.y) / 2.0

    torso_length = np.sqrt(
        (sx - hx) ** 2 +
        (sy - hy) ** 2
    )
    torso_length = max(torso_length, 1e-6)

    left_traj = (le.x - ls.x) / torso_length
    right_traj = (re.x - rs.x) / torso_length

    return float(left_traj), float(right_traj)


def get_rule_error(
    left_angle,
    right_angle,
    torso_tilt,
    torso_rotation,
    left_trajectory,
    right_trajectory,
    max_angle
):
    """Return a *soft* form warning. Do not use this to reject a rep
    unless the movement is clearly outside the basic exercise range.
    """

    if torso_tilt > MAX_TORSO_TILT:
        return (
            "torso_tilt",
            "Try to keep your body more upright."
        )

    asymmetry = abs(left_angle - right_angle)
    if asymmetry > MAX_ARM_ASYMMETRY:
        return (
            "arm_asymmetry",
            "Try to keep both arms moving more evenly."
        )

    if abs(left_trajectory) > MAX_ARM_TRAJECTORY:
        return (
            "left_arm_trajectory",
            "Try to keep your left arm on a smoother path."
        )

    if abs(right_trajectory) > MAX_ARM_TRAJECTORY:
        return (
            "right_arm_trajectory",
            "Try to keep your right arm on a smoother path."
        )

    return None, None

def reset_rep_buffers():
    return (
        [], [], [], [], [], [], [], [], [], []
    )


# ============================================================
# CAMERA
# ============================================================

cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

fps = cap.get(cv2.CAP_PROP_FPS)
if fps <= 0:
    fps = 30.0

print("Camera FPS:", fps)


# ============================================================
# STATE
# ============================================================

state = "DOWN"
rep_count = 0
frame_number = 0

rep_start_frame = None

(
    rep_angles_right,
    rep_angles_left,
    rep_visibility_right,
    rep_visibility_left,
    rep_torso_tilt,
    rep_torso_rotation,
    rep_left_trajectory,
    rep_right_trajectory,
    rep_error_frames
) = reset_rep_buffers()

previous_angle = None
max_angle_so_far = 0.0
height_reached = False

current_feedback = "Get ready — raise your arm."

# Error tracking
active_error = None
active_error_count = 0
first_error = None

last_result = {
    "form": "Waiting",
    "confidence": 0,
    "range_of_motion": 0,
    "duration": 0,
    "speed": "Waiting",
    "smoothness": 0,
    "score": 0,
    "feedback": "Perform a repetition."
}


# ============================================================
# MAIN LOOP
# ============================================================

while cap.isOpened():

    ret, frame = cap.read()

    if not ret:
        print("Could not read camera frame.")
        break

    frame_number += 1

    # IMPORTANT: no flip.
    # MediaPipe detects and draws on the exact same frame.
    display_frame = frame.copy()

    rgb = cv2.cvtColor(display_frame, cv2.COLOR_BGR2RGB)
    rgb.flags.writeable = False
    results = pose.process(rgb)
    rgb.flags.writeable = True

    right_angle = 0.0
    left_angle = 0.0
    torso_tilt = 0.0
    torso_rotation = 0.0
    left_trajectory = 0.0
    right_trajectory = 0.0

    if results.pose_landmarks:

        landmarks = results.pose_landmarks.landmark

        # ----------------------------------------------------
        # LANDMARKS
        # ----------------------------------------------------

        lh, ls, le = landmarks[23], landmarks[11], landmarks[13]
        rh, rs, re = landmarks[24], landmarks[12], landmarks[14]

        left_angle = calculate_angle(
            [lh.x, lh.y],
            [ls.x, ls.y],
            [le.x, le.y]
        )

        right_angle = calculate_angle(
            [rh.x, rh.y],
            [rs.x, rs.y],
            [re.x, re.y]
        )

        left_visibility = float(ls.visibility)
        right_visibility = float(rs.visibility)

        current_angle = (left_angle + right_angle) / 2.0

        torso_tilt, torso_rotation = calculate_torso_features(landmarks)
        left_trajectory, right_trajectory = calculate_arm_trajectory(landmarks)

        angle_change = (
            current_angle - previous_angle
            if previous_angle is not None
            else 0.0
        )

        # ====================================================
        # START REP
        # ====================================================

        if (
            state == "DOWN"
            and current_angle > START_ANGLE
            and angle_change > UPWARD_MOVEMENT_THRESHOLD
        ):
            state = "RAISING"
            rep_start_frame = frame_number

            (
                rep_angles_right,
                rep_angles_left,
                rep_visibility_right,
                rep_visibility_left,
                rep_torso_tilt,
                rep_torso_rotation,
                rep_left_trajectory,
                rep_right_trajectory,
                rep_error_frames
            ) = reset_rep_buffers()

            max_angle_so_far = current_angle
            height_reached = False

            active_error = None
            active_error_count = 0
            first_error = None

            current_feedback = "Raise your arm higher."

        # ====================================================
        # COLLECT REP
        # ====================================================

        if state in ("RAISING", "TOP", "LOWERING"):

            rep_angles_right.append(right_angle)
            rep_angles_left.append(left_angle)

            rep_visibility_right.append(right_visibility)
            rep_visibility_left.append(left_visibility)

            rep_torso_tilt.append(torso_tilt)
            rep_torso_rotation.append(torso_rotation)

            rep_left_trajectory.append(left_trajectory)
            rep_right_trajectory.append(right_trajectory)

            max_angle_so_far = max(max_angle_so_far, current_angle)

            # ------------------------------------------------
            # HARD FORM ERROR DETECTION
            # ------------------------------------------------

            error_type, error_message = get_rule_error(
                left_angle,
                right_angle,
                torso_tilt,
                torso_rotation,
                left_trajectory,
                right_trajectory,
                max_angle_so_far
            )

            if error_type is not None:

                if active_error == error_type:
                    active_error_count += 1
                else:
                    active_error = error_type
                    active_error_count = 1

                # Confirm error only after consecutive frames.
                if active_error_count >= ERROR_CONFIRM_FRAMES:

                    if first_error is None:

                        first_error = {
                            "type": error_type,
                            "frame": frame_number,
                            "feedback": error_message,
                            "angle": current_angle,
                            "torso_tilt": torso_tilt,
                            "torso_rotation": torso_rotation,
                            "arm_asymmetry": abs(
                                left_angle - right_angle
                            )
                        }

                    current_feedback = error_message

            else:

                active_error = None
                active_error_count = 0

            # =================================================
            # RAISING FEEDBACK
            # =================================================

            if state == "RAISING":

                if first_error is not None:
                    current_feedback = first_error["feedback"]

                elif current_angle < 80:
                    current_feedback = "Raise your arm higher."

                elif current_angle < 100:
                    current_feedback = (
                        "Good, keep raising your arm higher."
                    )

                elif current_angle < REQUIRED_TOP_ANGLE:
                    current_feedback = (
                        "Almost there — raise your arm a little higher."
                    )

                else:
                    height_reached = True
                    state = "TOP"
                    current_feedback = (
                        "Good height — now lower your arm slowly."
                    )

            # =================================================
            # TOP
            # =================================================

            elif state == "TOP":

                if first_error is not None:
                    current_feedback = first_error["feedback"]
                else:
                    current_feedback = (
                        "Good height — now lower your arm slowly."
                    )

                if angle_change < -0.35:
                    state = "LOWERING"

            # =================================================
            # LOWERING
            # =================================================

            elif state == "LOWERING":

                if first_error is not None:
                    current_feedback = first_error["feedback"]
                else:
                    current_feedback = "Lower your arm slowly."

        # ====================================================
        # REP COMPLETE
        # ====================================================

        if (
            state in ("RAISING", "TOP", "LOWERING")
            and current_angle < START_ANGLE
            and rep_start_frame is not None
        ):

            end_frame = frame_number

            duration = (
                end_frame - rep_start_frame
            ) / fps

            if len(rep_angles_right) >= MIN_REP_FRAMES:

                rep_count += 1

                right_array = np.array(
                    rep_angles_right,
                    dtype=np.float32
                )

                left_array = np.array(
                    rep_angles_left,
                    dtype=np.float32
                )

                range_of_motion = (
                    max(right_array) - min(right_array)
                    +
                    max(left_array) - min(left_array)
                ) / 2.0

                # Smoothness
                if len(right_array) >= 3:

                    second_diff = np.concatenate(
                        [
                            np.diff(right_array, n=2),
                            np.diff(left_array, n=2)
                        ]
                    )

                    smoothness_raw = 1.0 / (
                        1.0 +
                        np.mean(np.abs(second_diff))
                    )

                else:
                    smoothness_raw = 0.0

                # ------------------------------------------------
                # 10-FEATURE LSTM SEQUENCE
                # ------------------------------------------------

                visibility_right = np.array(
                    rep_visibility_right,
                    dtype=np.float32
                )

                visibility_left = np.array(
                    rep_visibility_left,
                    dtype=np.float32
                )

                torso_tilt_array = np.array(
                    rep_torso_tilt,
                    dtype=np.float32
                )

                torso_rotation_array = np.array(
                    rep_torso_rotation,
                    dtype=np.float32
                )

                left_trajectory_array = np.array(
                    rep_left_trajectory,
                    dtype=np.float32
                )

                right_trajectory_array = np.array(
                    rep_right_trajectory,
                    dtype=np.float32
                )

                velocity_right = np.gradient(right_array)
                velocity_left = np.gradient(left_array)

                old_x = np.linspace(
                    0,
                    1,
                    len(right_array)
                )

                new_x = np.linspace(
                    0,
                    1,
                    SEQUENCE_LENGTH
                )

                def interp(arr):
                    return np.interp(new_x, old_x, arr)

                right_angle_seq = interp(right_array)
                left_angle_seq = interp(left_array)
                right_velocity_seq = interp(velocity_right)
                left_velocity_seq = interp(velocity_left)
                right_visibility_seq = interp(visibility_right)
                left_visibility_seq = interp(visibility_left)
                torso_tilt_seq = interp(torso_tilt_array)
                torso_rotation_seq = interp(torso_rotation_array)
                left_trajectory_seq = interp(left_trajectory_array)
                right_trajectory_seq = interp(right_trajectory_array)

                # Same normalization used during training
                right_angle_seq /= 180.0
                left_angle_seq /= 180.0

                right_velocity_seq /= 10.0
                left_velocity_seq /= 10.0

                torso_tilt_seq /= 90.0

                sequence = np.stack(
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
                        right_trajectory_seq
                    ],
                    axis=1
                )

                sequence = np.nan_to_num(
                    sequence,
                    nan=0.0,
                    posinf=0.0,
                    neginf=0.0
                )

                # ------------------------------------------------
                # LSTM
                # ------------------------------------------------

                sequence_tensor = torch.tensor(
                    sequence,
                    dtype=torch.float32
                ).unsqueeze(0).to(device)

                with torch.no_grad():

                    output = model(sequence_tensor)

                    probabilities = torch.softmax(
                        output,
                        dim=1
                    )

                    predicted_class = torch.argmax(
                        probabilities,
                        dim=1
                    ).item()

                    confidence = (
                        probabilities[0][predicted_class].item()
                        * 100.0
                    )

                prediction = (
                    "correct"
                    if predicted_class == 0
                    else "incorrect"
                )

                # ------------------------------------------------
                # SCORE
                # ------------------------------------------------

                last_result = analyze_rep(
                    range_of_motion=range_of_motion,
                    duration=duration,
                    smoothness=smoothness_raw,
                    prediction=prediction,
                    confidence=confidence
                )

                score = float(last_result["score"])

                # =================================================
                # FINAL TOLERANT DECISION
                # =================================================

                # The only strict movement requirement is reaching the
                # required elevation. Posture warnings remain soft so
                # normal variation does not turn good reps incorrect.
                final_error = None

                if max_angle_so_far < REQUIRED_TOP_ANGLE:
                    final_error = {
                        "type": "insufficient_height",
                        "frame": end_frame,
                        "feedback": (
                            "Raise your arm a little higher next time."
                        ),
                        "angle": max_angle_so_far,
                        "torso_tilt": max(rep_torso_tilt) if rep_torso_tilt else 0,
                        "torso_rotation": max(abs(x) for x in rep_torso_rotation) if rep_torso_rotation else 0,
                        "arm_asymmetry": max(
                            (abs(a - b) for a, b in zip(rep_angles_left, rep_angles_right)),
                            default=0
                        )
                    }

                # If height was achieved, use the score only as a forgiving
                # quality signal. A low score alone is not enough to call a
                # normal rep incorrect unless it is quite low.
                elif score < MIN_ACCEPTABLE_SCORE:
                    final_error = {
                        "type": "low_quality",
                        "frame": end_frame,
                        "feedback": (
                            "Try to make the movement slower and more controlled."
                        ),
                        "angle": max_angle_so_far,
                        "torso_tilt": max(rep_torso_tilt) if rep_torso_tilt else 0,
                        "torso_rotation": max(abs(x) for x in rep_torso_rotation) if rep_torso_rotation else 0,
                        "arm_asymmetry": max(
                            (abs(a - b) for a, b in zip(rep_angles_left, rep_angles_right)),
                            default=0
                        )
                    }

                if final_error is not None:
                    last_result["form"] = "Incorrect"
                    last_result["feedback"] = final_error["feedback"]

                    print("ERROR TYPE:", final_error["type"])
                    print("ERROR FRAME:", final_error["frame"])
                    print("ERROR FEEDBACK:", final_error["feedback"])

                else:
                    last_result["form"] = "Correct"

                    # Give useful positive feedback, while also surfacing
                    # a soft posture warning when one was consistently seen.
                    if first_error is not None:
                        last_result["feedback"] = (
                            "Good repetition. " + first_error["feedback"]
                        )
                    elif last_result["score"] >= 75:
                        last_result["feedback"] = (
                            "Excellent movement. Keep this controlled form."
                        )
                    elif last_result["score"] >= 60:
                        last_result["feedback"] = (
                            "Good movement. Keep your motion smooth and controlled."
                        )
                    else:
                        last_result["feedback"] = (
                            "Good height. Try to make the movement a little smoother."
                        )
                # ------------------------------------------------
                # RESULT
                # ------------------------------------------------

                print("\n==============================")
                print("REP", rep_count)
                print("==============================")
                print("Form:", last_result["form"])
                print(
                    "LSTM Confidence:",
                    round(confidence, 1),
                    "%"
                )
                print(
                    "ROM:",
                    round(range_of_motion, 1),
                    "degrees"
                )
                print(
                    "Maximum Angle:",
                    round(max_angle_so_far, 1),
                    "degrees"
                )
                print(
                    "Duration:",
                    round(duration, 2),
                    "sec"
                )
                print(
                    "Speed:",
                    last_result["speed"]
                )
                print(
                    "Smoothness:",
                    last_result["smoothness"],
                    "%"
                )
                print(
                    "Score:",
                    last_result["score"],
                    "/ 100"
                )
                print(
                    "Feedback:",
                    last_result["feedback"]
                )

            # ----------------------------------------------------
            # RESET
            # ----------------------------------------------------

            state = "DOWN"
            rep_start_frame = None

            (
                rep_angles_right,
                rep_angles_left,
                rep_visibility_right,
                rep_visibility_left,
                rep_torso_tilt,
                rep_torso_rotation,
                rep_left_trajectory,
                rep_right_trajectory,
                rep_error_frames
            ) = reset_rep_buffers()

            max_angle_so_far = 0.0
            height_reached = False

            active_error = None
            active_error_count = 0
            first_error = None

            current_feedback = (
                "Get ready — raise your arm."
            )

        previous_angle = current_angle

        # ====================================================
        # DRAW SKELETON ON SAME FRAME
        # ====================================================

        mp_drawing.draw_landmarks(
            display_frame,
            results.pose_landmarks,
            mp_pose.POSE_CONNECTIONS
        )

    else:

        current_feedback = "Move into the camera view."
        previous_angle = None

    # ========================================================
    # DISPLAY
    # ========================================================

    cv2.putText(
        display_frame,
        f"REPS: {rep_count}",
        (30, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        1,
        (0, 255, 0),
        2
    )

    cv2.putText(
        display_frame,
        (
            f"RIGHT ANGLE: {right_angle:.1f}"
            if results.pose_landmarks
            else "RIGHT ANGLE: --"
        ),
        (30, 85),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"STATE: {state}",
        (30, 125),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        current_feedback,
        (30, 165),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.62,
        (0, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"FORM: {last_result['form'].upper()}",
        (30, 205),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"CONFIDENCE: {last_result['confidence']:.1f}%",
        (30, 245),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"SCORE: {last_result['score']}/100",
        (30, 285),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 0),
        2
    )

    cv2.putText(
        display_frame,
        f"ROM: {last_result['range_of_motion']:.1f} deg",
        (30, 325),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"SPEED: {last_result['speed']}",
        (30, 365),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"SMOOTHNESS: {last_result['smoothness']:.1f}%",
        (30, 405),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"TARGET: {REQUIRED_TOP_ANGLE:.0f} deg",
        (30, 445),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        "Press Q to quit",
        (30, 690),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (200, 200, 200),
        1
    )

    cv2.imshow(
        "AI Physiotherapy Assessment",
        display_frame
    )

    if cv2.waitKey(1) & 0xFF == ord("q"):
        break


# ============================================================
# CLEANUP
# ============================================================

cap.release()
pose.close()
cv2.destroyAllWindows()

print("\nLive assessment stopped.")

import cv2
import numpy as np
import torch
import mediapipe as mp

from pathlib import Path

from src.models.lstm_model import ExerciseLSTM


# ============================================================
# SETTINGS
# ============================================================

MODEL_PATH = (
    Path(__file__).resolve().parents[2]
    / "models"
    / "assisted_shoulder_lstm.pth"
)

CAMERA_INDEX = 0

SEQUENCE_LENGTH = 128

# Movement thresholds
START_ANGLE = 40.0
REQUIRED_TOP_ANGLE = 110.0

# Used to detect that the person is actually trying to
# raise the arm.
UPWARD_MOVEMENT_THRESHOLD = 0.8

# Number of consecutive upward frames required before
# changing from WAITING -> RAISING.
UPWARD_FRAMES_REQUIRED = 4

# How far the angle may fall before considering that
# the person has started lowering.
LOWERING_DROP = 2.0

# Body compensation thresholds
MAX_TORSO_TILT = 15.0
MAX_TORSO_ROTATION = 0.35


# ============================================================
# DEVICE
# ============================================================

DEVICE = torch.device(
    "cuda"
    if torch.cuda.is_available()
    else "cpu"
)


# ============================================================
# LOAD MODEL
# ============================================================

def load_model():

    model = ExerciseLSTM(
        input_size=10,
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3
    )

    checkpoint = torch.load(
        MODEL_PATH,
        map_location=DEVICE
    )

    if isinstance(checkpoint, dict) and "model_state_dict" in checkpoint:

        model.load_state_dict(
            checkpoint["model_state_dict"]
        )

    else:

        model.load_state_dict(
            checkpoint
        )

    model.to(DEVICE)
    model.eval()

    print(
        f"Model loaded from: {MODEL_PATH}"
    )

    print(
        f"Device: {DEVICE}"
    )

    return model


# ============================================================
# ANGLE
# ============================================================

def calculate_angle(a, b, c):

    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    c = np.array(c, dtype=np.float32)

    ba = a - b
    bc = c - b

    denominator = (
        np.linalg.norm(ba)
        *
        np.linalg.norm(bc)
    )

    if denominator < 1e-8:
        return np.nan

    cosine = (
        np.dot(ba, bc)
        /
        denominator
    )

    cosine = np.clip(
        cosine,
        -1.0,
        1.0
    )

    return float(
        np.degrees(
            np.arccos(cosine)
        )
    )


# ============================================================
# FEATURE EXTRACTION
# ============================================================

def extract_features(landmarks):

    # MediaPipe landmark indices
    LEFT_SHOULDER = 11
    RIGHT_SHOULDER = 12

    LEFT_ELBOW = 13
    RIGHT_ELBOW = 14

    LEFT_HIP = 23
    RIGHT_HIP = 24

    # --------------------------------------------------------
    # Coordinates
    # --------------------------------------------------------

    ls = landmarks[LEFT_SHOULDER]
    rs = landmarks[RIGHT_SHOULDER]

    le = landmarks[LEFT_ELBOW]
    re = landmarks[RIGHT_ELBOW]

    lh = landmarks[LEFT_HIP]
    rh = landmarks[RIGHT_HIP]

    # --------------------------------------------------------
    # 1. LEFT SHOULDER ANGLE
    # --------------------------------------------------------

    left_angle = calculate_angle(
        lh,
        ls,
        le
    )

    # --------------------------------------------------------
    # 2. RIGHT SHOULDER ANGLE
    # --------------------------------------------------------

    right_angle = calculate_angle(
        rh,
        rs,
        re
    )

    # --------------------------------------------------------
    # 3 & 4. Angular velocity
    #
    # Calculated outside because we need previous angles.
    # --------------------------------------------------------

    # --------------------------------------------------------
    # Visibility
    # --------------------------------------------------------

    left_visibility = float(
        ls[3]
    )

    right_visibility = float(
        rs[3]
    )

    # --------------------------------------------------------
    # TORSO CENTER
    # --------------------------------------------------------

    shoulder_mid = (
        np.array(ls[:3])
        +
        np.array(rs[:3])
    ) / 2.0

    hip_mid = (
        np.array(lh[:3])
        +
        np.array(rh[:3])
    ) / 2.0

    # --------------------------------------------------------
    # 7. TORSO TILT
    # --------------------------------------------------------

    torso_dx = (
        shoulder_mid[0]
        -
        hip_mid[0]
    )

    torso_dy = (
        shoulder_mid[1]
        -
        hip_mid[1]
    )

    torso_tilt = float(
        np.degrees(
            np.arctan2(
                abs(torso_dx),
                abs(torso_dy) + 1e-8
            )
        )
    )

    # --------------------------------------------------------
    # 8. TORSO ROTATION / DEPTH ASYMMETRY
    # --------------------------------------------------------

    shoulder_width = np.linalg.norm(
        np.array(rs[:2])
        -
        np.array(ls[:2])
    )

    if shoulder_width > 1e-8:

        torso_rotation = (
            float(rs[2])
            -
            float(ls[2])
        ) / shoulder_width

    else:

        torso_rotation = 0.0

    # --------------------------------------------------------
    # 9. LEFT ARM TRAJECTORY
    # --------------------------------------------------------

    torso_length = np.linalg.norm(
        shoulder_mid[:2]
        -
        hip_mid[:2]
    )

    if torso_length > 1e-8:

        left_arm_trajectory = (
            float(le[0])
            -
            float(ls[0])
        ) / torso_length

        # ----------------------------------------------------
        # 10. RIGHT ARM TRAJECTORY
        # ----------------------------------------------------

        right_arm_trajectory = (
            float(re[0])
            -
            float(rs[0])
        ) / torso_length

    else:

        left_arm_trajectory = 0.0
        right_arm_trajectory = 0.0

    return {
        "left_angle": left_angle,
        "right_angle": right_angle,

        "left_visibility":
            left_visibility,

        "right_visibility":
            right_visibility,

        "torso_tilt":
            torso_tilt,

        "torso_rotation":
            torso_rotation,

        "left_arm_trajectory":
            left_arm_trajectory,

        "right_arm_trajectory":
            right_arm_trajectory
    }


# ============================================================
# RESIZE FEATURE SEQUENCE
# ============================================================

def resize_feature(
    values,
    length=128
):

    values = np.asarray(
        values,
        dtype=np.float32
    )

    if len(values) < 2:

        return np.zeros(
            length,
            dtype=np.float32
        )

    old_positions = np.linspace(
        0,
        1,
        len(values)
    )

    new_positions = np.linspace(
        0,
        1,
        length
    )

    return np.interp(
        new_positions,
        old_positions,
        values
    ).astype(np.float32)


# ============================================================
# CREATE MODEL SEQUENCE
# ============================================================

def create_sequence(history):

    if len(history) < 2:
        return None

    right_angle = [
        x["right_angle"]
        for x in history
    ]

    left_angle = [
        x["left_angle"]
        for x in history
    ]

    right_velocity = [
        x["right_velocity"]
        for x in history
    ]

    left_velocity = [
        x["left_velocity"]
        for x in history
    ]

    right_visibility = [
        x["right_visibility"]
        for x in history
    ]

    left_visibility = [
        x["left_visibility"]
        for x in history
    ]

    torso_tilt = [
        x["torso_tilt"]
        for x in history
    ]

    torso_rotation = [
        x["torso_rotation"]
        for x in history
    ]

    left_arm_trajectory = [
        x["left_arm_trajectory"]
        for x in history
    ]

    right_arm_trajectory = [
        x["right_arm_trajectory"]
        for x in history
    ]

    features = [
        right_angle,
        left_angle,
        right_velocity,
        left_velocity,
        right_visibility,
        left_visibility,
        torso_tilt,
        torso_rotation,
        left_arm_trajectory,
        right_arm_trajectory
    ]

    resized = np.zeros(
        (SEQUENCE_LENGTH, 10),
        dtype=np.float32
    )

    for i, feature in enumerate(features):

        resized[:, i] = resize_feature(
            feature,
            SEQUENCE_LENGTH
        )

    # --------------------------------------------------------
    # SAME NORMALIZATION USED DURING TRAINING
    # --------------------------------------------------------

    resized[:, 0] /= 180.0
    resized[:, 1] /= 180.0

    resized[:, 2] /= 10.0
    resized[:, 3] /= 10.0

    resized[:, 6] /= 90.0

    resized = np.nan_to_num(
        resized,
        nan=0.0,
        posinf=1.0,
        neginf=-1.0
    )

    return resized


# ============================================================
# MODEL PREDICTION
# ============================================================

def predict(model, sequence):

    tensor = torch.tensor(
        sequence,
        dtype=torch.float32,
        device=DEVICE
    )

    tensor = tensor.unsqueeze(0)

    with torch.no_grad():

        logits = model(
            tensor
        )

        probabilities = torch.softmax(
            logits,
            dim=1
        )[0]

    prediction = int(
        torch.argmax(
            probabilities
        ).item()
    )

    confidence = float(
        probabilities[prediction].item()
        * 100
    )

    # IMPORTANT:
    # 0 = correct
    # 1 = incorrect
    if prediction == 0:

        label = "CORRECT"

    else:

        label = "INCORRECT"

    return (
        label,
        confidence,
        probabilities
    )


# ============================================================
# DRAW TEXT
# ============================================================

def draw_text(
    frame,
    text,
    position,
    scale=0.8,
    thickness=2
):

    cv2.putText(
        frame,
        text,
        position,
        cv2.FONT_HERSHEY_SIMPLEX,
        scale,
        (255, 255, 255),
        thickness,
        cv2.LINE_AA
    )


# ============================================================
# MAIN
# ============================================================

def main():

    model = load_model()

    # --------------------------------------------------------
    # MediaPipe
    # --------------------------------------------------------

    mp_pose = mp.solutions.pose

    mp_drawing = mp.solutions.drawing_utils

    pose = mp_pose.Pose(
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    )

    # --------------------------------------------------------
    # Camera
    # --------------------------------------------------------

    cap = cv2.VideoCapture(
        CAMERA_INDEX
    )

    cap.set(
        cv2.CAP_PROP_FRAME_WIDTH,
        1280
    )

    cap.set(
        cv2.CAP_PROP_FRAME_HEIGHT,
        720
    )

    if not cap.isOpened():

        print(
            "ERROR: Could not open camera."
        )

        return

    # --------------------------------------------------------
    # State
    # --------------------------------------------------------

    state = "WAITING"

    rep_count = 0

    previous_angle = None

    max_angle_so_far = 0.0

    upward_frames = 0

    movement_history = []

    final_result = "READY"

    final_confidence = 0.0

    feedback = "Get ready."

    # Keep feedback visible for a few frames
    feedback_timer = 0

    print("\nCamera started.")
    print("Press Q to quit.")

    # ========================================================
    # LOOP
    # ========================================================

    while True:

        ret, frame = cap.read()

        if not ret:
            break

        # IMPORTANT:
        # NO FLIP.
        #
        # This preserves the camera orientation that was
        # previously working correctly.

        rgb = cv2.cvtColor(
            frame,
            cv2.COLOR_BGR2RGB
        )

        results = pose.process(
            rgb
        )

        # ====================================================
        # POSE DETECTED
        # ====================================================

        if results.pose_landmarks:

            landmarks = []

            for lm in results.pose_landmarks.landmark:

                landmarks.append([
                    lm.x,
                    lm.y,
                    lm.z,
                    lm.visibility
                ])

            features = extract_features(
                landmarks
            )

            left_angle = features[
                "left_angle"
            ]

            right_angle = features[
                "right_angle"
            ]

            # ------------------------------------------------
            # Choose visible side
            # ------------------------------------------------

            if (
                features["right_visibility"]
                >=
                features["left_visibility"]
            ):

                current_angle = right_angle
                active_side = "RIGHT"

            else:

                current_angle = left_angle
                active_side = "LEFT"

            # ------------------------------------------------
            # Invalid angle
            # ------------------------------------------------

            if np.isnan(current_angle):

                current_angle = (
                    previous_angle
                    if previous_angle is not None
                    else 0.0
                )

            # ------------------------------------------------
            # Angular velocity
            # ------------------------------------------------

            if previous_angle is None:

                velocity = 0.0

            else:

                velocity = (
                    current_angle
                    -
                    previous_angle
                )

            # ------------------------------------------------
            # Add velocity
            # ------------------------------------------------

            features[
                "right_velocity"
            ] = velocity

            features[
                "left_velocity"
            ] = velocity

            # =================================================
            # WAITING
            # =================================================

            if state == "WAITING":

                feedback = (
                    "Get ready — raise your arm."
                )

                # Detect actual attempt to raise.
                if velocity > UPWARD_MOVEMENT_THRESHOLD:

                    upward_frames += 1

                else:

                    upward_frames = 0

                if (
                    upward_frames
                    >=
                    UPWARD_FRAMES_REQUIRED
                ):

                    state = "RAISING"

                    upward_frames = 0

                    max_angle_so_far = (
                        current_angle
                    )

                    movement_history = []

                    final_result = "RAISING"

                    feedback = (
                        "Raise your arm higher."
                    )

            # =================================================
            # RAISING
            # =================================================

            elif state == "RAISING":

                max_angle_so_far = max(
                    max_angle_so_far,
                    current_angle
                )

                # ---------------------------------------------
                # Store frame features
                # ---------------------------------------------

                movement_history.append(
                    features.copy()
                )

                # ---------------------------------------------
                # Detect torso compensation immediately
                # ---------------------------------------------

                if (
                    features["torso_tilt"]
                    >
                    MAX_TORSO_TILT
                ):

                    feedback = (
                        "Keep your torso upright."
                    )

                elif (
                    abs(
                        features["torso_rotation"]
                    )
                    >
                    MAX_TORSO_ROTATION
                ):

                    feedback = (
                        "Keep your upper body facing forward."
                    )

                # ---------------------------------------------
                # Height feedback
                # ---------------------------------------------

                elif current_angle < 80:

                    feedback = (
                        "Raise your arm higher."
                    )

                elif current_angle < 100:

                    feedback = (
                        "Keep raising your arm higher."
                    )

                elif current_angle < REQUIRED_TOP_ANGLE:

                    feedback = (
                        "Almost there — raise a little higher."
                    )

                else:

                    # REQUIRED HEIGHT REACHED
                    state = "TOP"

                    feedback = (
                        "Good height — now lower your arm slowly."
                    )

                    final_result = "HEIGHT REACHED"

                # ---------------------------------------------
                # If user stops before reaching required height
                # and starts lowering, catch it.
                # ---------------------------------------------

                if (
                    previous_angle is not None
                    and
                    velocity < -LOWERING_DROP
                    and
                    max_angle_so_far < REQUIRED_TOP_ANGLE
                ):

                    state = "LOWERING_INCORRECT"

                    feedback = (
                        "Raise your arm higher — "
                        "you did not reach the required height."
                    )

            # =================================================
            # TOP
            # =================================================

            elif state == "TOP":

                movement_history.append(
                    features.copy()
                )

                if (
                    current_angle
                    <
                    max_angle_so_far
                    -
                    LOWERING_DROP
                ):

                    state = "LOWERING"

                    feedback = (
                        "Lower your arm slowly."
                    )

            # =================================================
            # LOWERING AFTER FAILURE
            # =================================================

            elif state == "LOWERING_INCORRECT":

                movement_history.append(
                    features.copy()
                )

                feedback = (
                    "Try to raise your arm higher "
                    "on the next repetition."
                )

                # Rep finishes when we return near start
                if current_angle < START_ANGLE:

                    rep_count += 1

                    # -----------------------------------------
                    # Final LSTM prediction
                    # -----------------------------------------

                    sequence = create_sequence(
                        movement_history
                    )

                    if sequence is not None:

                        (
                            final_result,
                            final_confidence,
                            probabilities
                        ) = predict(
                            model,
                            sequence
                        )

                    # Force known height failure to incorrect
                    # because the explicit movement requirement
                    # was violated.
                    final_result = "INCORRECT"

                    final_confidence = max(
                        final_confidence,
                        90.0
                    )

                    feedback = (
                        "Incorrect: "
                        "raise your arm higher."
                    )

                    state = "WAITING"

                    movement_history = []

                    max_angle_so_far = 0.0

            # =================================================
            # NORMAL LOWERING
            # =================================================

            elif state == "LOWERING":

                movement_history.append(
                    features.copy()
                )

                feedback = (
                    "Lower your arm slowly."
                )

                # Rep complete
                if current_angle < START_ANGLE:

                    rep_count += 1

                    # -----------------------------------------
                    # LSTM
                    # -----------------------------------------

                    sequence = create_sequence(
                        movement_history
                    )

                    if sequence is not None:

                        (
                            final_result,
                            final_confidence,
                            probabilities
                        ) = predict(
                            model,
                            sequence
                        )

                    # -----------------------------------------
                    # Explicit height safety check
                    # -----------------------------------------

                    if (
                        max_angle_so_far
                        <
                        REQUIRED_TOP_ANGLE
                    ):

                        final_result = (
                            "INCORRECT"
                        )

                        final_confidence = max(
                            final_confidence,
                            90.0
                        )

                        feedback = (
                            "Incorrect: "
                            "raise your arm higher."
                        )

                    else:

                        feedback = (
                            f"{final_result} — "
                            f"rep {rep_count} complete."
                        )

                    # Reset
                    state = "WAITING"

                    movement_history = []

                    max_angle_so_far = 0.0

            # ------------------------------------------------
            # Previous angle
            # ------------------------------------------------

            previous_angle = current_angle

            # =================================================
            # DRAW SKELETON
            # =================================================

            mp_drawing.draw_landmarks(
                frame,
                results.pose_landmarks,
                mp_pose.POSE_CONNECTIONS
            )

            # =================================================
            # DISPLAY
            # =================================================

            draw_text(
                frame,
                f"REPS: {rep_count}",
                (30, 40),
                0.8,
                2
            )

            draw_text(
                frame,
                f"{active_side} ANGLE: "
                f"{current_angle:.1f} deg",
                (30, 75),
                0.7,
                2
            )

            draw_text(
                frame,
                f"STATE: {state}",
                (30, 110),
                0.7,
                2
            )

            draw_text(
                frame,
                f"MAX: {max_angle_so_far:.1f} deg",
                (30, 145),
                0.7,
                2
            )

            draw_text(
                frame,
                f"REQUIRED: "
                f"{REQUIRED_TOP_ANGLE:.0f} deg",
                (30, 180),
                0.7,
                2
            )

            draw_text(
                frame,
                f"FORM: {final_result}",
                (30, 220),
                0.8,
                2
            )

            draw_text(
                frame,
                f"CONF: "
                f"{final_confidence:.1f}%",
                (30, 255),
                0.7,
                2
            )

            # ------------------------------------------------
            # Large feedback
            # ------------------------------------------------

            draw_text(
                frame,
                feedback,
                (30, 310),
                0.8,
                2
            )

        else:

            draw_text(
                frame,
                "NO PERSON DETECTED",
                (30, 50),
                0.8,
                2
            )

        # ====================================================
        # SHOW
        # ====================================================

        cv2.imshow(
            "Assisted Shoulder Flexion",
            frame
        )

        key = cv2.waitKey(1) & 0xFF

        if key == ord("q"):

            break

    # ========================================================
    # CLEANUP
    # ========================================================

    cap.release()

    cv2.destroyAllWindows()

    pose.close()


# ============================================================
# RUN
# ============================================================

if __name__ == "__main__":
    main()
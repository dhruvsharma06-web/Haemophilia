import cv2
import mediapipe as mp
import numpy as np
import torch
import sys
import os

# Allow importing from src/
sys.path.append(
    os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..")
    )
)

from models.lstm_model import ExerciseLSTM
from feedback.score_feedback import analyze_rep


# ============================================================
# SETTINGS
# ============================================================

MODEL_PATH = "models/assisted_shoulder_lstm.pth"

SEQUENCE_LENGTH = 128
START_ANGLE = 40

# ============================================================
# DEVICE
# ============================================================

device = torch.device(
    "cuda" if torch.cuda.is_available() else "cpu"
)

print("Device:", device)

if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))


# ============================================================
# LOAD MODEL
# ============================================================

model = ExerciseLSTM(
    input_size=6,
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
    model_complexity=1,
    smooth_landmarks=True,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)


# ============================================================
# ANGLE FUNCTION
# ============================================================

def calculate_angle(a, b, c):

    a = np.array(a)
    b = np.array(b)
    c = np.array(c)

    ba = a - b
    bc = c - b

    cosine_angle = np.dot(ba, bc) / (
        np.linalg.norm(ba) *
        np.linalg.norm(bc) + 1e-8
    )

    cosine_angle = np.clip(
        cosine_angle,
        -1.0,
        1.0
    )

    angle = np.degrees(
        np.arccos(cosine_angle)
    )

    return angle


# ============================================================
# CAMERA
# ============================================================

cap = cv2.VideoCapture(0)

cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

fps = cap.get(cv2.CAP_PROP_FPS)

if fps <= 0:
    fps = 30

print("Camera FPS:", fps)


# ============================================================
# REP VARIABLES
# ============================================================

state = "DOWN"

rep_count = 0

rep_angles_right = []
rep_angles_left = []

rep_visibility_right = []
rep_visibility_left = []

rep_start_frame = None

frame_number = 0


# ============================================================
# LAST RESULT
# ============================================================

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
        break

    frame_number += 1

    # Mirror camera for natural display
    display_frame = cv2.flip(frame, 1)

    # MediaPipe uses RGB
    rgb = cv2.cvtColor(
        frame,
        cv2.COLOR_BGR2RGB
    )

    results = pose.process(rgb)

    # --------------------------------------------------------
    # POSE DETECTED
    # --------------------------------------------------------

    if results.pose_landmarks:

        landmarks = results.pose_landmarks.landmark

        # Left side
        left_hip = landmarks[23]
        left_shoulder = landmarks[11]
        left_elbow = landmarks[13]

        # Right side
        right_hip = landmarks[24]
        right_shoulder = landmarks[12]
        right_elbow = landmarks[14]

        # Calculate angles
        left_angle = calculate_angle(
            [left_hip.x, left_hip.y],
            [left_shoulder.x, left_shoulder.y],
            [left_elbow.x, left_elbow.y]
        )

        right_angle = calculate_angle(
            [right_hip.x, right_hip.y],
            [right_shoulder.x, right_shoulder.y],
            [right_elbow.x, right_elbow.y]
        )

        left_visibility = left_shoulder.visibility
        right_visibility = right_shoulder.visibility

        # Average angle for rep detection
        current_angle = (
            left_angle + right_angle
        ) / 2

        # ----------------------------------------------------
        # REP START
        # ----------------------------------------------------

        if (
            state == "DOWN"
            and current_angle > START_ANGLE
        ):

            state = "UP"

            rep_start_frame = frame_number

            rep_angles_right = []
            rep_angles_left = []

            rep_visibility_right = []
            rep_visibility_left = []

        # ----------------------------------------------------
        # COLLECT REP DATA
        # ----------------------------------------------------

        if state == "UP":

            rep_angles_right.append(
                right_angle
            )

            rep_angles_left.append(
                left_angle
            )

            rep_visibility_right.append(
                right_visibility
            )

            rep_visibility_left.append(
                left_visibility
            )

        # ----------------------------------------------------
        # REP COMPLETE
        # ----------------------------------------------------

        if (
            state == "UP"
            and current_angle < START_ANGLE
            and rep_start_frame is not None
        ):

            end_frame = frame_number

            duration = (
                end_frame - rep_start_frame
            ) / fps

            # Require enough frames
            if len(rep_angles_right) >= 20:

                rep_count += 1

                # ------------------------------------------------
                # RANGE OF MOTION
                # ------------------------------------------------

                right_rom = (
                    max(rep_angles_right)
                    - min(rep_angles_right)
                )

                left_rom = (
                    max(rep_angles_left)
                    - min(rep_angles_left)
                )

                range_of_motion = (
                    right_rom + left_rom
                ) / 2

                # ------------------------------------------------
                # SMOOTHNESS
                # ------------------------------------------------

                right_array = np.array(
                    rep_angles_right
                )

                left_array = np.array(
                    rep_angles_left
                )

                right_second_diff = np.diff(
                    right_array,
                    n=2
                )

                left_second_diff = np.diff(
                    left_array,
                    n=2
                )

                smoothness_raw = 1 / (
                    1 +
                    (
                        np.mean(
                            np.abs(
                                np.concatenate(
                                    [
                                        right_second_diff,
                                        left_second_diff
                                    ]
                                )
                            )
                        )
                    )
                )

                # ------------------------------------------------
                # CREATE 6-FEATURE SEQUENCE
                # ------------------------------------------------

                angles_right = np.array(
                    rep_angles_right
                )

                angles_left = np.array(
                    rep_angles_left
                )

                visibility_right = np.array(
                    rep_visibility_right
                )

                visibility_left = np.array(
                    rep_visibility_left
                )

                # Angular velocity
                velocity_right = np.gradient(
                    angles_right
                )

                velocity_left = np.gradient(
                    angles_left
                )

                # Interpolation
                old_x = np.linspace(
                    0,
                    1,
                    len(angles_right)
                )

                new_x = np.linspace(
                    0,
                    1,
                    SEQUENCE_LENGTH
                )

                right_angle_seq = np.interp(
                    new_x,
                    old_x,
                    angles_right
                )

                left_angle_seq = np.interp(
                    new_x,
                    old_x,
                    angles_left
                )

                right_velocity_seq = np.interp(
                    new_x,
                    old_x,
                    velocity_right
                )

                left_velocity_seq = np.interp(
                    new_x,
                    old_x,
                    velocity_left
                )

                right_visibility_seq = np.interp(
                    new_x,
                    old_x,
                    visibility_right
                )

                left_visibility_seq = np.interp(
                    new_x,
                    old_x,
                    visibility_left
                )

                # ------------------------------------------------
                # NORMALIZATION
                # ------------------------------------------------

                right_angle_seq /= 180.0
                left_angle_seq /= 180.0

                right_velocity_seq /= 10.0
                left_velocity_seq /= 10.0

                # ------------------------------------------------
                # FINAL 128 x 6 SEQUENCE
                # ------------------------------------------------

                sequence = np.stack(
                    [
                        right_angle_seq,
                        left_angle_seq,
                        right_velocity_seq,
                        left_velocity_seq,
                        right_visibility_seq,
                        left_visibility_seq
                    ],
                    axis=1
                )

                sequence_tensor = torch.tensor(
                    sequence,
                    dtype=torch.float32
                ).unsqueeze(0).to(device)

                # ------------------------------------------------
                # LSTM PREDICTION
                # ------------------------------------------------

                with torch.no_grad():

                    output = model(
                        sequence_tensor
                    )

                    probabilities = torch.softmax(
                        output,
                        dim=1
                    )

                    predicted_class = torch.argmax(
                        probabilities,
                        dim=1
                    ).item()

                    confidence = (
                        probabilities[0][
                            predicted_class
                        ].item() * 100
                    )

                if predicted_class == 0:
                    prediction = "correct"
                else:
                    prediction = "incorrect"

                # ------------------------------------------------
                # SCORE + FEEDBACK
                # ------------------------------------------------

                last_result = analyze_rep(
                    range_of_motion=range_of_motion,
                    duration=duration,
                    smoothness=smoothness_raw,
                    prediction=prediction,
                    confidence=confidence
                )

                print("\n==============================")
                print("REP", rep_count)
                print("==============================")
                print(
                    "Form:",
                    last_result["form"]
                )
                print(
                    "Confidence:",
                    last_result["confidence"],
                    "%"
                )
                print(
                    "ROM:",
                    last_result["range_of_motion"],
                    "degrees"
                )
                print(
                    "Duration:",
                    last_result["duration"],
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

            # Reset
            state = "DOWN"

            rep_start_frame = None

            rep_angles_right = []
            rep_angles_left = []

            rep_visibility_right = []
            rep_visibility_left = []

        # ----------------------------------------------------
        # DRAW SKELETON
        # ----------------------------------------------------

        mp_drawing.draw_landmarks(
            display_frame,
            results.pose_landmarks,
            mp_pose.POSE_CONNECTIONS
        )

    # ========================================================
    # DISPLAY INFORMATION
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
        f"RIGHT ANGLE: {right_angle:.1f}"
        if results.pose_landmarks
        else "RIGHT ANGLE: --",
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
        f"FORM: {last_result['form'].upper()}",
        (30, 170),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"CONFIDENCE: {last_result['confidence']:.1f}%",
        (30, 210),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"SCORE: {last_result['score']}/100",
        (30, 250),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 0),
        2
    )

    cv2.putText(
        display_frame,
        f"ROM: {last_result['range_of_motion']:.1f} deg",
        (30, 290),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"SPEED: {last_result['speed']}",
        (30, 330),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"SMOOTHNESS: {last_result['smoothness']:.1f}%",
        (30, 370),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    # Short feedback on screen
    feedback = last_result["feedback"]

    # Wrap feedback into two lines
    words = feedback.split()

    line1 = ""
    line2 = ""

    for word in words:

        if len(line1 + " " + word) < 55:
            line1 += " " + word
        else:
            line2 += " " + word

    cv2.putText(
        display_frame,
        line1.strip(),
        (30, 420),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (0, 255, 255),
        2
    )

    if line2:

        cv2.putText(
            display_frame,
            line2.strip(),
            (30, 450),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 255, 255),
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

    # Show
    cv2.imshow(
        "AI Physiotherapy Assessment",
        display_frame
    )

    # Quit
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break


# ============================================================
# CLEANUP
# ============================================================

cap.release()
pose.close()
cv2.destroyAllWindows()

print("\nLive assessment stopped.")
print("Today's MVP work is complete.")
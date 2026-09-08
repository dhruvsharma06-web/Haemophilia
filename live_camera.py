import cv2
import mediapipe as mp
import numpy as np
import torch
import os
import sys

# ============================================================
# PATH
# ============================================================

PROJECT_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..")
)

sys.path.append(PROJECT_ROOT)

from src.models.lstm_model import ExerciseLSTM


# ============================================================
# SETTINGS
# ============================================================

MODEL_PATH = os.path.join(
    PROJECT_ROOT,
    "models",
    "assisted_shoulder_lstm.pth"
)

SEQUENCE_LENGTH = 128

START_ANGLE = 40

MIN_REP_FRAMES = 20

# Real-time visual guidance
GOOD_MIN_ANGLE = 40
GOOD_MAX_ANGLE = 165

# ============================================================
# DEVICE
# ============================================================

device = torch.device(
    "cuda" if torch.cuda.is_available() else "cpu"
)

print("Device:", device)

if torch.cuda.is_available():
    print(
        "GPU:",
        torch.cuda.get_device_name(0)
    )


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

print("Model loaded.")


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

    denominator = (
        np.linalg.norm(ba) *
        np.linalg.norm(bc)
    )

    if denominator < 1e-8:
        return 0.0

    cosine = np.dot(ba, bc) / denominator

    cosine = np.clip(
        cosine,
        -1.0,
        1.0
    )

    return np.degrees(
        np.arccos(cosine)
    )


# ============================================================
# RESIZE
# ============================================================

def resize_sequence(values):

    values = np.asarray(values)

    if len(values) < 2:
        return np.zeros(SEQUENCE_LENGTH)

    old_x = np.linspace(
        0,
        1,
        len(values)
    )

    new_x = np.linspace(
        0,
        1,
        SEQUENCE_LENGTH
    )

    return np.interp(
        new_x,
        old_x,
        values
    )


# ============================================================
# CAMERA
# ============================================================

cap = cv2.VideoCapture(0)

cap.set(
    cv2.CAP_PROP_FRAME_WIDTH,
    1280
)

cap.set(
    cv2.CAP_PROP_FRAME_HEIGHT,
    720
)

fps = cap.get(
    cv2.CAP_PROP_FPS
)

if fps <= 0:
    fps = 30

print("FPS:", fps)


# ============================================================
# REP VARIABLES
# ============================================================

state = "DOWN"

rep_count = 0

frame_number = 0

rep_start_frame = None

right_angles = []
left_angles = []

right_visibility = []
left_visibility = []


# ============================================================
# DISPLAY
# ============================================================

form_text = "WAITING"

confidence = 0

correct_probability = 0

incorrect_probability = 0

movement_status = "NEUTRAL"


# ============================================================
# MAIN LOOP
# ============================================================

while True:

    ret, frame = cap.read()

    if not ret:
        print("Camera frame unavailable.")
        break

    frame_number += 1

    # --------------------------------------------------------
    # NO FLIP
    # --------------------------------------------------------

    display_frame = frame.copy()

    rgb = cv2.cvtColor(
        display_frame,
        cv2.COLOR_BGR2RGB
    )

    results = pose.process(rgb)

    right_angle_display = "--"


    # ========================================================
    # DEFAULT SKELETON = BLUE
    # ========================================================

    landmark_color = (255, 0, 0)

    connection_color = (255, 0, 0)


    # ========================================================
    # POSE
    # ========================================================

    if results.pose_landmarks:

        lm = results.pose_landmarks.landmark

        # ----------------------------------------------------
        # LEFT
        # ----------------------------------------------------

        left_hip = lm[23]
        left_shoulder = lm[11]
        left_elbow = lm[13]

        # ----------------------------------------------------
        # RIGHT
        # ----------------------------------------------------

        right_hip = lm[24]
        right_shoulder = lm[12]
        right_elbow = lm[14]

        # ----------------------------------------------------
        # ANGLES
        # ----------------------------------------------------

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

        right_angle_display = f"{right_angle:.1f}"

        left_vis = left_shoulder.visibility
        right_vis = right_shoulder.visibility

        current_angle = (
            left_angle +
            right_angle
        ) / 2


        # ====================================================
        # REAL-TIME COLOUR GUIDANCE
        # ====================================================

        if current_angle < GOOD_MIN_ANGLE:

            # Starting / neutral
            movement_status = "NEUTRAL"

            landmark_color = (255, 0, 0)
            connection_color = (255, 0, 0)

        elif (
            GOOD_MIN_ANGLE
            <= current_angle
            <= GOOD_MAX_ANGLE
        ):

            # Expected movement zone
            movement_status = "GOOD MOTION"

            landmark_color = (0, 255, 0)
            connection_color = (0, 255, 0)

        else:

            # Outside expected angle
            movement_status = "OUT OF RANGE"

            landmark_color = (0, 0, 255)
            connection_color = (0, 0, 255)


        # ====================================================
        # START REP
        # ====================================================

        if (
            state == "DOWN"
            and current_angle > START_ANGLE
        ):

            state = "UP"

            rep_start_frame = frame_number

            right_angles = []

            left_angles = []

            right_visibility = []

            left_visibility = []


        # ====================================================
        # COLLECT REP
        # ====================================================

        if state == "UP":

            right_angles.append(
                right_angle
            )

            left_angles.append(
                left_angle
            )

            right_visibility.append(
                right_vis
            )

            left_visibility.append(
                left_vis
            )


        # ====================================================
        # COMPLETE REP
        # ====================================================

        if (
            state == "UP"
            and current_angle < START_ANGLE
            and rep_start_frame is not None
        ):

            duration = (
                frame_number -
                rep_start_frame
            ) / fps

            if len(right_angles) >= MIN_REP_FRAMES:

                rep_count += 1

                # --------------------------------------------
                # ARRAYS
                # --------------------------------------------

                right = np.array(
                    right_angles,
                    dtype=np.float32
                )

                left = np.array(
                    left_angles,
                    dtype=np.float32
                )

                rv = np.array(
                    right_visibility,
                    dtype=np.float32
                )

                lv = np.array(
                    left_visibility,
                    dtype=np.float32
                )

                # --------------------------------------------
                # VELOCITY
                # --------------------------------------------

                right_velocity = np.gradient(right)

                left_velocity = np.gradient(left)

                # --------------------------------------------
                # RESIZE
                # --------------------------------------------

                right_seq = resize_sequence(right)

                left_seq = resize_sequence(left)

                right_velocity_seq = resize_sequence(
                    right_velocity
                )

                left_velocity_seq = resize_sequence(
                    left_velocity
                )

                right_vis_seq = resize_sequence(rv)

                left_vis_seq = resize_sequence(lv)

                # --------------------------------------------
                # NORMALIZE
                # --------------------------------------------

                right_seq /= 180.0
                left_seq /= 180.0

                right_velocity_seq /= 10.0
                left_velocity_seq /= 10.0

                # --------------------------------------------
                # 128 x 6
                # --------------------------------------------

                sequence = np.stack(
                    [
                        right_seq,
                        left_seq,
                        right_velocity_seq,
                        left_velocity_seq,
                        right_vis_seq,
                        left_vis_seq
                    ],
                    axis=1
                )

                # --------------------------------------------
                # LSTM
                # --------------------------------------------

                x = torch.tensor(
                    sequence,
                    dtype=torch.float32
                ).unsqueeze(0)

                x = x.to(device)

                with torch.no_grad():

                    output = model(x)

                    probabilities = torch.softmax(
                        output,
                        dim=1
                    )[0]

                # --------------------------------------------
                # CLASS MAPPING
                # --------------------------------------------

                correct_probability = (
                    probabilities[0].item()
                    * 100
                )

                incorrect_probability = (
                    probabilities[1].item()
                    * 100
                )

                if (
                    correct_probability
                    >=
                    incorrect_probability
                ):

                    form_text = "CORRECT"

                    confidence = (
                        correct_probability
                    )

                else:

                    form_text = "INCORRECT"

                    confidence = (
                        incorrect_probability
                    )


                # --------------------------------------------
                # TERMINAL
                # --------------------------------------------

                print()
                print(
                    "================================"
                )

                print(
                    f"REP {rep_count}"
                )

                print(
                    "================================"
                )

                print(
                    f"Correct probability   : "
                    f"{correct_probability:.2f}%"
                )

                print(
                    f"Incorrect probability : "
                    f"{incorrect_probability:.2f}%"
                )

                print(
                    f"Prediction            : "
                    f"{form_text}"
                )

                print(
                    f"Duration              : "
                    f"{duration:.2f} sec"
                )


            # ----------------------------------------------
            # RESET
            # ----------------------------------------------

            state = "DOWN"

            rep_start_frame = None

            right_angles = []

            left_angles = []

            right_visibility = []

            left_visibility = []


        # ====================================================
        # DRAW COLOURED SKELETON
        # ====================================================

        landmark_spec = mp_drawing.DrawingSpec(
            color=landmark_color,
            thickness=3,
            circle_radius=4
        )

        connection_spec = mp_drawing.DrawingSpec(
            color=connection_color,
            thickness=3
        )

        mp_drawing.draw_landmarks(
            display_frame,
            results.pose_landmarks,
            mp_pose.POSE_CONNECTIONS,
            landmark_drawing_spec=landmark_spec,
            connection_drawing_spec=connection_spec
        )


    # ========================================================
    # UI
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
        f"RIGHT ANGLE: {right_angle_display}",
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

    # --------------------------------------------------------
    # MOVEMENT STATUS
    # --------------------------------------------------------

    if movement_status == "GOOD MOTION":

        status_color = (0, 255, 0)

    elif movement_status == "OUT OF RANGE":

        status_color = (0, 0, 255)

    else:

        status_color = (255, 0, 0)

    cv2.putText(
        display_frame,
        f"MOTION: {movement_status}",
        (30, 165),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        status_color,
        2
    )


    # --------------------------------------------------------
    # FORM
    # --------------------------------------------------------

    cv2.putText(
        display_frame,
        f"FORM: {form_text}",
        (30, 210),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"CONFIDENCE: {confidence:.1f}%",
        (30, 250),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"CORRECT: {correct_probability:.1f}%",
        (30, 290),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )

    cv2.putText(
        display_frame,
        f"INCORRECT: {incorrect_probability:.1f}%",
        (30, 325),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.65,
        (255, 255, 255),
        2
    )


    # --------------------------------------------------------
    # COLOUR LEGEND
    # --------------------------------------------------------

    cv2.putText(
        display_frame,
        "BLUE  = Neutral",
        (900, 45),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (255, 0, 0),
        2
    )

    cv2.putText(
        display_frame,
        "GREEN = Good motion",
        (900, 75),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (0, 255, 0),
        2
    )

    cv2.putText(
        display_frame,
        "RED   = Out of range",
        (900, 105),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.6,
        (0, 0, 255),
        2
    )


    # --------------------------------------------------------
    # QUIT
    # --------------------------------------------------------

    cv2.putText(
        display_frame,
        "Press Q to quit",
        (30, 690),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (200, 200, 200),
        1
    )


    # ========================================================
    # SHOW
    # ========================================================

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

print()
print("Live assessment stopped.")
print("Today's MVP is complete.")
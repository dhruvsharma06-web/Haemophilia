import os
import pandas as pd
import numpy as np


KEYPOINT_DIR = "processed_data/keypoints"
ANGLE_DIR = "processed_data/angles"

VISIBILITY_THRESHOLD = 0.5


def calculate_angle(a, b, c):
    a = np.array(a, dtype=float)
    b = np.array(b, dtype=float)
    c = np.array(c, dtype=float)

    ba = a - b
    bc = c - b

    denominator = np.linalg.norm(ba) * np.linalg.norm(bc)

    if denominator < 1e-8:
        return np.nan

    cosine_angle = np.dot(ba, bc) / denominator
    cosine_angle = np.clip(cosine_angle, -1.0, 1.0)

    return np.degrees(np.arccos(cosine_angle))


def process_file(filepath):

    df = pd.read_csv(filepath)

    rows = []

    for _, row in df.iterrows():

        # ====================================================
        # LANDMARKS
        # ====================================================

        left_hip = np.array([
            row["landmark_23_x"],
            row["landmark_23_y"]
        ])

        right_hip = np.array([
            row["landmark_24_x"],
            row["landmark_24_y"]
        ])

        left_shoulder = np.array([
            row["landmark_11_x"],
            row["landmark_11_y"]
        ])

        right_shoulder = np.array([
            row["landmark_12_x"],
            row["landmark_12_y"]
        ])

        left_elbow = np.array([
            row["landmark_13_x"],
            row["landmark_13_y"]
        ])

        right_elbow = np.array([
            row["landmark_14_x"],
            row["landmark_14_y"]
        ])

        # ====================================================
        # VISIBILITY
        # ====================================================

        left_vis = row["landmark_11_visibility"]
        right_vis = row["landmark_12_visibility"]

        # ====================================================
        # SHOULDER FLEXION ANGLES
        # ====================================================

        left_angle = calculate_angle(
            left_hip,
            left_shoulder,
            left_elbow
        )

        right_angle = calculate_angle(
            right_hip,
            right_shoulder,
            right_elbow
        )

        # ====================================================
        # TORSO CENTERS
        # ====================================================

        shoulder_mid = (
            left_shoulder + right_shoulder
        ) / 2.0

        hip_mid = (
            left_hip + right_hip
        ) / 2.0

        torso_dx = shoulder_mid[0] - hip_mid[0]
        torso_dy = shoulder_mid[1] - hip_mid[1]

        # ====================================================
        # 7. TORSO TILT
        #
        # Upright ≈ 0 degrees
        # Larger value = more body tilt
        # ====================================================

        torso_tilt = np.degrees(
            np.arctan2(
                abs(torso_dx),
                abs(torso_dy) + 1e-8
            )
        )

        # ====================================================
        # 8. TORSO ROTATION
        #
        # Uses 3D depth difference between shoulders,
        # normalized by shoulder width.
        # ====================================================

        left_shoulder_z = row["landmark_11_z"]
        right_shoulder_z = row["landmark_12_z"]

        shoulder_width = np.linalg.norm(
            right_shoulder - left_shoulder
        )

        if shoulder_width > 1e-8:
            torso_rotation = (
                right_shoulder_z -
                left_shoulder_z
            ) / shoulder_width
        else:
            torso_rotation = 0.0

        # ====================================================
        # 9. LEFT ARM TRAJECTORY
        #
        # Lateral elbow displacement relative to shoulder.
        # ====================================================

        torso_length = np.linalg.norm(
            shoulder_mid - hip_mid
        )

        if torso_length > 1e-8:

            left_arm_trajectory = (
                left_elbow[0] -
                left_shoulder[0]
            ) / torso_length

            right_arm_trajectory = (
                right_elbow[0] -
                right_shoulder[0]
            ) / torso_length

        else:

            left_arm_trajectory = 0.0
            right_arm_trajectory = 0.0

        # ====================================================
        # SAVE FRAME
        # ====================================================

        rows.append({

            "frame": row["frame"],

            "left_shoulder_angle": left_angle,
            "right_shoulder_angle": right_angle,

            "left_visibility": left_vis,
            "right_visibility": right_vis,

            "torso_tilt": torso_tilt,
            "torso_rotation": torso_rotation,

            "left_arm_trajectory":
                left_arm_trajectory,

            "right_arm_trajectory":
                right_arm_trajectory
        })

    output = pd.DataFrame(rows)

    # ========================================================
    # ANGULAR VELOCITY
    # ========================================================

    output["left_angular_velocity"] = (
        output["left_shoulder_angle"]
        .diff()
        .fillna(0)
    )

    output["right_angular_velocity"] = (
        output["right_shoulder_angle"]
        .diff()
        .fillna(0)
    )

    # ========================================================
    # FINAL COLUMN ORDER
    # ========================================================

    output = output[
        [
            "frame",

            "left_shoulder_angle",
            "right_shoulder_angle",

            "left_angular_velocity",
            "right_angular_velocity",

            "left_visibility",
            "right_visibility",

            "torso_tilt",
            "torso_rotation",

            "left_arm_trajectory",
            "right_arm_trajectory"
        ]
    ]

    # ========================================================
    # OUTPUT PATH
    # ========================================================

    filename = os.path.basename(filepath)

    name = os.path.splitext(filename)[0]

    name = name.replace(
        "_keypoints",
        ""
    )

    output_path = os.path.join(
        ANGLE_DIR,
        name + "_angles.csv"
    )

    os.makedirs(
        ANGLE_DIR,
        exist_ok=True
    )

    output.to_csv(
        output_path,
        index=False
    )

    print(f"Saved: {output_path}")


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    os.makedirs(
        ANGLE_DIR,
        exist_ok=True
    )

    files = [
        f
        for f in os.listdir(KEYPOINT_DIR)
        if f.endswith("_keypoints.csv")
    ]

    print(f"Found {len(files)} keypoint files.")

    for filename in files:

        filepath = os.path.join(
            KEYPOINT_DIR,
            filename
        )

        process_file(filepath)

    print("\nFeature extraction complete.")
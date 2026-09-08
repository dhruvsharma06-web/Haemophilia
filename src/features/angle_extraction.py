import pandas as pd
import numpy as np
import os
import sys


def calculate_angle(a, b, c):
    """
    Calculate angle ABC in degrees.
    a = first point
    b = vertex point
    c = third point
    """

    a = np.array(a, dtype=float)
    b = np.array(b, dtype=float)
    c = np.array(c, dtype=float)

    ba = a - b
    bc = c - b

    norm_ba = np.linalg.norm(ba)
    norm_bc = np.linalg.norm(bc)

    if norm_ba == 0 or norm_bc == 0:
        return np.nan

    cosine_angle = np.dot(ba, bc) / (norm_ba * norm_bc)

    cosine_angle = np.clip(cosine_angle, -1.0, 1.0)

    angle = np.degrees(np.arccos(cosine_angle))

    return angle


def extract_angles(keypoint_file):

    if not os.path.exists(keypoint_file):
        print(f"Keypoint file not found: {keypoint_file}")
        return

    filename = os.path.splitext(
        os.path.basename(keypoint_file)
    )[0]

    output_dir = "processed_data/angles"
    os.makedirs(output_dir, exist_ok=True)

    output_file = os.path.join(
        output_dir,
        filename.replace("_keypoints", "") + "_angles.csv"
    )

    df = pd.read_csv(keypoint_file)

    angle_rows = []

    for _, row in df.iterrows():

        # MediaPipe landmark numbers
        #
        # 11 = left shoulder
        # 12 = right shoulder
        # 13 = left elbow
        # 14 = right elbow
        # 23 = left hip
        # 24 = right hip

        left_hip = [
            row["landmark_23_x"],
            row["landmark_23_y"],
            row["landmark_23_z"]
        ]

        left_shoulder = [
            row["landmark_11_x"],
            row["landmark_11_y"],
            row["landmark_11_z"]
        ]

        left_elbow = [
            row["landmark_13_x"],
            row["landmark_13_y"],
            row["landmark_13_z"]
        ]

        right_hip = [
            row["landmark_24_x"],
            row["landmark_24_y"],
            row["landmark_24_z"]
        ]

        right_shoulder = [
            row["landmark_12_x"],
            row["landmark_12_y"],
            row["landmark_12_z"]
        ]

        right_elbow = [
            row["landmark_14_x"],
            row["landmark_14_y"],
            row["landmark_14_z"]
        ]

        # Check landmark visibility
        left_visibility = min(
            row["landmark_23_visibility"],
            row["landmark_11_visibility"],
            row["landmark_13_visibility"]
        )

        right_visibility = min(
            row["landmark_24_visibility"],
            row["landmark_12_visibility"],
            row["landmark_14_visibility"]
        )

        if left_visibility >= 0.5:
            left_angle = calculate_angle(
                left_hip,
                left_shoulder,
                left_elbow
            )
        else:
            left_angle = np.nan

        if right_visibility >= 0.5:
            right_angle = calculate_angle(
                right_hip,
                right_shoulder,
                right_elbow
            )
        else:
            right_angle = np.nan

        angle_rows.append({
            "frame": int(row["frame"]),
            "left_shoulder_angle": left_angle,
            "right_shoulder_angle": right_angle,
            "left_visibility": left_visibility,
            "right_visibility": right_visibility
        })

    angle_df = pd.DataFrame(angle_rows)

    angle_df.to_csv(
        output_file,
        index=False
    )

    print()
    print("Angle extraction completed!")
    print(f"Frames: {len(angle_df)}")
    print(f"Output: {output_file}")

    print()
    print("Left shoulder angle:")
    print(
        f"Min = {angle_df['left_shoulder_angle'].min():.2f}°"
    )
    print(
        f"Max = {angle_df['left_shoulder_angle'].max():.2f}°"
    )

    print()
    print("Right shoulder angle:")
    print(
        f"Min = {angle_df['right_shoulder_angle'].min():.2f}°"
    )
    print(
        f"Max = {angle_df['right_shoulder_angle'].max():.2f}°"
    )


if __name__ == "__main__":

    if len(sys.argv) < 2:

        print("Usage:")
        print(
            'python src\\features\\angle_extraction.py '
            '"path\\to\\keypoints.csv"'
        )

        sys.exit(1)

    extract_angles(sys.argv[1])
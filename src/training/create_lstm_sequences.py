import numpy as np
import pandas as pd
from pathlib import Path


SEQUENCE_LENGTH = 128

BASE_DIR = Path(__file__).resolve().parents[2]
ANGLES_DIR = BASE_DIR / "processed_data" / "angles"
OUTPUT_DIR = BASE_DIR / "processed_data" / "sequences"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def resize_sequence(values, length=128):
    values = np.asarray(values, dtype=np.float32)

    if len(values) < 2:
        return np.zeros(length, dtype=np.float32)

    old_positions = np.linspace(0, 1, len(values))
    new_positions = np.linspace(0, 1, length)

    return np.interp(
        new_positions,
        old_positions,
        values
    ).astype(np.float32)


def process_file(rep_file):

    video_id = rep_file.stem.replace("_reps", "")
    angle_file = ANGLES_DIR / f"{video_id}_angles.csv"

    if not angle_file.exists():
        print(f"Missing angle file: {angle_file}")
        return 0

    reps = pd.read_csv(rep_file)
    angles = pd.read_csv(angle_file)

    created = 0

    for _, rep in reps.iterrows():

        start_frame = int(rep["start_frame"])
        end_frame = int(rep["end_frame"])
        label = rep["label"]

        if label not in ["correct", "incorrect"]:
            continue

        rep_frames = angles[
            (angles["frame"] >= start_frame) &
            (angles["frame"] <= end_frame)
        ].copy()

        if len(rep_frames) < 5:
            continue

        # ====================================================
        # 1. RIGHT SHOULDER ANGLE
        # ====================================================

        right_angle = (
            rep_frames["right_shoulder_angle"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
        )

        # ====================================================
        # 2. LEFT SHOULDER ANGLE
        # ====================================================

        left_angle = (
            rep_frames["left_shoulder_angle"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
        )

        if right_angle.isna().all() or left_angle.isna().all():
            continue

        # ====================================================
        # 3. RIGHT ANGULAR VELOCITY
        # ====================================================

        right_velocity = (
            rep_frames["right_angular_velocity"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
            .values
        )

        # ====================================================
        # 4. LEFT ANGULAR VELOCITY
        # ====================================================

        left_velocity = (
            rep_frames["left_angular_velocity"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
            .values
        )

        # ====================================================
        # 5. RIGHT VISIBILITY
        # ====================================================

        right_visibility = (
            rep_frames["right_visibility"]
            .fillna(0.0)
            .values
        )

        # ====================================================
        # 6. LEFT VISIBILITY
        # ====================================================

        left_visibility = (
            rep_frames["left_visibility"]
            .fillna(0.0)
            .values
        )

        # ====================================================
        # 7. TORSO TILT
        # ====================================================

        torso_tilt = (
            rep_frames["torso_tilt"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
            .fillna(0.0)
            .values
        )

        # ====================================================
        # 8. TORSO ROTATION
        # ====================================================

        torso_rotation = (
            rep_frames["torso_rotation"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
            .fillna(0.0)
            .values
        )

        # ====================================================
        # 9. LEFT ARM TRAJECTORY
        # ====================================================

        left_arm_trajectory = (
            rep_frames["left_arm_trajectory"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
            .fillna(0.0)
            .values
        )

        # ====================================================
        # 10. RIGHT ARM TRAJECTORY
        # ====================================================

        right_arm_trajectory = (
            rep_frames["right_arm_trajectory"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
            .fillna(0.0)
            .values
        )

        # ====================================================
        # BUILD 10-FEATURE MATRIX
        # ====================================================

        sequence = np.column_stack([

            # 0
            right_angle.values,

            # 1
            left_angle.values,

            # 2
            right_velocity,

            # 3
            left_velocity,

            # 4
            right_visibility,

            # 5
            left_visibility,

            # 6
            torso_tilt,

            # 7
            torso_rotation,

            # 8
            left_arm_trajectory,

            # 9
            right_arm_trajectory
        ])

        # ====================================================
        # RESIZE TO 128 FRAMES
        # ====================================================

        resized = np.zeros(
            (SEQUENCE_LENGTH, 10),
            dtype=np.float32
        )

        for feature in range(10):

            resized[:, feature] = resize_sequence(
                sequence[:, feature],
                SEQUENCE_LENGTH
            )

        # ====================================================
        # NORMALIZATION
        # ====================================================

        # Shoulder angles: 0-180 degrees
        resized[:, 0] /= 180.0
        resized[:, 1] /= 180.0

        # Angular velocity
        resized[:, 2] /= 10.0
        resized[:, 3] /= 10.0

        # Visibility already approximately 0-1

        # Torso tilt: normalize 0-90 degrees
        resized[:, 6] /= 90.0

        # Torso rotation is a normalized depth ratio.
        # Keep as-is.

        # Arm trajectory is a normalized body-relative
        # horizontal displacement.
        # Keep as-is.

        # ====================================================
        # SAFETY: REMOVE NaN / INF
        # ====================================================

        resized = np.nan_to_num(
            resized,
            nan=0.0,
            posinf=1.0,
            neginf=-1.0
        )

        # ====================================================
        # SAVE
        # ====================================================

        rep_number = int(rep["rep"])

        output_file = OUTPUT_DIR / (
            f"{video_id}_rep_{rep_number}_{label}.npy"
        )

        np.save(
            output_file,
            resized
        )

        created += 1

    return created


def main():

    # ========================================================
    # REMOVE OLD SEQUENCES
    # ========================================================

    old_files = list(
        OUTPUT_DIR.glob("*.npy")
    )

    for file in old_files:
        file.unlink()

    print(
        f"Removed {len(old_files)} old sequence files."
    )

    # ========================================================
    # FIND REP FILES
    # ========================================================

    rep_files = sorted(
        ANGLES_DIR.glob("*_reps.csv")
    )

    if not rep_files:

        print(
            "No *_reps.csv files found."
        )

        return

    # ========================================================
    # CREATE SEQUENCES
    # ========================================================

    total = 0

    print("\n" + "=" * 60)
    print("CREATING 10-FEATURE LSTM SEQUENCES")
    print("=" * 60)

    for rep_file in rep_files:

        count = process_file(
            rep_file
        )

        print(
            f"{rep_file.name}: "
            f"{count} sequences created"
        )

        total += count

    # ========================================================
    # SUMMARY
    # ========================================================

    print("\n" + "=" * 60)
    print("SEQUENCE CREATION COMPLETE")
    print("=" * 60)

    print(
        f"Total sequences: {total}"
    )

    print(
        f"Sequence length: {SEQUENCE_LENGTH}"
    )

    print(
        "Features per frame: 10"
    )

    print("\nFeatures:")

    print(
        "1. Right shoulder angle"
    )

    print(
        "2. Left shoulder angle"
    )

    print(
        "3. Right angular velocity"
    )

    print(
        "4. Left angular velocity"
    )

    print(
        "5. Right visibility"
    )

    print(
        "6. Left visibility"
    )

    print(
        "7. Torso tilt"
    )

    print(
        "8. Torso rotation"
    )

    print(
        "9. Left arm trajectory"
    )

    print(
        "10. Right arm trajectory"
    )

    print(
        f"\nOutput directory:"
    )

    print(
        OUTPUT_DIR
    )


if __name__ == "__main__":
    main()
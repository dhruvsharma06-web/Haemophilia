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

        # Fill missing angles
        right_angle = (
            rep_frames["right_shoulder_angle"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
        )

        left_angle = (
            rep_frames["left_shoulder_angle"]
            .interpolate(limit_direction="both")
            .bfill()
            .ffill()
        )

        if right_angle.isna().all() or left_angle.isna().all():
            continue

        # Visibility
        right_visibility = (
            rep_frames["right_visibility"]
            .fillna(0.0)
            .values
        )

        left_visibility = (
            rep_frames["left_visibility"]
            .fillna(0.0)
            .values
        )

        # Angular velocity
        right_velocity = np.gradient(
            right_angle.values
        )

        left_velocity = np.gradient(
            left_angle.values
        )

        # Build feature matrix
        #
        # 0 = right angle
        # 1 = left angle
        # 2 = right angular velocity
        # 3 = left angular velocity
        # 4 = right visibility
        # 5 = left visibility

        sequence = np.column_stack([
            right_angle.values,
            left_angle.values,
            right_velocity,
            left_velocity,
            right_visibility,
            left_visibility
        ])

        # Resize to 128 frames
        resized = np.zeros(
            (SEQUENCE_LENGTH, 6),
            dtype=np.float32
        )

        for feature in range(6):
            resized[:, feature] = resize_sequence(
                sequence[:, feature],
                SEQUENCE_LENGTH
            )

        # Normalize angle features
        resized[:, 0] /= 180.0
        resized[:, 1] /= 180.0

        # Normalize angular velocity
        # Typical values are much smaller than angles.
        resized[:, 2] /= 10.0
        resized[:, 3] /= 10.0

        # Visibility is already approximately 0-1

        rep_number = int(rep["rep"])

        output_file = OUTPUT_DIR / (
            f"{video_id}_rep_{rep_number}_{label}.npy"
        )

        np.save(output_file, resized)

        created += 1

    return created


def main():

    # Remove old sequence files first
    old_files = list(OUTPUT_DIR.glob("*.npy"))

    for file in old_files:
        file.unlink()

    print(f"Removed {len(old_files)} old sequence files.")

    rep_files = sorted(
        ANGLES_DIR.glob("*_reps.csv")
    )

    if not rep_files:
        print("No *_reps.csv files found.")
        return

    total = 0

    print("\n" + "=" * 60)
    print("CREATING LSTM SEQUENCES")
    print("=" * 60)

    for rep_file in rep_files:

        count = process_file(rep_file)

        print(
            f"{rep_file.name}: "
            f"{count} sequences created"
        )

        total += count

    print("\n" + "=" * 60)
    print("SEQUENCE CREATION COMPLETE")
    print("=" * 60)

    print(f"Total sequences: {total}")
    print(f"Sequence length: {SEQUENCE_LENGTH}")
    print("Features per frame: 6")

    print("\nFeatures:")
    print("1. Right shoulder angle")
    print("2. Left shoulder angle")
    print("3. Right angular velocity")
    print("4. Left angular velocity")
    print("5. Right visibility")
    print("6. Left visibility")

    print(f"\nOutput directory:")
    print(OUTPUT_DIR)


if __name__ == "__main__":
    main()
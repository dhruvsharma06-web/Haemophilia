import sys
from pathlib import Path
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.exercises.shoulder_rotation import (
    REP_DIR,
    SMOOTHING_WINDOW,
    MIN_REP_DURATION,
    MIN_REP_FRAMES,
    MIN_ROTATION_EXCURSION_DEG
)


def smoothness(signal, t):
    if len(signal) < 5:
        return 0.0

    v = np.gradient(signal, t)
    a = np.gradient(v, t)

    scale = np.nanpercentile(np.abs(a), 90) + 1e-8

    return float(
        np.clip(
            1.0 / (1.0 + np.nanmean(np.abs(a)) / scale),
            0,
            1
        )
    )


def find_turning_points(signal):
    values = signal.to_numpy(float)
    points = []

    for i in range(1, len(values) - 1):

        if values[i] > values[i - 1] and values[i] >= values[i + 1]:
            points.append((i, "peak", values[i]))

        elif values[i] < values[i - 1] and values[i] <= values[i + 1]:
            points.append((i, "trough", values[i]))

    return points


def process_reps(feature_file: Path, label: str, subject_id: str):

    df = pd.read_csv(feature_file)

    right = df["right_rotation_angle"].interpolate(
        limit_direction="both"
    )

    left = df["left_rotation_angle"].interpolate(
        limit_direction="both"
    )

    # Preserve rotation direction instead of using absolute distance
    signal = (right + left) / 2.0

    signal = signal.rolling(
        SMOOTHING_WINDOW,
        center=True,
        min_periods=1
    ).mean()

    points = find_turning_points(signal)

    # Remove very small alternating movements
    filtered = []

    for point in points:

        if not filtered:
            filtered.append(point)
            continue

        prev = filtered[-1]

        if point[1] == prev[1]:

            if point[1] == "peak" and point[2] > prev[2]:
                filtered[-1] = point

            elif point[1] == "trough" and point[2] < prev[2]:
                filtered[-1] = point

            continue

        excursion = abs(point[2] - prev[2])

        if excursion >= MIN_ROTATION_EXCURSION_DEG:
            filtered.append(point)

    reps = []

    # Three alternating extremes form one complete cycle:
    # peak -> trough -> peak
    # or trough -> peak -> trough
    i = 0

    while i + 2 < len(filtered):

        p1 = filtered[i]
        p2 = filtered[i + 1]
        p3 = filtered[i + 2]

        valid_cycle = (
            p1[1] == p3[1] and
            p1[1] != p2[1]
        )

        if not valid_cycle:
            i += 1
            continue

        start = p1[0]
        end = p3[0]

        if end - start < MIN_REP_FRAMES:
            i += 2
            continue

        seg = df.iloc[start:end + 1]

        duration = float(
            seg["time_sec"].iloc[-1] -
            seg["time_sec"].iloc[0]
        )

        if duration < MIN_REP_DURATION:
            i += 2
            continue

        rr = float(
            seg["right_rotation_angle"].max() -
            seg["right_rotation_angle"].min()
        )

        lr = float(
            seg["left_rotation_angle"].max() -
            seg["left_rotation_angle"].min()
        )

        tt = seg["time_sec"].to_numpy(float)
        sig = signal.iloc[start:end + 1].to_numpy(float)

        rom = (rr + lr) / 2.0

        reps.append({
            "rep": len(reps) + 1,
            "start_frame": int(seg["frame"].iloc[0]),
            "end_frame": int(seg["frame"].iloc[-1]),
            "label": label,
            "subject_id": subject_id,
            "right_rom": rr,
            "left_rom": lr,
            "range_of_motion": float(rom),
            "duration": duration,
            "speed_deg_per_sec": float(
                rom / (duration + 1e-8)
            ),
            "smoothness": smoothness(sig, tt),
            "max_torso_tilt": float(
                seg["torso_tilt"].abs().max()
            ),
            "max_torso_rotation": float(
                seg["torso_rotation"].abs().max()
            ),
            "max_right_elbow_drift": float(
                seg["right_elbow_drift"].max()
            ),
            "max_left_elbow_drift": float(
                seg["left_elbow_drift"].max()
            )
        })

        # Move to the next full cycle
        i += 2

    REP_DIR.mkdir(parents=True, exist_ok=True)

    out = REP_DIR / (
        f"{Path(feature_file).stem.replace('_features', '')}_reps.csv"
    )

    pd.DataFrame(reps).to_csv(out, index=False)

    print(
        f"Reps: {len(reps)} -> {out} "
        f"(turning points: {len(filtered)})"
    )

    return out


if __name__ == "__main__":

    if len(sys.argv) != 4:
        raise SystemExit(
            "Usage: python "
            "src/feedback/shoulder_rotation_rep_counter.py "
            "<features.csv> <correct|incorrect> <subject_id>"
        )

    process_reps(
        Path(sys.argv[1]),
        sys.argv[2],
        sys.argv[3]
    )
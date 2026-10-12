import sys
from pathlib import Path
import numpy as np
import pandas as pd

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))
from src.exercises.shoulder_rotation import FEATURE_DIR


def angle3(a, b, c):
    a, b, c = map(lambda x: np.asarray(x, dtype=float), (a, b, c))
    ba, bc = a - b, c - b
    den = np.linalg.norm(ba) * np.linalg.norm(bc)
    if den < 1e-8:
        return np.nan
    return float(np.degrees(np.arccos(np.clip(np.dot(ba, bc) / den, -1, 1))))


def forearm_rotation_angle(elbow, wrist):
    """3-D forearm azimuth in the MediaPipe x-z plane, degrees in [-180, 180].

    This is a camera-relative movement signal, not a direct clinical goniometric
    internal/external rotation measurement.
    """
    v = np.asarray(wrist, float) - np.asarray(elbow, float)
    if np.linalg.norm(v[[0, 2]]) < 1e-8:
        return np.nan
    return float(np.degrees(np.arctan2(v[0], -v[2])))


def _p(row, idx):
    return np.array([row[f"landmark_{idx}_x"], row[f"landmark_{idx}_y"], row[f"landmark_{idx}_z"]], float)


def process_file(keypoint_file: Path):
    # CSV tooling follows the same observed-frame features as the live engine.
    # Do not interpolate missing poses across a tracking gap.
    from types import SimpleNamespace
    from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment
    from src.exercises.shoulder_rotation import FEATURE_NAMES
    engine = ShoulderRotationAssessment(None, "cpu", save_artifacts=False)
    df = pd.read_csv(keypoint_file)
    rows = []
    previous_time = None
    for _, row in df.iterrows():
        time = float(row.get("time_sec", 0))
        landmarks = SimpleNamespace(landmark=[SimpleNamespace(
            x=float(row[f"landmark_{i}_x"]), y=float(row[f"landmark_{i}_y"]),
            z=float(row[f"landmark_{i}_z"]), visibility=float(row[f"landmark_{i}_visibility"]))
            for i in range(33)])
        good = all(np.isfinite([lm.x, lm.y, lm.z, lm.visibility]).all() and lm.visibility >= .5
                   for lm in [landmarks.landmark[i] for i in [11,12,13,14,15,16,23,24]])
        engine.dt = time - previous_time if previous_time is not None and time > previous_time else 1 / 20
        feature = engine._extract_feature(landmarks) if good else np.full(14, np.nan)
        if not np.isfinite(feature).all():
            engine.reset_incomplete_rep()
            feature = np.full(14, np.nan)
        rows.append({"frame": int(row["frame"]), "time_sec": time,
                     "fps": float(row.get("fps", 20)),
                     **dict(zip(FEATURE_NAMES + ["right_hand_displacement", "left_hand_displacement",
                                                "right_upper_arm_offset", "left_upper_arm_offset"], feature))})
        previous_time = time if np.isfinite(feature).all() else None
    FEATURE_DIR.mkdir(parents=True, exist_ok=True)
    output = FEATURE_DIR / f"{Path(keypoint_file).stem.replace('_keypoints', '')}_features.csv"
    pd.DataFrame(rows).to_csv(output, index=False)
    return output


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python src/features/shoulder_rotation_features.py <keypoints.csv>")
    process_file(Path(sys.argv[1]))

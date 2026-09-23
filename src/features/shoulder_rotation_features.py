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
    keypoint_file = Path(keypoint_file)
    df = pd.read_csv(keypoint_file)
    rows = []
    for _, r in df.iterrows():
        ls, rs, le, re, lw, rw, lh, rh = (_p(r, i) for i in [11,12,13,14,15,16,23,24])
        shoulder_mid = (ls + rs) / 2
        hip_mid = (lh + rh) / 2
        torso = shoulder_mid - hip_mid
        torso_tilt = np.degrees(np.arctan2(abs(torso[0]), abs(torso[1]) + 1e-8))
        shoulder_width_xy = np.linalg.norm((rs-ls)[:2])
        torso_rotation = (rs[2]-ls[2]) / (shoulder_width_xy + 1e-8)
        torso_len = np.linalg.norm((shoulder_mid-hip_mid)[:2]) + 1e-8
        rows.append({
            "frame": int(r["frame"]), "time_sec": float(r.get("time_sec", 0.0)), "fps": float(r.get("fps", 30.0)),
            "right_rotation_angle": forearm_rotation_angle(re, rw),
            "left_rotation_angle": forearm_rotation_angle(le, lw),
            "right_elbow_angle": angle3(rs, re, rw),
            "left_elbow_angle": angle3(ls, le, lw),
            "right_visibility": min(r["landmark_12_visibility"], r["landmark_14_visibility"], r["landmark_16_visibility"]),
            "left_visibility": min(r["landmark_11_visibility"], r["landmark_13_visibility"], r["landmark_15_visibility"]),
            "torso_tilt": torso_tilt, "torso_rotation": torso_rotation,
            "right_elbow_drift": np.linalg.norm((re-rs)[:2]) / torso_len,
            "left_elbow_drift": np.linalg.norm((le-ls)[:2]) / torso_len,
        })
    out = pd.DataFrame(rows)
    # unwrap circular angle before derivative
    for side in ["right", "left"]:
        col = f"{side}_rotation_angle"
        vals = out[col].interpolate(limit_direction="both").to_numpy(float)
        vals = np.degrees(np.unwrap(np.radians(vals)))
        out[col] = vals
        t = out["time_sec"].to_numpy(float)
        if len(t) > 1 and np.all(np.diff(t) > 0):
            out[f"{side}_angular_velocity"] = np.gradient(vals, t)
        else:
            fps = float(out["fps"].replace(0, np.nan).median() or 30.0)
            out[f"{side}_angular_velocity"] = np.gradient(vals) * fps
    FEATURE_DIR.mkdir(parents=True, exist_ok=True)
    output = FEATURE_DIR / f"{keypoint_file.stem.replace('_keypoints','')}_features.csv"
    out.to_csv(output, index=False)
    print(f"Feature CSV: {output}")
    return output


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python src/features/shoulder_rotation_features.py <keypoints.csv>")
    process_file(Path(sys.argv[1]))

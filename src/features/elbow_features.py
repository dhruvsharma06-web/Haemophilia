import numpy as np

INPUT_SIZE = 8
SHOULDER = 12
ELBOW = 14
WRIST = 16


def resample(seq, target_len=128):
    idx = np.linspace(0, len(seq) - 1, target_len).astype(int)
    return seq[idx]


def build_features(rows, fps=30.0, angle_series=None):
    if angle_series is None:
        angle_series = np.array([elbow_angle(row) for row in rows], dtype=np.float32)
    else:
        angle_series = np.array(angle_series, dtype=np.float32)

    if len(angle_series) < 5:
        return np.zeros((128, INPUT_SIZE), dtype=np.float32), angle_series

    # -------------------------
    # 🔥 RAW SIGNAL
    # -------------------------
    raw_angle = angle_series.copy()

    # -------------------------
    # 🔥 NORMALIZED SHAPE
    # -------------------------
    min_a = np.min(angle_series)
    max_a = np.max(angle_series)
    norm_angle = (angle_series - min_a) / (max_a - min_a + 1e-6)

    # -------------------------
    # 🔥 DERIVATIVES
    # -------------------------
    vel = np.diff(raw_angle, prepend=raw_angle[0])
    acc = np.diff(vel, prepend=vel[0])

    # -------------------------
    # 🔥 SHAPE FEATURES (VERY IMPORTANT)
    # -------------------------
    peak = np.max(raw_angle)
    valley = np.min(raw_angle)

    range_motion = peak - valley
    duration = len(raw_angle) / max(fps, 1.0)

    # 🔥 symmetry (correct reps are smoother)
    half = len(raw_angle) // 2
    first = raw_angle[:half]
    second = raw_angle[-half:][::-1]

    if len(first) == len(second) and len(first) > 0:
        symmetry = np.mean(np.abs(first - second))
    else:
        symmetry = 0.0

    # -------------------------
    # 🔥 RESAMPLE
    # -------------------------
    raw_angle = resample(raw_angle)
    norm_angle = resample(norm_angle)
    vel = resample(vel)
    acc = resample(acc)

    # -------------------------
    # 🔥 GLOBAL FEATURES (broadcast)
    # -------------------------
    range_norm = np.full(128, range_motion / 100)
    duration_norm = np.full(128, duration / 5)
    symmetry_norm = np.full(128, symmetry / 50)
    peak_norm = np.full(128, peak / 180)

    # -------------------------
    # 🔥 FINAL FEATURES (8 STRONG SIGNALS)
    # -------------------------
    features = np.column_stack([
        raw_angle / 180,     # 🔥 absolute info
        norm_angle,          # shape
        vel / 50,            # motion speed
        acc / 50,            # smoothness
        range_norm,          # full ROM
        duration_norm,       # control
        symmetry_norm,       # smooth rep
        peak_norm            # extension quality
    ])

    return features.astype(np.float32), angle_series


def elbow_angle(landmarks) -> float:
    """Compute joint angle from relative 3D vectors."""
    shoulder = _point(landmarks, SHOULDER)
    elbow = _point(landmarks, ELBOW)
    wrist = _point(landmarks, WRIST)
    first = shoulder - elbow
    second = wrist - elbow
    denominator = np.linalg.norm(first) * np.linalg.norm(second)
    if denominator <= 1e-6:
        return 0.0
    cosine = np.clip(np.dot(first, second) / denominator, -1.0, 1.0)
    return float(np.degrees(np.arccos(cosine)))


def smooth_angles(angles: np.ndarray, window: int = 5) -> np.ndarray:
    angles = np.asarray(angles, dtype=np.float32)
    if len(angles) < 2 or window <= 1:
        return angles
    window = min(window, len(angles) if len(angles) % 2 else len(angles) - 1)
    if window < 2:
        return angles
    kernel = np.ones(window, dtype=np.float32) / window
    padded = np.pad(angles, (window // 2, window // 2), mode="edge")
    return np.convolve(padded, kernel, mode="valid").astype(np.float32)


def filter_angle_outliers(angles: np.ndarray, max_jump: float = 30.0) -> np.ndarray:
    angles = np.asarray(angles, dtype=np.float32).copy()
    if len(angles) < 3:
        return angles
    median = smooth_angles(angles, window=3)
    spikes = np.abs(angles - median) > max_jump
    angles[spikes] = median[spikes]
    return angles


def _point(row, index: int) -> np.ndarray:
    if isinstance(row, dict):
        return np.asarray(
            [row.get(f"landmark_{index}_{axis}", 0.0) for axis in ("x", "y", "z")],
            dtype=np.float32,
        )
    return np.zeros(3, dtype=np.float32)

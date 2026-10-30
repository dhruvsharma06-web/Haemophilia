"""
Biomechanical feature extractor for live repetition assessment.
Faithfully mirrors the seniors' feature engineering pipeline:
- common_features.py (geometry, 2D/3D angles, segment lengths, velocities)
- exercise_extractors/*.py (per-exercise landmark filtering and derived metrics)
- aggregate_features.py (min, max, mean, std, range, first, last aggregations)
"""
from typing import Any, Dict, List, Optional
import numpy as np
import pandas as pd

from src.exercises.lower_body.geometry import get_coord

LEAK_COLS = {
    "frame",
    "timestamp_ms",
    "person_id",
    "phase_normalized",
}


def landmarks_to_dataframe(landmark_frames: List[Any], fps: float = 20.0) -> pd.DataFrame:
    """Convert sequence of MediaPipe landmark frames into raw DataFrame format."""
    records = []
    dt_ms = 1000.0 / max(fps, 1.0)
    for f_idx, pose_landmarks in enumerate(landmark_frames):
        rec = {
            "frame": f_idx,
            "timestamp_ms": int(f_idx * dt_ms),
            "person_id": 0,
        }
        lms_list = []
        if hasattr(pose_landmarks, "landmark"):
            lms_list = pose_landmarks.landmark
        elif isinstance(pose_landmarks, (list, tuple)):
            lms_list = pose_landmarks

        for i in range(33):
            if i < len(lms_list):
                x, y, z, vis = get_coord(lms_list[i])
                rec[f"lm{i}_x"] = x
                rec[f"lm{i}_y"] = y
                rec[f"lm{i}_z"] = z
                rec[f"lm{i}_visibility"] = vis
                rec[f"lm{i}_presence"] = getattr(lms_list[i], "presence", 1.0)
            else:
                rec[f"lm{i}_x"] = 0.0
                rec[f"lm{i}_y"] = 0.0
                rec[f"lm{i}_z"] = 0.0
                rec[f"lm{i}_visibility"] = 0.0
                rec[f"lm{i}_presence"] = 0.0
        records.append(rec)
    return pd.DataFrame(records)


def p3(df: pd.DataFrame, lm_id: int) -> np.ndarray:
    return df[[f"lm{lm_id}_x", f"lm{lm_id}_y", f"lm{lm_id}_z"]].astype(float).to_numpy()


def p2(df: pd.DataFrame, lm_id: int) -> np.ndarray:
    return df[[f"lm{lm_id}_x", f"lm{lm_id}_y"]].astype(float).to_numpy()


def add_angle_2d(out: dict, df: pd.DataFrame, a_id: int, vertex_id: int, c_id: int, name: str) -> None:
    a = p2(df, a_id)
    b = p2(df, vertex_id)
    c = p2(df, c_id)
    ba = a - b
    bc = c - b
    ba_n = np.linalg.norm(ba, axis=1)
    bc_n = np.linalg.norm(bc, axis=1)
    denom = ba_n * bc_n
    valid = denom > 1e-9
    cosine = np.full(len(df), np.nan)
    cosine[valid] = np.sum(ba[valid] * bc[valid], axis=1) / denom[valid]
    cosine = np.clip(cosine, -1.0, 1.0)
    angle = np.full(len(df), np.nan)
    angle[valid] = np.degrees(np.arccos(cosine[valid]))
    out[name] = angle


def add_angle_3d(out: dict, df: pd.DataFrame, a_id: int, vertex_id: int, c_id: int, name: str) -> None:
    a = p3(df, a_id)
    b = p3(df, vertex_id)
    c = p3(df, c_id)
    ba = a - b
    bc = c - b
    ba_n = np.linalg.norm(ba, axis=1)
    bc_n = np.linalg.norm(bc, axis=1)
    denom = ba_n * bc_n
    valid = denom > 1e-9
    cosine = np.full(len(df), np.nan)
    cosine[valid] = np.sum(ba[valid] * bc[valid], axis=1) / denom[valid]
    cosine = np.clip(cosine, -1.0, 1.0)
    angle = np.full(len(df), np.nan)
    angle[valid] = np.degrees(np.arccos(cosine[valid]))
    out[name] = angle


def add_distance_3d(out: dict, df: pd.DataFrame, a_id: int, b_id: int, name: str) -> None:
    d = p3(df, a_id) - p3(df, b_id)
    out[name] = np.linalg.norm(d, axis=1)


def derivative(values: np.ndarray, time_s: np.ndarray) -> np.ndarray:
    if len(values) < 2:
        return np.full(len(values), np.nan)
    dt = np.gradient(time_s)
    dt = np.where(dt > 1e-6, dt, np.nan)
    return np.gradient(values) / dt


def add_derivative_features(out: dict, time_s: np.ndarray, source_name: str, values: np.ndarray, acceleration: bool = True) -> None:
    vel = derivative(values, time_s)
    out[f"{source_name}_velocity"] = vel
    if acceleration:
        out[f"{source_name}_acceleration"] = derivative(vel, time_s)


def extract_common_features(df: pd.DataFrame) -> pd.DataFrame:
    """Extract standard biomechanical features as defined in Physio-Project common_features.py."""
    out: Dict[str, Any] = {}
    out["frame"] = df["frame"].to_numpy()
    out["timestamp_ms"] = df["timestamp_ms"].to_numpy()
    out["person_id"] = df["person_id"].to_numpy()

    time_s = df["timestamp_ms"].astype(float).to_numpy() / 1000.0
    if len(df) <= 1:
        phase = np.zeros(len(df))
    else:
        t0 = float(time_s[0])
        t1 = float(time_s[-1])
        phase = np.linspace(0.0, 1.0, len(df)) if t1 <= t0 else (time_s - t0) / (t1 - t0)
    out["phase_normalized"] = phase

    vis_cols = [f"lm{i}_visibility" for i in range(33) if f"lm{i}_visibility" in df.columns]
    pres_cols = [f"lm{i}_presence" for i in range(33) if f"lm{i}_presence" in df.columns]

    if vis_cols:
        vis = df[vis_cols].astype(float)
        out["mean_landmark_visibility"] = vis.mean(axis=1).to_numpy()
        out["min_landmark_visibility"] = vis.min(axis=1).to_numpy()
        out["low_visibility_landmark_count"] = (vis < 0.5).sum(axis=1).to_numpy()

    if pres_cols:
        pres = df[pres_cols].astype(float)
        out["mean_landmark_presence"] = pres.mean(axis=1).to_numpy()
        out["min_landmark_presence"] = pres.min(axis=1).to_numpy()

    shoulder_center = (p3(df, 11) + p3(df, 12)) / 2.0
    pelvis_center = (p3(df, 23) + p3(df, 24)) / 2.0

    out["pelvis_center_x"] = pelvis_center[:, 0]
    out["pelvis_center_y"] = pelvis_center[:, 1]
    out["pelvis_center_z"] = pelvis_center[:, 2]

    out["shoulder_center_x"] = shoulder_center[:, 0]
    out["shoulder_center_y"] = shoulder_center[:, 1]
    out["shoulder_center_z"] = shoulder_center[:, 2]

    torso_vec = shoulder_center - pelvis_center
    torso_length = np.linalg.norm(torso_vec, axis=1)
    hip_vec = p3(df, 23) - p3(df, 24)
    hip_width = np.linalg.norm(hip_vec, axis=1)

    body_scale = np.sqrt(np.square(torso_length) + np.square(hip_width))
    body_scale = np.where(body_scale > 1e-6, body_scale, np.nan)

    out["torso_length_3d"] = torso_length
    out["hip_width_3d"] = hip_width
    out["body_scale"] = body_scale

    body_landmarks = {
        "nose": 0, "left_shoulder": 11, "right_shoulder": 12, "left_elbow": 13, "right_elbow": 14,
        "left_wrist": 15, "right_wrist": 16, "left_hip": 23, "right_hip": 24, "left_knee": 25,
        "right_knee": 26, "left_ankle": 27, "right_ankle": 28, "left_heel": 29, "right_heel": 30,
        "left_foot_index": 31, "right_foot_index": 32,
    }

    for name, lm_id in body_landmarks.items():
        rel = (p3(df, lm_id) - pelvis_center) / body_scale[:, None]
        out[f"{name}_rel_x"] = rel[:, 0]
        out[f"{name}_rel_y"] = rel[:, 1]
        out[f"{name}_rel_z"] = rel[:, 2]

    angle_2d_specs = {
        "left_elbow_angle_2d": (11, 13, 15), "right_elbow_angle_2d": (12, 14, 16),
        "left_shoulder_angle_2d": (13, 11, 23), "right_shoulder_angle_2d": (14, 12, 24),
        "left_knee_angle_2d": (23, 25, 27), "right_knee_angle_2d": (24, 26, 28),
        "left_hip_angle_2d": (11, 23, 25), "right_hip_angle_2d": (12, 24, 26),
        "left_ankle_angle_2d": (25, 27, 29), "right_ankle_angle_2d": (26, 28, 30),
        "trunk_left_angle_2d": (11, 23, 24), "trunk_right_angle_2d": (12, 24, 23),
    }
    for name, (a, b, c) in angle_2d_specs.items():
        add_angle_2d(out, df, a, b, c, name)

    angle_3d_specs = {
        "left_elbow_angle_3d": (11, 13, 15), "right_elbow_angle_3d": (12, 14, 16),
        "left_shoulder_angle_3d": (13, 11, 23), "right_shoulder_angle_3d": (14, 12, 24),
        "left_knee_angle_3d": (23, 25, 27), "right_knee_angle_3d": (24, 26, 28),
        "left_hip_angle_3d": (11, 23, 25), "right_hip_angle_3d": (12, 24, 26),
        "left_ankle_angle_3d": (25, 27, 29), "right_ankle_angle_3d": (26, 28, 30),
    }
    for name, (a, b, c) in angle_3d_specs.items():
        add_angle_3d(out, df, a, b, c, name)

    distance_specs = {
        "left_upper_arm_length_3d": (11, 13), "right_upper_arm_length_3d": (12, 14),
        "left_forearm_length_3d": (13, 15), "right_forearm_length_3d": (14, 16),
        "left_thigh_length_3d": (23, 25), "right_thigh_length_3d": (24, 26),
        "left_shank_length_3d": (25, 27), "right_shank_length_3d": (26, 28),
        "shoulder_width_3d": (11, 12),
    }
    for name, (a, b) in distance_specs.items():
        add_distance_3d(out, df, a, b, name)

    motion_points = {
        "left_elbow": p3(df, 13), "right_elbow": p3(df, 14),
        "left_wrist": p3(df, 15), "right_wrist": p3(df, 16),
        "pelvis_center": pelvis_center,
        "left_knee": p3(df, 25), "right_knee": p3(df, 26),
        "left_ankle": p3(df, 27), "right_ankle": p3(df, 28),
        "left_heel": p3(df, 29), "right_heel": p3(df, 30),
    }
    for name, points in motion_points.items():
        for i, axis in enumerate(("x", "y", "z")):
            add_derivative_features(out, time_s, f"{name}_{axis}", points[:, i], acceleration=False)
        vx = out[f"{name}_x_velocity"]
        vy = out[f"{name}_y_velocity"]
        vz = out[f"{name}_z_velocity"]
        out[f"{name}_speed"] = np.sqrt(np.square(vx) + np.square(vy) + np.square(vz))

    for name in (
        "left_elbow_angle_2d", "right_elbow_angle_2d", "left_shoulder_angle_2d", "right_shoulder_angle_2d",
        "left_knee_angle_2d", "right_knee_angle_2d", "left_hip_angle_2d", "right_hip_angle_2d",
        "left_ankle_angle_2d", "right_ankle_angle_2d",
    ):
        add_derivative_features(out, time_s, name, np.asarray(out[name], dtype=float), acceleration=False)

    return pd.DataFrame(out)


def extract_repetition_features(exercise_name: str, landmark_frames: List[Any], fps: float = 20.0) -> Dict[str, float]:
    """
    Extract aggregated features from a repetition's landmark sequence.
    Applies exercise-specific column filtering and generates (min, max, mean, std, range, first, last).
    """
    if not landmark_frames or len(landmark_frames) < 2:
        return {}

    raw_df = landmarks_to_dataframe(landmark_frames, fps=fps)
    feats = extract_common_features(raw_df)

    # Exercise-specific adaptations
    if exercise_name == "mini_squat":
        drop_prefixes = ("nose_", "left_wrist_", "right_wrist_")
        selected = [c for c in feats.columns if not c.startswith(drop_prefixes)]
        out_df = feats[selected].copy()
        if "left_ankle_rel_x" in out_df and "right_ankle_rel_x" in out_df:
            dx = out_df["left_ankle_rel_x"] - out_df["right_ankle_rel_x"]
            dy = out_df["left_ankle_rel_y"] - out_df["right_ankle_rel_y"]
            dz = out_df["left_ankle_rel_z"] - out_df["right_ankle_rel_z"]
            out_df["ankle_width_3d"] = np.sqrt(dx**2 + dy**2 + dz**2)

    elif exercise_name == "seated_knee_extension":
        out_df = feats.copy()
        out_df["baseline"] = float(out_df["pelvis_center_y"].mean()) if "pelvis_center_y" in out_df else 0.0
        if "nose_rel_x" in out_df and "shoulder_center_x" in out_df:
            head_x = out_df["nose_rel_x"] + out_df["shoulder_center_x"]
            out_df["rocking_score"] = float(head_x.std())
        else:
            out_df["rocking_score"] = 0.0

    elif exercise_name == "straight_leg_raise":
        drop_prefixes = ("left_wrist_", "right_wrist_")
        selected = [c for c in feats.columns if not c.startswith(drop_prefixes)]
        out_df = feats[selected].copy()

    else:
        out_df = feats.copy()

    # Aggregate columns
    num = out_df.select_dtypes(include=[np.number])
    num = num.drop(columns=[c for c in LEAK_COLS if c in num.columns], errors="ignore")

    aggregated: Dict[str, float] = {}
    for col in num.columns:
        s = num[col]
        s_clean = s.dropna()
        if len(s_clean) == 0:
            continue
        aggregated[f"{col}__min"] = float(s_clean.min())
        aggregated[f"{col}__max"] = float(s_clean.max())
        aggregated[f"{col}__mean"] = float(s_clean.mean())
        aggregated[f"{col}__std"] = float(s_clean.std()) if len(s_clean) > 1 else 0.0
        aggregated[f"{col}__range"] = float(s_clean.max() - s_clean.min())
        aggregated[f"{col}__first"] = float(s_clean.iloc[0])
        aggregated[f"{col}__last"] = float(s_clean.iloc[-1])

    return aggregated

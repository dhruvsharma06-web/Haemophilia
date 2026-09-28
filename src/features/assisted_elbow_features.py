"""Assisted elbow flexion feature extraction.

Constructs an arm-invariant 10-feature representation focused on movement
correctness rather than side identity (left vs. right).
"""

from typing import Dict, List, Optional, Tuple
import numpy as np


FEATURE_NAMES = [
    "active_elbow_angle",
    "assisting_elbow_angle",
    "active_elbow_velocity",
    "assisting_elbow_velocity",
    "torso_tilt",
    "torso_rotation",
    "active_elbow_flare",
    "assisting_elbow_flare",
]

# Normalization constants empirically calibrated on Persons 1 and 2
NORM_CONSTANTS = {
    "angle_divisor": 180.0,
    "velocity_divisor": 8.0,
    "tilt_divisor": 3.0,  # Empirical engineering scaling: training P95 ~ 1.59°, max ~ 4.67°
    "clip_velocity": 1.5,
    "clip_flare": 1.5,
    "clip_rotation": 1.5,
}


def compute_angle_3d(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Compute the 3D angle at vertex b between vectors (a - b) and (c - b) in degrees."""
    ba = a - b
    bc = c - b
    norm_ba = np.linalg.norm(ba)
    norm_bc = np.linalg.norm(bc)
    if norm_ba < 1e-6 or norm_bc < 1e-6:
        return 0.0
    cosine = np.clip(np.dot(ba, bc) / (norm_ba * norm_bc), -1.0, 1.0)
    return float(np.degrees(np.arccos(cosine)))


def extract_frame_kinematics(
    landmarks,
    ref_shoulder_width: Optional[float] = None,
) -> Dict[str, float]:
    """Extract raw angles, visibilities, posture, and flare metrics from 33 pose landmarks.
    
    Uses robust anatomical reference shoulder width across the video to avoid
    momentary landmark collapse artifact spikes.
    """
    lm = landmarks if hasattr(landmarks, "__getitem__") else landmarks.landmark

    # Landmark coordinates
    ls = np.array([lm[11].x, lm[11].y, lm[11].z], dtype=np.float32)
    rs = np.array([lm[12].x, lm[12].y, lm[12].z], dtype=np.float32)
    le = np.array([lm[13].x, lm[13].y, lm[13].z], dtype=np.float32)
    re = np.array([lm[14].x, lm[14].y, lm[14].z], dtype=np.float32)
    lw = np.array([lm[15].x, lm[15].y, lm[15].z], dtype=np.float32)
    rw = np.array([lm[16].x, lm[16].y, lm[16].z], dtype=np.float32)
    lh = np.array([lm[23].x, lm[23].y, lm[23].z], dtype=np.float32)
    rh = np.array([lm[24].x, lm[24].y, lm[24].z], dtype=np.float32)

    # Elbow joint angles (shoulder -> elbow -> wrist)
    left_angle = compute_angle_3d(ls, le, lw)
    right_angle = compute_angle_3d(rs, re, rw)

    # Arm visibilities (for quality control and tracking loss detection)
    left_vis = float((lm[11].visibility + lm[13].visibility + lm[15].visibility) / 3.0)
    right_vis = float((lm[12].visibility + lm[14].visibility + lm[16].visibility) / 3.0)

    # Torso tilt
    sx, sy = (ls[0] + rs[0]) / 2.0, (ls[1] + rs[1]) / 2.0
    hx, hy = (lh[0] + rh[0]) / 2.0, (lh[1] + rh[1]) / 2.0
    torso_tilt = float(np.degrees(np.arctan2(abs(sx - hx), abs(sy - hy) + 1e-6)))

    # Robust shoulder width normalization
    inst_sw = float(np.sqrt((rs[0] - ls[0]) ** 2 + (rs[1] - ls[1]) ** 2))
    if ref_shoulder_width is not None and ref_shoulder_width > 0.05:
        shoulder_width = ref_shoulder_width
        fallback_used = bool(inst_sw < (0.5 * ref_shoulder_width))
    else:
        shoulder_width = max(inst_sw, 0.10)
        fallback_used = bool(inst_sw < 0.10)

    torso_rotation = float((rs[2] - ls[2]) / shoulder_width)

    # Elbow flare (lateral displacement of elbow relative to shoulder)
    left_flare = float(abs(le[0] - ls[0]) / shoulder_width)
    right_flare = float(abs(re[0] - rs[0]) / shoulder_width)

    return {
        "left_angle": left_angle,
        "right_angle": right_angle,
        "left_vis": left_vis,
        "right_vis": right_vis,
        "torso_tilt": torso_tilt,
        "torso_rotation": torso_rotation,
        "left_flare": left_flare,
        "right_flare": right_flare,
        "instantaneous_sw": inst_sw,
        "fallback_used": 1.0 if fallback_used else 0.0,
    }


def map_canonical_features(
    raw: Dict[str, float],
    assistance_type: str = "both_hand_assisted",
) -> Dict[str, float]:
    """Map raw left/right metrics to canonical active vs. assisting arm semantics."""
    asst_norm = assistance_type.lower().strip()

    if "right" in asst_norm:
        # Right hand assisted: right arm is active exercising arm
        return {
            "active_elbow_angle": raw["right_angle"],
            "assisting_elbow_angle": raw["left_angle"],
            "active_arm_visibility": raw["right_vis"],
            "assisting_arm_visibility": raw["left_vis"],
            "torso_tilt": raw["torso_tilt"],
            "torso_rotation": raw["torso_rotation"],
            "active_elbow_flare": raw["right_flare"],
            "assisting_elbow_flare": raw["left_flare"],
            "fallback_used": raw.get("fallback_used", 0.0),
        }
    elif "left" in asst_norm:
        # Left hand assisted: left arm is active exercising arm
        return {
            "active_elbow_angle": raw["left_angle"],
            "assisting_elbow_angle": raw["right_angle"],
            "active_arm_visibility": raw["left_vis"],
            "assisting_arm_visibility": raw["right_vis"],
            "torso_tilt": raw["torso_tilt"],
            "torso_rotation": raw["torso_rotation"],
            "active_elbow_flare": raw["left_flare"],
            "assisting_elbow_flare": raw["right_flare"],
            "fallback_used": raw.get("fallback_used", 0.0),
        }
    else:
        # Both hand assisted: symmetric bilateral exercise
        return {
            "active_elbow_angle": (raw["left_angle"] + raw["right_angle"]) / 2.0,
            "assisting_elbow_angle": (raw["left_angle"] + raw["right_angle"]) / 2.0,
            "active_arm_visibility": (raw["left_vis"] + raw["right_vis"]) / 2.0,
            "assisting_arm_visibility": (raw["left_vis"] + raw["right_vis"]) / 2.0,
            "torso_tilt": raw["torso_tilt"],
            "torso_rotation": raw["torso_rotation"],
            "active_elbow_flare": max(raw["left_flare"], raw["right_flare"]),
            "assisting_elbow_flare": min(raw["left_flare"], raw["right_flare"]),
            "fallback_used": raw.get("fallback_used", 0.0),
        }


def build_normalized_sequence(
    rep_records: List[Dict[str, float]],
    target_length: int = 128,
) -> np.ndarray:
    """Build and normalize an 8-feature sequence matrix (target_length, 8) for a repetition.
    
    Features (8):
    0: active_elbow_angle
    1: assisting_elbow_angle
    2: active_elbow_velocity
    3: assisting_elbow_velocity
    4: torso_tilt
    5: torso_rotation
    6: active_elbow_flare
    7: assisting_elbow_flare
    """
    n_frames = len(rep_records)
    if n_frames < 2:
        return np.zeros((target_length, len(FEATURE_NAMES)), dtype=np.float32)

    # Extract time-series arrays
    act_angles = np.array([r["active_elbow_angle"] for r in rep_records], dtype=np.float32)
    asst_angles = np.array([r["assisting_elbow_angle"] for r in rep_records], dtype=np.float32)
    tilt = np.array([r["torso_tilt"] for r in rep_records], dtype=np.float32)
    rot = np.array([r["torso_rotation"] for r in rep_records], dtype=np.float32)
    act_flare = np.array([r["active_elbow_flare"] for r in rep_records], dtype=np.float32)
    asst_flare = np.array([r["assisting_elbow_flare"] for r in rep_records], dtype=np.float32)

    # Compute angular velocities (first derivative across frames)
    act_vel = np.gradient(act_angles)
    asst_vel = np.gradient(asst_angles)

    # Temporal interpolation to target_length
    old_x = np.linspace(0.0, 1.0, n_frames)
    new_x = np.linspace(0.0, 1.0, target_length)

    def resample(arr):
        return np.interp(new_x, old_x, arr).astype(np.float32)

    s_act_angle = resample(act_angles) / NORM_CONSTANTS["angle_divisor"]
    s_asst_angle = resample(asst_angles) / NORM_CONSTANTS["angle_divisor"]

    s_act_vel = np.clip(
        resample(act_vel) / NORM_CONSTANTS["velocity_divisor"],
        -NORM_CONSTANTS["clip_velocity"],
        NORM_CONSTANTS["clip_velocity"],
    )
    s_asst_vel = np.clip(
        resample(asst_vel) / NORM_CONSTANTS["velocity_divisor"],
        -NORM_CONSTANTS["clip_velocity"],
        NORM_CONSTANTS["clip_velocity"],
    )

    s_tilt = np.clip(resample(tilt) / NORM_CONSTANTS["tilt_divisor"], 0.0, 1.0)
    s_rot = np.clip(
        resample(rot),
        -NORM_CONSTANTS["clip_rotation"],
        NORM_CONSTANTS["clip_rotation"],
    )

    s_act_flare = np.clip(
        resample(act_flare),
        0.0,
        NORM_CONSTANTS["clip_flare"],
    )
    s_asst_flare = np.clip(
        resample(asst_flare),
        0.0,
        NORM_CONSTANTS["clip_flare"],
    )

    matrix = np.column_stack([
        s_act_angle,
        s_asst_angle,
        s_act_vel,
        s_asst_vel,
        s_tilt,
        s_rot,
        s_act_flare,
        s_asst_flare,
    ]).astype(np.float32)

    return np.nan_to_num(matrix, nan=0.0, posinf=1.0, neginf=-1.0)

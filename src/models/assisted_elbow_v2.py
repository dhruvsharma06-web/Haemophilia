"""Assisted Elbow Flexion V2 - Phase 4 Deployment Adapter.

Research-only inference adapter reproducing the authoritative Phase 3 BalancedSVM
pipeline with exact numerical equivalence.

Frozen Pipeline Architecture:
Raw Landmarks (World Coordinates)
  -> 34 Biomechanical Scalar Features
  -> Mean Imputation (Phase 3 Imputer Statistics)
  -> Standard Scaling (Phase 3 Scaler Mean & Scale)
  -> RBF Support Vector Classifier (Phase 3 BalancedSVM Parameters)
  -> Signed Decision Score (decision_function)
  -> Prediction: score > 0 => Incorrect, score <= 0 => Correct

PROHIBITIONS:
- No retraining
- No refitting
- No threshold tuning
- No feature addition/removal
- Strictly research-only (no modification of production checkpoints or evaluators)
"""

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

import numpy as np

# Authoritative feature order snapshot
MODEL_DIR = Path(__file__).resolve().parents[2] / "models"
DEFAULT_CHECKPOINT_PATH = MODEL_DIR / "assisted_elbow_v2_parameters.json"
DEFAULT_METADATA_PATH = MODEL_DIR / "assisted_elbow_v2_metadata.json"
DEFAULT_FEATURE_SNAPSHOT_PATH = MODEL_DIR / "assisted_elbow_v2_feature_snapshot.json"

BASE_CHANNELS = [
    "active_angle",
    "opposing_angle",
    "active_flare",
    "opposing_flare",
    "torso_lean",
    "shoulder_depth_ratio",
]

SCALAR_FEATURE_NAMES = [
    "active_min_angle",
    "active_max_angle",
    "active_rom",
    "opposing_min_angle",
    "opposing_max_angle",
    "opposing_rom",
    "duration",
    "active_peak_abs_velocity",
    "active_mean_abs_velocity",
    "opposing_peak_abs_velocity",
    "opposing_mean_abs_velocity",
    "active_mean_flare",
    "active_max_flare",
    "opposing_mean_flare",
    "opposing_max_flare",
    "mean_angle_asymmetry",
    "max_angle_asymmetry",
    "mean_flare_asymmetry",
    "max_flare_asymmetry",
    "mean_torso_lean",
    "max_torso_lean",
    "range_torso_lean",
    "mean_shoulder_depth_ratio",
    "max_shoulder_depth_ratio",
    "range_shoulder_depth_ratio",
    "flexion_duration",
    "extension_duration",
    "flexion_fraction",
    "active_start_angle",
    "active_end_angle",
    "flexion_excursion",
    "extension_excursion",
    "flexion_net_speed",
    "extension_net_speed",
]


@dataclass
class RepetitionInferenceResult:
    """Represents the complete result of Phase 4 model inference on one repetition."""
    repetition_id: Optional[str]
    hand: str
    duration_sec: float
    frame_count: int
    raw_features: np.ndarray
    imputed_features: np.ndarray
    scaled_features: np.ndarray
    decision_score: float
    predicted_label: str  # "Correct" or "Incorrect"
    is_incorrect: bool
    qc_flags: Dict[str, Any]
    feature_dict: Dict[str, float]


def compute_angle_3d_vectorized(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Compute 3D angle between vectors (a - b) and (c - b) in degrees across frames."""
    u = a - b
    v = c - b
    norm_u = np.linalg.norm(u, axis=1)
    norm_v = np.linalg.norm(v, axis=1)
    den = norm_u * norm_v
    safe_den = np.where(den > 1e-8, den, np.nan)
    dot = np.sum(u * v, axis=1)
    cos = np.clip(dot / safe_den, -1.0, 1.0)
    return np.degrees(np.arccos(cos))


def extract_base_kinematic_channels(
    world_landmarks: np.ndarray,
    hand: str,
    min_joint_visibility: float = 0.5,
) -> np.ndarray:
    """Extract raw base kinematic channels from (N, 33, 4) world landmarks.

    Landmark mapping:
      11: Left Shoulder, 12: Right Shoulder
      13: Left Elbow,    14: Right Elbow
      15: Left Wrist,    16: Right Wrist
      23: Left Hip,      24: Right Hip
    """
    if hand not in ("Left", "Right"):
        raise ValueError(f"Hand must be 'Left' or 'Right', got '{hand}'")

    xyz = world_landmarks[:, :, :3]
    vis = world_landmarks[:, :, 3]

    active_indices = (11, 13, 15) if hand == "Left" else (12, 14, 16)
    opposing_indices = (12, 14, 16) if hand == "Left" else (11, 13, 15)

    # Shoulder line and unit vector
    shoulder = xyz[:, 12] - xyz[:, 11]
    shoulder_width = np.linalg.norm(shoulder, axis=1)
    unit_shoulder = shoulder / np.where(shoulder_width > 1e-8, shoulder_width, np.nan)[:, None]

    # Torso vector
    mid_shoulder = (xyz[:, 11] + xyz[:, 12]) / 2.0
    mid_hip = (xyz[:, 23] + xyz[:, 24]) / 2.0
    torso = mid_shoulder - mid_hip

    # Base kinematics
    active_ang = compute_angle_3d_vectorized(
        xyz[:, active_indices[0]],
        xyz[:, active_indices[1]],
        xyz[:, active_indices[2]],
    )
    opposing_ang = compute_angle_3d_vectorized(
        xyz[:, opposing_indices[0]],
        xyz[:, opposing_indices[1]],
        xyz[:, opposing_indices[2]],
    )

    # Elbow flare relative to shoulder unit vector
    active_flare = (
        np.abs(np.sum((xyz[:, active_indices[1]] - xyz[:, active_indices[0]]) * unit_shoulder, axis=1))
        / shoulder_width
    )
    opposing_flare = (
        np.abs(np.sum((xyz[:, opposing_indices[1]] - xyz[:, opposing_indices[0]]) * unit_shoulder, axis=1))
        / shoulder_width
    )

    # Torso lean
    torso_lean = np.degrees(
        np.arctan2(np.linalg.norm(torso[:, [0, 2]], axis=1), np.abs(torso[:, 1]))
    )

    # Shoulder depth ratio
    shoulder_depth = np.abs(shoulder[:, 2]) / shoulder_width

    values = np.column_stack([
        active_ang,
        opposing_ang,
        active_flare,
        opposing_flare,
        torso_lean,
        shoulder_depth,
    ])

    # Visibility masking
    joints_to_check = [
        active_indices,
        opposing_indices,
        (11, 12, active_indices[1]),
        (11, 12, opposing_indices[1]),
        (11, 12, 23, 24),
        (11, 12),
    ]

    for j, indices in enumerate(joints_to_check):
        valid = (vis[:, indices] >= min_joint_visibility).all(axis=1) & np.isfinite(
            xyz[:, indices, :]
        ).all(axis=(1, 2))
        if j == 4:
            valid &= np.linalg.norm(torso, axis=1) > 1e-8
        values[~valid, j] = np.nan

    values[~np.isfinite(values)] = np.nan
    return values


def repair_channel_signal(
    values: np.ndarray,
    times: np.ndarray,
    min_valid_fraction: float = 0.8,
    max_internal_gap_sec: float = 0.5,
    max_endpoint_hold_sec: float = 0.1,
) -> Tuple[np.ndarray, List[Dict[str, Any]], Optional[str]]:
    """Strict Phase 1/3 channel repair policy with bounded interpolation."""
    x = values.copy()
    valid = np.isfinite(x)
    events = []

    if valid.mean() < min_valid_fraction:
        return x, events, f"valid_fraction={valid.mean():.6f} below {min_valid_fraction}"

    n = len(x)
    i = 0
    while i < n:
        if valid[i]:
            i += 1
            continue
        a = i
        while i < n and not valid[i]:
            i += 1
        b = i - 1

        if a > 0 and b < n - 1:
            gap = times[b + 1] - times[a - 1]
            if gap > max_internal_gap_sec:
                return x, events, f"internal_gap_seconds={gap:.6f}"
            x[a : b + 1] = np.interp(
                times[a : b + 1],
                [times[a - 1], times[b + 1]],
                [x[a - 1], x[b + 1]],
            )
            kind = "linear_internal"
        else:
            anchor = b + 1 if a == 0 else a - 1
            if not 0 <= anchor < n:
                return x, events, "no_valid_anchor"
            gap = max(abs(times[a] - times[anchor]), abs(times[b] - times[anchor]))
            if gap > max_endpoint_hold_sec:
                return x, events, f"endpoint_gap_seconds={gap:.6f}"
            x[a : b + 1] = x[anchor]
            kind = "endpoint_hold"

        events.append({
            "start_index": a,
            "end_index": b,
            "frames": b - a + 1,
            "support_gap_seconds": float(gap),
            "operation": kind,
        })

    return x, events, None


def derive_kinematics(base: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Compute gradient velocities, asymmetries, and elapsed time."""
    active_vel = np.gradient(base[:, 0], t, edge_order=1)
    opposing_vel = np.gradient(base[:, 1], t, edge_order=1)
    angle_asym = np.abs(base[:, 0] - base[:, 1])
    flare_asym = np.abs(base[:, 2] - base[:, 3])
    elapsed = t - t[0]

    return np.column_stack([
        base,
        active_vel,
        opposing_vel,
        angle_asym,
        flare_asym,
        elapsed,
    ])


def summarize_34_scalars(
    z: np.ndarray,
    t: np.ndarray,
    duration: float,
) -> Tuple[np.ndarray, int]:
    """Compute the locked 34 biomechanical scalar features from kinematic channels."""
    span = t[-1] - t[0]
    span = max(span, 1e-6)

    # trapezoidal numerical integration
    # NumPy 1.26 is required by MediaPipe 0.10.21; trapz is numerically
    # equivalent to the newer trapezoid API used by the research runner.
    avg = lambda arr: float(np.trapz(arr, t) / span)

    a, o, af, of, lean, depth, av, ov, aa, fa, _ = z.T
    phase_valid = np.isfinite(a).all()

    peak = int(np.argmin(a)) if phase_valid else -1
    flex = (t[peak] - t[0]) if phase_valid else np.nan
    extension = (t[-1] - t[peak]) if phase_valid else np.nan
    flex_exc = (a[0] - a[peak]) if phase_valid else np.nan
    ext_exc = (a[-1] - a[peak]) if phase_valid else np.nan

    vals = [
        a.min(),
        a.max(),
        np.ptp(a),
        o.min(),
        o.max(),
        np.ptp(o),
        duration,
        abs(av).max(),
        avg(abs(av)),
        abs(ov).max(),
        avg(abs(ov)),
        avg(af),
        af.max(),
        avg(of),
        of.max(),
        avg(aa),
        aa.max(),
        avg(fa),
        fa.max(),
        avg(lean),
        lean.max(),
        np.ptp(lean),
        avg(depth),
        depth.max(),
        np.ptp(depth),
        flex,
        extension,
        (flex / span) if phase_valid else np.nan,
        a[0],
        a[-1],
        flex_exc,
        ext_exc,
        (flex_exc / flex if flex > 0 else 0.0) if phase_valid else np.nan,
        (ext_exc / extension if extension > 0 else 0.0) if phase_valid else np.nan,
    ]

    scalars = np.array(vals, dtype=np.float64)
    assert len(scalars) == len(SCALAR_FEATURE_NAMES) == 34
    return scalars, peak


class BalancedSVMDeploymentAdapter:
    """Authoritative Phase 4 Deployment Adapter for Assisted Elbow Flexion V2."""

    def __init__(self, checkpoint_path: Union[str, Path] = DEFAULT_CHECKPOINT_PATH):
        self.checkpoint_path = Path(checkpoint_path)
        if not self.checkpoint_path.exists():
            raise FileNotFoundError(
                f"Authoritative Phase 3 parameters not found at {self.checkpoint_path}"
            )

        with open(self.checkpoint_path, "r", encoding="utf-8") as f:
            self.params = json.load(f)

        # Validate parameter structure
        assert self.params["kernel"] == "rbf"
        assert self.params["class_weight"] == "balanced"
        assert self.params["classes"] == [0, 1]
        assert self.params["class_labels"] == ["Correct", "Incorrect"]
        assert len(self.params["feature_names"]) == 34
        assert self.params["feature_names"] == SCALAR_FEATURE_NAMES

        # Numerical arrays
        self.support_vectors = np.array(self.params["support_vectors"], dtype=np.float64)
        self.dual_coefficients = np.array(self.params["dual_coefficients"][0], dtype=np.float64)
        self.intercept = float(self.params["intercept"])
        self.gamma = float(self.params["effective_gamma"])
        self.imputer_statistics = np.array(self.params["imputer_statistics"], dtype=np.float64)
        self.scaler_mean = np.array(self.params["scaler_mean"], dtype=np.float64)
        self.scaler_scale = np.array(self.params["scaler_scale"], dtype=np.float64)

        self.n_support = self.params["n_support_vectors"]
        self.total_support = self.params["total_support_vectors"]
        assert len(self.support_vectors) == self.total_support

    def extract_features(
        self,
        world_landmarks: np.ndarray,
        timestamps: np.ndarray,
        hand: str,
        duration: Optional[float] = None,
    ) -> Tuple[np.ndarray, Dict[str, float], Dict[str, Any]]:
        """Extract exact 34-feature vector from raw world landmarks and timestamps."""
        if len(world_landmarks) != len(timestamps):
            raise ValueError("world_landmarks and timestamps length mismatch")
        if len(world_landmarks) < 3:
            raise ValueError(f"Insufficient frames ({len(world_landmarks)}) for kinematics extraction")

        t = timestamps.astype(np.float64)
        rep_duration = float(duration if duration is not None else (t[-1] - t[0]))

        raw = extract_base_kinematic_channels(world_landmarks, hand)
        base = raw.copy()
        errors = []
        repaired_count = 0

        for j, name in enumerate(BASE_CHANNELS):
            base[:, j], events, err = repair_channel_signal(raw[:, j], t)
            repaired_count += sum(e["frames"] for e in events)
            if err:
                errors.append(f"{name}: {err}")

        z = derive_kinematics(base, t)
        scalars, peak = summarize_34_scalars(z, t, rep_duration)

        feature_dict = dict(zip(SCALAR_FEATURE_NAMES, scalars.tolist()))
        qc_dict = {
            "n_frames": len(t),
            "duration_sec": rep_duration,
            "raw_nan_count": int(np.isnan(raw).sum()),
            "repaired_values": repaired_count,
            "remaining_nan_count": int(np.isnan(base).sum()),
            "errors": errors,
            "phase_peak_index": peak,
            "phase_peak_at_endpoint": (peak in (0, len(t) - 1)),
        }

        return scalars, feature_dict, qc_dict

    def preprocess(self, raw_scalars: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """Apply Phase 3 SimpleImputer and StandardScaler."""
        # Mean imputation
        imputed = np.where(np.isnan(raw_scalars), self.imputer_statistics, raw_scalars)
        # Standard scaling
        scaled = (imputed - self.scaler_mean) / self.scaler_scale
        return imputed, scaled

    def decision_function(self, scaled_features: np.ndarray) -> Union[float, np.ndarray]:
        """Compute exact RBF SVM decision function score via deterministic NumPy math.

        K(x, s) = exp(-gamma * ||x - s||^2)
        score = sum(alpha_i * K(x, s_i)) + intercept
        """
        is_1d = (scaled_features.ndim == 1)
        X = np.atleast_2d(scaled_features)

        # Compute squared Euclidean distances to all support vectors: (N, N_sv)
        dist_sq = np.sum((X[:, None, :] - self.support_vectors[None, :, :]) ** 2, axis=-1)
        kernel = np.exp(-self.gamma * dist_sq)
        scores = np.dot(kernel, self.dual_coefficients) + self.intercept

        return float(scores[0]) if is_1d else scores

    def predict_from_scalars(
        self,
        raw_scalars: np.ndarray,
        hand: str = "Unknown",
        repetition_id: Optional[str] = None,
        duration: Optional[float] = None,
        frame_count: int = 0,
        qc_flags: Optional[Dict[str, Any]] = None,
    ) -> RepetitionInferenceResult:
        """Inference from pre-computed 34 scalar features."""
        imputed, scaled = self.preprocess(raw_scalars)
        score = float(self.decision_function(scaled))

        # Authoritative decision rule:
        # decision_function > 0 -> Incorrect (Class 1)
        # decision_function <= 0 -> Correct (Class 0)
        is_incorrect = bool(score > 0.0)
        pred_label = "Incorrect" if is_incorrect else "Correct"

        dur = float(duration if duration is not None else raw_scalars[6])
        feature_dict = dict(zip(SCALAR_FEATURE_NAMES, raw_scalars.tolist()))

        return RepetitionInferenceResult(
            repetition_id=repetition_id,
            hand=hand,
            duration_sec=dur,
            frame_count=frame_count,
            raw_features=raw_scalars,
            imputed_features=imputed,
            scaled_features=scaled,
            decision_score=score,
            predicted_label=pred_label,
            is_incorrect=is_incorrect,
            qc_flags=qc_flags or {},
            feature_dict=feature_dict,
        )

    def predict(
        self,
        world_landmarks: np.ndarray,
        timestamps: np.ndarray,
        hand: str,
        duration: Optional[float] = None,
        repetition_id: Optional[str] = None,
    ) -> RepetitionInferenceResult:
        """Full end-to-end inference from raw landmarks and timestamps."""
        scalars, feat_dict, qc = self.extract_features(
            world_landmarks=world_landmarks,
            timestamps=timestamps,
            hand=hand,
            duration=duration,
        )
        return self.predict_from_scalars(
            raw_scalars=scalars,
            hand=hand,
            repetition_id=repetition_id,
            duration=duration,
            frame_count=len(world_landmarks),
            qc_flags=qc,
        )

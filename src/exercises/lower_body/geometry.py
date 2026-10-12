# Geometry and biomechanical math utilities for lower-body exercises.
# Direct port from Physio-Project (math_utils.py, landmarks.py) to preserve exact logic.
from typing import Dict, List, Optional, Tuple, Union
import numpy as np

LM = {
    "nose": 0,
    "left_ear": 7,
    "right_ear": 8,
    "left_shoulder": 11,
    "right_shoulder": 12,
    "left_elbow": 13,
    "right_elbow": 14,
    "left_wrist": 15,
    "right_wrist": 16,
    "left_hip": 23,
    "right_hip": 24,
    "left_knee": 25,
    "right_knee": 26,
    "left_ankle": 27,
    "right_ankle": 28,
    "left_heel": 29,
    "right_heel": 30,
    "left_foot": 31,
    "right_foot": 32,
}

VISIBILITY_THRESH = 0.5


def get_coord(lm) -> Tuple[float, float, float, float]:
    """Extract (x, y, z, visibility) from landmark object, dict, or tuple."""
    if hasattr(lm, "x"):
        return float(lm.x), float(lm.y), float(getattr(lm, "z", 0.0)), float(getattr(lm, "visibility", 1.0))
    if isinstance(lm, dict):
        return (
            float(lm.get("x", 0.0)),
            float(lm.get("y", 0.0)),
            float(lm.get("z", 0.0)),
            float(lm.get("visibility", 1.0)),
        )
    if isinstance(lm, (list, tuple)):
        x = float(lm[0]) if len(lm) > 0 else 0.0
        y = float(lm[1]) if len(lm) > 1 else 0.0
        z = float(lm[2]) if len(lm) > 2 else 0.0
        vis = float(lm[3]) if len(lm) > 3 else 1.0
        return x, y, z, vis
    return 0.0, 0.0, 0.0, 0.0


def get_lm(lms, name_or_idx):
    """Retrieve landmark by name or index from PoseLandmarks, list, or dict."""
    if lms is None:
        return None
    idx = LM[name_or_idx] if isinstance(name_or_idx, str) and name_or_idx in LM else name_or_idx
    if hasattr(lms, "landmark"):
        if 0 <= idx < len(lms.landmark):
            return lms.landmark[idx]
        return None
    if isinstance(lms, (list, tuple)):
        if 0 <= idx < len(lms):
            return lms[idx]
        return None
    if isinstance(lms, dict):
        if idx in lms:
            return lms[idx]
        if isinstance(name_or_idx, str) and name_or_idx in lms:
            return lms[name_or_idx]
        return None
    return None


def angle_2d(a, b, c) -> float:
    """
    Angle at vertex point B using 2D pixel/normalized coordinates (x, y).
    Formula: arccos(dot(ba, bc) / (|ba|*|bc|)).
    """
    a_pt = np.array([a[0], a[1]], dtype=float)
    b_pt = np.array([b[0], b[1]], dtype=float)
    c_pt = np.array([c[0], c[1]], dtype=float)
    ba = a_pt - b_pt
    bc = c_pt - b_pt
    denom = np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6
    cos = np.dot(ba, bc) / denom
    return float(np.degrees(np.arccos(np.clip(cos, -1.0, 1.0))))


def angle_3d(a, b, c) -> float:
    """
    Angle at vertex point B using normalized 3D coordinates (x, y, z).
    Formula: arccos(dot(ba, bc) / (|ba|*|bc|)).
    """
    ax, ay, az, _ = get_coord(a)
    bx, by, bz, _ = get_coord(b)
    cx, cy, cz, _ = get_coord(c)
    av = np.array([ax, ay, az], dtype=float)
    bv = np.array([bx, by, bz], dtype=float)
    cv_ = np.array([cx, cy, cz], dtype=float)
    ba = av - bv
    bc = cv_ - bv
    denom = np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6
    cos = np.dot(ba, bc) / denom
    return float(np.degrees(np.arccos(np.clip(cos, -1.0, 1.0))))


def torso_lean(sh_px, hip_px) -> float:
    """Returns the lean angle (degrees) of torso from vertical."""
    dx = sh_px[0] - hip_px[0]
    dy = max(hip_px[1] - sh_px[1], 1)
    return float(np.degrees(np.arctan2(abs(dx), dy)))


def detect_view(lms) -> str:
    """
    Returns 'SIDE' if turned sideways, 'FRONT' otherwise.
    Uses shoulder z difference threshold (0.12) from seniors' codebase.
    """
    try:
        sh_l = get_lm(lms, "left_shoulder")
        sh_r = get_lm(lms, "right_shoulder")
        if sh_l is None or sh_r is None:
            return "FRONT"
        _, _, zl, _ = get_coord(sh_l)
        _, _, zr, _ = get_coord(sh_r)
        return "SIDE" if abs(zl - zr) > 0.12 else "FRONT"
    except Exception:
        return "FRONT"


def build_pts(lms, w: int, h: int, thresh: float = VISIBILITY_THRESH) -> Dict[str, Tuple[int, int]]:
    """Build a pixel-coordinate dict for all landmarks meeting visibility threshold."""
    pts = {}
    if lms is None:
        return pts
    for name, idx in LM.items():
        lm = get_lm(lms, idx)
        if lm is None:
            continue
        x, y, _, vis = get_coord(lm)
        if vis >= thresh:
            pts[name] = (int(x * w), int(y * h))
    return pts

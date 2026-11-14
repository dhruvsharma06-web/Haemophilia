# Biomechanical check implementations for lower-body exercises.
# Ported faithfully from Physio-Project (checks/*.js, posture_checks.py).
import math
from typing import Dict, List, Optional, Tuple
import numpy as np

from src.exercises.lower_body.geometry import (
    LM,
    angle_2d,
    angle_3d,
    detect_view,
    get_coord,
    get_lm,
    torso_lean,
)


class BiomechanicalCheckEngine:
    """Stateful evaluator for real-time exercise checks across a repetition."""

    def __init__(self, exercise_name: str, thresholds: Dict):
        self.exercise_name = exercise_name
        self.thresholds = thresholds or {}

        # Stateful baselines reset on rep start
        self.heel_baseline: Optional[Dict[str, float]] = None
        self.pelvis_baseline_y: Optional[float] = None
        self.head_baseline_y: Optional[float] = None
        self.thigh_baseline_angle: Optional[float] = None
        self.heel_slide_rest_dist: float = 0.0
        self.heel_slide_min_dist: float = float("inf")
        self.heel_slide_min_angle: float = float("inf")
        self.heel_slide_judged: bool = False
        self.heel_slide_verdict: Optional[str] = None
        self.rocking_samples: List[float] = []

    def reset_rep_state(self):
        """Called when a new repetition begins (transition to DOWN stage)."""
        self.heel_baseline = None
        self.pelvis_baseline_y = None
        self.head_baseline_y = None
        self.thigh_baseline_angle = None
        self.heel_slide_rest_dist = 0.0
        self.heel_slide_min_dist = float("inf")
        self.heel_slide_min_angle = float("inf")
        self.heel_slide_judged = False
        self.heel_slide_verdict = None
        self.rocking_samples = []

    def run_checks(
        self,
        lms,
        pts: Dict[str, Tuple[int, int]],
        w: int,
        h: int,
        stage: str,
        driver_angle: Optional[float] = None,
        view: Optional[str] = None,
    ) -> List[str]:
        """
        Run all configured checks for the current exercise and frame.
        Returns a list of human-readable alert strings.
        """
        if lms is None:
            return []

        if view is None:
            view = detect_view(lms)

        alerts = []
        checks_to_run = self._get_configured_checks()

        for check_name in checks_to_run:
            alert = self._evaluate_check(
                check_name, lms, pts, w, h, stage, driver_angle, view
            )
            if alert and alert not in alerts:
                alerts.append(alert)

        return alerts

    def _get_configured_checks(self) -> List[str]:
        mapping = {
            "mini_squat": [
                "heel_lifting",
                "knee_varus",
                "knee_past_toes_margin",
                "ankles_close_together",
            ],
            "seated_knee_extension": [
                "hip_lifting",
                "back_slouching",
                "back_rocking",
            ],
            "straight_leg_raise": [
                "hip_lifting_raise_angle",
                "knee_flexion_high",
                "head_lifting",
            ],
            "heel_slide": [
                "heel_lifting",
                "hip_lifting",
                "slide_insufficient",
            ],
            "terminal_knee_extension": [
                "hip_lifting",
                "thigh_lifting",
            ],
            "squat": [
                "knee_cave",
                "torso_lean_front",
                "torso_lean_side",
                "knee_past_toes",
                "heel_lift",
                "butt_wink",
                "neck",
            ],
        }
        return mapping.get(self.exercise_name, [])

    def _evaluate_check(
        self,
        check_name: str,
        lms,
        pts: Dict[str, Tuple[int, int]],
        w: int,
        h: int,
        stage: str,
        driver_angle: Optional[float],
        view: str,
    ) -> Optional[str]:
        t = self.thresholds

        # -------------------------------------------------------------
        # SQUAT & SHARED CHECKS
        # -------------------------------------------------------------
        if check_name == "knee_cave":
            if view != "FRONT":
                return None
            if "left_knee" in pts and "right_knee" in pts and "left_ankle" in pts and "right_ankle" in pts:
                knee_w = abs(pts["left_knee"][0] - pts["right_knee"][0])
                ankle_w = abs(pts["left_ankle"][0] - pts["right_ankle"][0])
                ratio_thresh = t.get("knee_cave_min_width_ratio", {}).get("value", 0.72)
                if ankle_w > 10 and knee_w < ankle_w * ratio_thresh:
                    return t.get("knee_cave_min_width_ratio", {}).get(
                        "alert", "Knees caving in — push knees out"
                    )
            return None

        if check_name == "torso_lean_front":
            if view != "FRONT":
                return None
            need = {"left_shoulder", "right_shoulder", "left_hip", "right_hip"}
            if need.issubset(pts):
                mid_sh = (
                    (pts["left_shoulder"][0] + pts["right_shoulder"][0]) // 2,
                    (pts["left_shoulder"][1] + pts["right_shoulder"][1]) // 2,
                )
                mid_hip = (
                    (pts["left_hip"][0] + pts["right_hip"][0]) // 2,
                    (pts["left_hip"][1] + pts["right_hip"][1]) // 2,
                )
                lean = torso_lean(mid_sh, mid_hip)
                max_deg = t.get("torso_lean_max_deg", {}).get("value", 55)
                if lean > max_deg:
                    return t.get("torso_lean_max_deg", {}).get(
                        "alert", "Leaning too far forward — chest up"
                    )
            return None

        if check_name == "torso_lean_side":
            if view != "SIDE":
                return None
            s = self._get_side_prefix(lms)
            if f"{s}_shoulder" in pts and f"{s}_hip" in pts:
                lean = torso_lean(pts[f"{s}_shoulder"], pts[f"{s}_hip"])
                max_deg = t.get("torso_lean_max_deg", {}).get("value", 55)
                if lean > max_deg:
                    return t.get("torso_lean_max_deg", {}).get(
                        "alert", "Leaning too far forward — chest up"
                    )
            return None

        if check_name == "knee_past_toes":
            if view != "SIDE":
                return None
            s = self._get_side_prefix(lms)
            foot_key = f"{s}_ankle" if f"{s}_foot" not in pts else f"{s}_foot"
            if f"{s}_knee" in pts and foot_key in pts:
                knee_toe_x = (pts[f"{s}_knee"][0] - pts[foot_key][0]) / max(w, 1)
                max_ratio = t.get("knee_past_toes_max_x_ratio", {}).get("value", 0.06)
                if abs(knee_toe_x) > max_ratio:
                    return t.get("knee_past_toes_max_x_ratio", {}).get(
                        "alert", "Knee past toes — sit back more"
                    )
            return None

        if check_name == "knee_past_toes_margin":
            if view != "SIDE":
                return None
            s = self._get_side_prefix(lms)
            foot_key = f"{s}_foot" if f"{s}_foot" in pts else f"{s}_ankle"
            if f"{s}_knee" in pts and foot_key in pts:
                margin = (pts[f"{s}_knee"][0] - pts[foot_key][0]) / max(w, 1)
                max_margin = t.get("knee_past_toes_max_margin", {}).get("value", 0.05)
                if abs(margin) > max_margin:
                    return t.get("knee_past_toes_max_margin", {}).get(
                        "alert", "Knee past toes — sit back more"
                    )
            return None

        if check_name in {"heel_lift", "heel_lifting"}:
            hl_l = get_lm(lms, "left_heel")
            hl_r = get_lm(lms, "right_heel")
            if hl_l is None or hl_r is None:
                return None
            _, y_l, _, _ = get_coord(hl_l)
            _, y_r, _, _ = get_coord(hl_r)
            if stage == "DOWN" and self.heel_baseline is None:
                self.heel_baseline = {"left": y_l, "right": y_r}
            elif stage == "UP":
                self.heel_baseline = None
                return None
            if self.heel_baseline is not None:
                rise = max(
                    self.heel_baseline["left"] - y_l,
                    self.heel_baseline["right"] - y_r,
                )
                max_rise = t.get("heel_lifting_max_y_rise", {}).get("value", 0.03)
                if rise > max_rise:
                    return t.get("heel_lifting_max_y_rise", {}).get(
                        "alert", "Heels lifting — press heels down"
                    )
            return None

        if check_name == "butt_wink":
            if view != "SIDE":
                return None
            max_knee = t.get("butt_wink_max_knee_angle_deg", {}).get("value", 115)
            if driver_angle is not None and driver_angle > max_knee:
                return None
            s = self._get_side_prefix(lms)
            sh = get_lm(lms, f"{s}_shoulder")
            hip = get_lm(lms, f"{s}_hip")
            knee = get_lm(lms, f"{s}_knee")
            if sh and hip and knee:
                hip_angle = angle_3d(sh, hip, knee)
                min_hip = t.get("butt_wink_min_hip_angle_deg", {}).get("value", 58)
                if hip_angle < min_hip:
                    return t.get("butt_wink_min_hip_angle_deg", {}).get(
                        "alert", "Lower back rounding — brace your core"
                    )
            return None

        if check_name == "neck":
            try:
                if view == "SIDE":
                    s = self._get_side_prefix(lms)
                    ear = get_lm(lms, f"{s}_ear")
                    sh = get_lm(lms, f"{s}_shoulder")
                    hip = get_lm(lms, f"{s}_hip")
                    na = angle_3d(ear, sh, hip) if ear and sh and hip else 180.0
                else:
                    el = get_lm(lms, "left_ear")
                    er = get_lm(lms, "right_ear")
                    sl = get_lm(lms, "left_shoulder")
                    sr = get_lm(lms, "right_shoulder")
                    hl = get_lm(lms, "left_hip")
                    hr = get_lm(lms, "right_hip")
                    al = angle_3d(el, sl, hl) if el and sl and hl else 180.0
                    ar = angle_3d(er, sr, hr) if er and sr and hr else 180.0
                    na = (al + ar) / 2
                min_na = t.get("neck_min_angle_deg", {}).get("value", 140)
                if na < min_na:
                    return t.get("neck_min_angle_deg", {}).get(
                        "alert", "Neck not neutral — look straight ahead"
                    )
            except Exception:
                pass
            return None

        # -------------------------------------------------------------
        # MINI SQUAT SPECIFIC CHECKS
        # -------------------------------------------------------------
        if check_name == "knee_varus":
            if view != "FRONT":
                return None
            if "left_hip" not in pts or "right_hip" not in pts:
                return None
            hip_width = abs(pts["left_hip"][0] - pts["right_hip"][0])
            if hip_width < 10:
                return None
            max_ratio = 0.0
            for side in ["left", "right"]:
                hip = pts.get(f"{side}_hip")
                knee = pts.get(f"{side}_knee")
                ankle = pts.get(f"{side}_ankle")
                if not hip or not knee or not ankle:
                    continue
                vx = ankle[0] - hip[0]
                vy = ankle[1] - hip[1]
                length = math.hypot(vx, vy)
                if length < 1:
                    continue
                dist = abs((knee[0] - hip[0]) * vy - (knee[1] - hip[1]) * vx) / length
                max_ratio = max(max_ratio, dist / hip_width)
            thresh = t.get("knee_varus_max_offset_ratio", {}).get("value", 0.18)
            if max_ratio > thresh:
                return t.get("knee_varus_max_offset_ratio", {}).get(
                    "alert", "Keep knees aligned with toes"
                )
            return None

        if check_name == "ankles_close_together":
            if view != "FRONT":
                return None
            la = get_lm(lms, "left_ankle")
            ra = get_lm(lms, "right_ankle")
            ls = get_lm(lms, "left_shoulder")
            rs = get_lm(lms, "right_shoulder")
            if la and ra and ls and rs:
                lax, lay, laz, _ = get_coord(la)
                rax, ray, raz, _ = get_coord(ra)
                lsx, lsy, lsz, _ = get_coord(ls)
                rsx, rsy, rsz, _ = get_coord(rs)
                ankle_w = math.sqrt((lax - rax) ** 2 + (lay - ray) ** 2 + (laz - raz) ** 2)
                sh_w = math.sqrt((lsx - rsx) ** 2 + (lsy - rsy) ** 2 + (lsz - rsz) ** 2)
                if sh_w > 1e-6:
                    ratio = ankle_w / sh_w
                    min_ratio = t.get("ankles_min_width_ratio", {}).get("value", 0.85)
                    if ratio < min_ratio:
                        return t.get("ankles_min_width_ratio", {}).get(
                            "alert", "Ankles too close together — widen stance"
                        )
            return None

        # -------------------------------------------------------------
        # SEATED & SUPINE LOWER BODY CHECKS
        # -------------------------------------------------------------
        if check_name == "hip_lifting":
            lh = get_lm(lms, "left_hip")
            rh = get_lm(lms, "right_hip")
            if lh and rh:
                _, ly, _, _ = get_coord(lh)
                _, ry, _, _ = get_coord(rh)
                pelvis_y = (ly + ry) / 2.0
                if stage == "DOWN" and self.pelvis_baseline_y is None:
                    self.pelvis_baseline_y = pelvis_y
                elif stage == "UP":
                    self.pelvis_baseline_y = None
                    return None
                if self.pelvis_baseline_y is not None:
                    rise = self.pelvis_baseline_y - pelvis_y
                    max_rise = t.get("hip_lifting_max_y_rise", {}).get("value", 0.03)
                    if rise > max_rise:
                        return t.get("hip_lifting_max_y_rise", {}).get(
                            "alert", "Hip lifting — keep your hip down"
                        )
            return None

        if check_name == "back_slouching":
            need = {"left_shoulder", "right_shoulder", "left_hip", "right_hip", "nose"}
            if need.issubset(pts):
                sh_x = (pts["left_shoulder"][0] + pts["right_shoulder"][0]) / 2.0
                sh_y = (pts["left_shoulder"][1] + pts["right_shoulder"][1]) / 2.0
                hip_x = (pts["left_hip"][0] + pts["right_hip"][0]) / 2.0
                hip_y = (pts["left_hip"][1] + pts["right_hip"][1]) / 2.0
                trunk = math.hypot(sh_x - hip_x, sh_y - hip_y)
                if trunk >= 10:
                    head_forward = abs(pts["nose"][0] - sh_x) / trunk
                    max_ratio = t.get("back_slouching_max_head_forward_ratio", {}).get("value", 0.25)
                    if head_forward > max_ratio:
                        return t.get("back_slouching_max_head_forward_ratio", {}).get(
                            "alert", "Keep your back straight and chest upright"
                        )
            return None

        if check_name == "back_rocking":
            lh = get_lm(lms, "left_hip")
            rh = get_lm(lms, "right_hip")
            ls = get_lm(lms, "left_shoulder")
            rs = get_lm(lms, "right_shoulder")
            nose = get_lm(lms, "nose")
            if lh and rh and ls and rs and nose:
                lx, _, _, _ = get_coord(lh)
                rx, _, _, _ = get_coord(rh)
                pelvis_cx = (lx + rx) / 2.0
                lsx, lsy, _, _ = get_coord(ls)
                rsx, rsy, _, _ = get_coord(rs)
                sh_w = math.hypot(lsx - rsx, lsy - rsy)
                nx, _, _, _ = get_coord(nose)
                if stage == "UP":
                    self.rocking_samples = []
                    return None
                if sh_w > 1e-6:
                    self.rocking_samples.append((nx - pelvis_cx) / sh_w)
                    if len(self.rocking_samples) > 300:
                        self.rocking_samples.pop(0)
                    if len(self.rocking_samples) >= 15:
                        var = float(np.var(self.rocking_samples))
                        std_dev = math.sqrt(var)
                        max_score = t.get("back_rocking_max_score", {}).get("value", 0.06)
                        if std_dev > max_score:
                            return t.get("back_rocking_max_score", {}).get(
                                "alert", "Keep upper body still — avoid rocking"
                            )
            return None

        # -------------------------------------------------------------
        # STRAIGHT LEG RAISE CHECKS
        # -------------------------------------------------------------
        if check_name == "hip_lifting_raise_angle":
            max_raise = 0.0
            found = False
            for side in ["left", "right"]:
                sh = pts.get(f"{side}_shoulder")
                hip = pts.get(f"{side}_hip")
                knee = pts.get(f"{side}_knee")
                if sh and hip and knee:
                    try:
                        ang = angle_2d(sh, hip, knee)
                        max_raise = max(max_raise, 180.0 - ang)
                        found = True
                    except Exception:
                        pass
            if found:
                max_allowed = t.get("hip_lifting_max_raise_angle_deg", {}).get("value", 46.0)
                if max_raise > max_allowed:
                    return t.get("hip_lifting_max_raise_angle_deg", {}).get(
                        "alert", "Keep pelvis on mat — do not over-lift hip"
                    )
            return None

        if check_name == "knee_flexion_high":
            if stage != "DOWN":
                return None
            min_knee = 180.0
            found = False
            for side in ["left", "right"]:
                hip = pts.get(f"{side}_hip")
                knee = pts.get(f"{side}_knee")
                ankle = pts.get(f"{side}_ankle")
                if hip and knee and ankle:
                    try:
                        ang = angle_2d(hip, knee, ankle)
                        min_knee = min(min_knee, ang)
                        found = True
                    except Exception:
                        pass
            if found:
                min_allowed = t.get("knee_flexion_high_min_angle_deg", {}).get("value", 160.0)
                if min_knee < min_allowed:
                    return t.get("knee_flexion_high_min_angle_deg", {}).get(
                        "alert", "Keep your knee straight"
                    )
            return None

        if check_name == "head_lifting":
            nose = get_lm(lms, "nose")
            if nose:
                _, ny, _, _ = get_coord(nose)
                if stage == "DOWN" and self.head_baseline_y is None:
                    self.head_baseline_y = ny
                elif stage == "UP":
                    self.head_baseline_y = None
                    return None
                if self.head_baseline_y is not None:
                    rise = self.head_baseline_y - ny
                    max_rise = t.get("head_lifting_max_y_rise", {}).get("value", 0.04)
                    if rise > max_rise:
                        return t.get("head_lifting_max_y_rise", {}).get(
                            "alert", "Keep head resting down on mat"
                        )
            return None

        # -------------------------------------------------------------
        # TERMINAL KNEE EXTENSION CHECKS
        # -------------------------------------------------------------
        if check_name == "thigh_lifting":
            sh = pts.get("left_shoulder")
            hip = pts.get("left_hip")
            knee = pts.get("left_knee")
            if sh and hip and knee:
                ang = angle_2d(sh, hip, knee)
                if stage == "DOWN" and self.thigh_baseline_angle is None:
                    self.thigh_baseline_angle = ang
                elif stage != "DOWN":
                    self.thigh_baseline_angle = None
                    return None
                if self.thigh_baseline_angle is not None:
                    diff = abs(ang - self.thigh_baseline_angle)
                    max_change = t.get("thigh_lifting_max_hip_change_deg", {}).get("value", 20.0)
                    if diff > max_change:
                        return t.get("thigh_lifting_max_hip_change_deg", {}).get(
                            "alert", "Keep your thigh on the pillow — only straighten the knee"
                        )
            return None

        # -------------------------------------------------------------
        # HEEL SLIDE CHECKS
        # -------------------------------------------------------------
        if check_name == "slide_insufficient":
            hip = pts.get("left_hip")
            heel = pts.get("left_heel")
            d = math.hypot(heel[0] - hip[0], heel[1] - hip[1]) if hip and heel else None
            if stage != "DOWN":
                if d is not None:
                    self.heel_slide_rest_dist = max(self.heel_slide_rest_dist, d)
                self.heel_slide_min_dist = float("inf")
                self.heel_slide_min_angle = float("inf")
                self.heel_slide_verdict = None
                self.heel_slide_judged = False
                return None
            if self.heel_slide_judged:
                return self.heel_slide_verdict
            if driver_angle is None:
                return None
            self.heel_slide_min_angle = min(self.heel_slide_min_angle, driver_angle)
            if d is not None:
                self.heel_slide_min_dist = min(self.heel_slide_min_dist, d)
            return_deg = t.get("slide_insufficient_return_deg", {}).get("value", 15.0)
            if driver_angle >= self.heel_slide_min_angle + return_deg:
                self.heel_slide_judged = True
                depth_target = 90.0
                knee_short = self.heel_slide_min_angle > depth_target
                min_travel = t.get("slide_insufficient_min_heel_travel_ratio", {}).get("value", 0.35)
                heel_short = (
                    self.heel_slide_rest_dist > 0
                    and math.isfinite(self.heel_slide_min_dist)
                    and (self.heel_slide_rest_dist - self.heel_slide_min_dist) / self.heel_slide_rest_dist < min_travel
                )
                if knee_short or heel_short:
                    self.heel_slide_verdict = "Slide heel further toward your hips"
                else:
                    self.heel_slide_verdict = None
                return self.heel_slide_verdict
            return None

        return None

    def _get_side_prefix(self, lms) -> str:
        sh_l = get_lm(lms, "left_shoulder")
        sh_r = get_lm(lms, "right_shoulder")
        if sh_l and sh_r:
            _, _, zl, _ = get_coord(sh_l)
            _, _, zr, _ = get_coord(sh_r)
            return "left" if zl < zr else "right"
        return "left"

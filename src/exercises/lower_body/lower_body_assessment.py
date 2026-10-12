# Lower-body assessment engine implementing HemoPhysio live assessment interface.
# Preserves senior algorithms and clinical thresholds from Physio-Project.
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import numpy as np

from src.exercises.lower_body.checks import BiomechanicalCheckEngine
from src.exercises.lower_body.geometry import (
    LM,
    angle_2d,
    angle_3d,
    build_pts,
    detect_view,
    get_coord,
    get_lm,
)
from src.exercises.lower_body.model_evaluator import model_evaluator

CONFIG_PATH = Path(__file__).resolve().parents[3] / "backend" / "app" / "config" / "exercises.json"

SUPPORTED_LOWER_BODY_EXERCISES = {
    "heel_slide",
    "mini_squat",
    "seated_knee_extension",
    "straight_leg_raise",
    "terminal_knee_extension",
    "squat",
}

# Exercise alias normalization map
EXERCISE_ALIASES = {
    "heel_slides": "heel_slide",
    "heel_slide": "heel_slide",
    "mini_squats": "mini_squat",
    "mini_squat": "mini_squat",
    "seated_knee_extension": "seated_knee_extension",
    "seated_knee_extensions": "seated_knee_extension",
    "seated_leg_extensions": "seated_knee_extension",
    "straight_leg_raise": "straight_leg_raise",
    "straight_leg_raises": "straight_leg_raise",
    "slr": "straight_leg_raise",
    "terminal_knee_extension": "terminal_knee_extension",
    "terminal_knee_extensions": "terminal_knee_extension",
    "tke": "terminal_knee_extension",
    "squat": "squat",
    "squats": "squat",
}


def canonicalize_lower_body_id(exercise_id: str) -> Optional[str]:
    """Map raw or display exercise name to canonical lower-body exercise ID."""
    clean = (
        (exercise_id or "")
        .strip()
        .lower()
        .replace("-", "_")
        .replace(" ", "_")
    )
    return EXERCISE_ALIASES.get(clean)


class LowerBodyAssessment:
    """
    Live assessment engine for lower-body exercises.
    Compatible drop-in with HemoPhysio WebSocket assessment loop.
    """

    def __init__(
        self,
        exercise_name: str,
        fps: float = 20.0,
        config_path: Path = CONFIG_PATH,
    ):
        canonical_name = canonicalize_lower_body_id(exercise_name)
        if not canonical_name:
            raise ValueError(
                f"Unsupported lower-body exercise: {exercise_name}. "
                f"Supported: {sorted(SUPPORTED_LOWER_BODY_EXERCISES)}"
            )

        self.canonical_name = canonical_name
        self.fps = fps
        self.config_path = config_path

        # Load exercise config from exercises.json
        self.config = self._load_exercise_config(canonical_name)
        self.display_name = self.config.get("display_name", canonical_name.replace("_", " ").title())
        self.rep_trigger = self.config.get("rep_trigger", {})
        self.joints = self.config.get("joints", [])
        self.thresholds = self.config.get("thresholds", {})

        # Check engine & ML model evaluator
        self.check_engine = BiomechanicalCheckEngine(self.canonical_name, self.thresholds)
        self.model_eval = model_evaluator

        # Assessment state machine
        self.state = "UP"  # "UP" (starting/resting) vs "DOWN" (active movement)
        self.rep_count = 0
        self.clean_rep_count = 0
        self.frame_number = 0
        self.rep_start_frame: Optional[int] = None
        self.best_driver_angle: Optional[float] = None
        self.current_angle = 0.0
        self.current_left_angle = 0.0
        self.current_right_angle = 0.0
        self.current_view = "FRONT"
        self.active_error: Optional[str] = None
        self.current_feedback = f"Ready: Position yourself for {self.display_name}."

        # Repetition tracking buffers
        self.current_rep_errors: List[str] = []
        self.rep_kinematics_buffer: List[Dict[str, Any]] = []
        self.rep_landmarks_buffer: List[Any] = []
        self.last_result: Dict[str, Any] = {}

    def _load_exercise_config(self, ex_name: str) -> Dict[str, Any]:
        if not self.config_path.exists():
            raise FileNotFoundError(f"Exercise config file not found: {self.config_path}")
        with open(self.config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        for item in data.get("exercises", []):
            if item.get("name") == ex_name:
                return item
        raise ValueError(f"Exercise {ex_name} not found in {self.config_path}")

    def _compute_joint_angle(self, joint_cfg: Dict, lms, pts: Dict[str, Tuple[int, int]]) -> Optional[float]:
        """Compute angle for joint config using 2D or 3D as specified in config."""
        la_name = joint_cfg.get("landmark_a")
        lb_name = joint_cfg.get("landmark_b")
        lc_name = joint_cfg.get("landmark_c")
        use_3d = joint_cfg.get("use_3d", False)

        if use_3d:
            la = get_lm(lms, la_name)
            lb = get_lm(lms, lb_name)
            lc = get_lm(lms, lc_name)
            if la and lb and lc:
                try:
                    return angle_3d(la, lb, lc)
                except Exception:
                    return None
            return None
        else:
            if la_name in pts and lb_name in pts and lc_name in pts:
                try:
                    return angle_2d(pts[la_name], pts[lb_name], pts[lc_name])
                except Exception:
                    return None
            return None

    def process_frame(
        self,
        frame: Optional[np.ndarray],
        pose_landmarks,
        frame_number: int = 0,
    ) -> Optional[Dict[str, Any]]:
        """
        Process single video frame with pose landmarks.
        Returns completed_rep dict if a rep finished on this frame, else None.
        """
        self.frame_number = frame_number or (self.frame_number + 1)

        if pose_landmarks is None:
            self.current_feedback = "Position yourself clearly in front of the camera."
            return None

        # Determine frame dimensions
        h, w = (frame.shape[0], frame.shape[1]) if frame is not None else (480, 640)
        pts = build_pts(pose_landmarks, w, h)
        self.current_view = detect_view(pose_landmarks)

        # Compute angles for all configured joints
        driver_angle: Optional[float] = None
        left_angle: Optional[float] = None
        right_angle: Optional[float] = None

        for jc in self.joints:
            ang = self._compute_joint_angle(jc, pose_landmarks, pts)
            if ang is not None:
                dname = jc.get("display_name", "")
                if "L" in dname or "left" in dname.lower():
                    left_angle = ang
                elif "R" in dname or "right" in dname.lower():
                    right_angle = ang

                if jc.get("is_rep_driver", False):
                    driver_angle = ang

        if driver_angle is None:
            driver_angle = left_angle if left_angle is not None else right_angle

        if driver_angle is not None:
            self.current_angle = float(driver_angle)
        if left_angle is not None:
            self.current_left_angle = float(left_angle)
        if right_angle is not None:
            self.current_right_angle = float(right_angle)

        # Evaluate real-time biomechanical checks
        alerts = self.check_engine.run_checks(
            pose_landmarks, pts, w, h, self.state, driver_angle, self.current_view
        )

        for alert in alerts:
            if alert not in self.current_rep_errors:
                self.current_rep_errors.append(alert)

        if alerts:
            self.active_error = alerts[0]
            self.current_feedback = alerts[0]
        elif self.state == "DOWN":
            self.active_error = None
            self.current_feedback = "Good form! Complete the movement smoothly."
        elif self.state == "UP" and self.rep_count == 0:
            self.active_error = None
            self.current_feedback = f"Ready: Begin {self.display_name}."

        # Buffer kinematics during active movement
        if self.state == "DOWN" and driver_angle is not None:
            self.rep_kinematics_buffer.append({
                "frame": self.frame_number,
                "angle": float(driver_angle),
                "left_angle": float(self.current_left_angle),
                "right_angle": float(self.current_right_angle),
            })
            if pose_landmarks is not None:
                self.rep_landmarks_buffer.append(pose_landmarks)

        # -------------------------------------------------------------
        # STATE MACHINE: REP TRIGGER (UP <-> DOWN)
        # -------------------------------------------------------------
        if not self.rep_trigger or driver_angle is None:
            return None

        direction = self.rep_trigger.get("direction", "decrease")
        enter_angle = float(self.rep_trigger.get("enter_angle", {}).get("value", 120.0))
        exit_angle = float(self.rep_trigger.get("exit_angle", {}).get("value", 160.0))
        depth_target = float(self.rep_trigger.get("depth_target", {}).get("value", 120.0))

        # Check for entering active repetition (UP -> DOWN)
        if self.state == "UP":
            starts_rep = (
                (direction == "decrease" and driver_angle <= enter_angle)
                or (direction == "increase" and driver_angle >= enter_angle)
            )
            if starts_rep:
                self.state = "DOWN"
                self.rep_start_frame = self.frame_number
                self.best_driver_angle = driver_angle
                self.current_rep_errors = []
                self.rep_kinematics_buffer = [{
                    "frame": self.frame_number,
                    "angle": float(driver_angle),
                    "left_angle": float(self.current_left_angle),
                    "right_angle": float(self.current_right_angle),
                }]
                self.rep_landmarks_buffer = [pose_landmarks] if pose_landmarks is not None else []
                self.check_engine.reset_rep_state()
                return None

        # Check for completing repetition (DOWN -> UP)
        if self.state == "DOWN":
            if self.best_driver_angle is not None:
                if direction == "decrease":
                    self.best_driver_angle = min(self.best_driver_angle, driver_angle)
                else:
                    self.best_driver_angle = max(self.best_driver_angle, driver_angle)

            completes_rep = (
                (direction == "decrease" and driver_angle >= exit_angle)
                or (direction == "increase" and driver_angle <= exit_angle)
            )

            if completes_rep:
                self.state = "UP"
                self.rep_count += 1

                # Check depth target compliance
                depth_ok = (
                    (direction == "decrease" and self.best_driver_angle <= depth_target)
                    or (direction == "increase" and self.best_driver_angle >= depth_target)
                )

                depth_alert_text = self.thresholds.get("depth_insufficient_alert", {}).get(
                    "value", "Movement depth insufficient"
                )

                if not depth_ok:
                    if depth_alert_text not in self.current_rep_errors:
                        self.current_rep_errors.append(depth_alert_text)

                # Compute Repetition Metrics
                angles_in_rep = [k["angle"] for k in self.rep_kinematics_buffer]
                rom = (
                    float(np.max(angles_in_rep) - np.min(angles_in_rep))
                    if len(angles_in_rep) > 1
                    else abs(enter_angle - depth_target)
                )

                duration_s = (
                    (self.frame_number - self.rep_start_frame) / self.fps
                    if self.rep_start_frame
                    else 2.0
                )

                if duration_s < 1.0:
                    speed = "Fast"
                elif duration_s <= 3.8:
                    speed = "Good"
                else:
                    speed = "Slow"

                if len(angles_in_rep) >= 3:
                    diffs = np.diff(np.array(angles_in_rep), n=2)
                    smoothness = float(1.0 / (1.0 + np.mean(np.abs(diffs)))) * 100.0
                else:
                    smoothness = 85.0

                # Form & Biomechanical Scoring
                has_errors = len(self.current_rep_errors) > 0
                if has_errors:
                    form = "incorrect"
                    score = max(40.0, 75.0 - (15.0 * len(self.current_rep_errors)))
                    rep_feedback = self.current_rep_errors[0]
                else:
                    form = "correct"
                    score = min(100.0, 92.0 + (rom / 10.0))
                    rep_feedback = "Good repetition! Maintain controlled pace."
                    self.clean_rep_count += 1

                self.current_feedback = rep_feedback

                # Evaluate ML model (if packaged)
                ml_res = self.model_eval.evaluate_repetition(
                    self.canonical_name,
                    self.rep_kinematics_buffer,
                    self.current_rep_errors,
                    landmark_frames=self.rep_landmarks_buffer,
                )

                completed_rep = {
                    "rep_index": int(self.rep_count),
                    "exercise": self.canonical_name,
                    "form": form,
                    "score": round(score, 1),
                    "range_of_motion": round(rom, 1),
                    "speed": speed,
                    "smoothness": round(smoothness, 1),
                    "feedback": rep_feedback,
                    "biomechanical_evaluation": {
                        "depth_target": depth_target,
                        "best_angle": round(self.best_driver_angle, 1) if self.best_driver_angle is not None else 0.0,
                        "depth_reached": bool(depth_ok),
                        "errors": list(self.current_rep_errors),
                    },
                    "ml_prediction": ml_res,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                }

                self.last_result = dict(completed_rep)
                self.rep_kinematics_buffer = []
                self.rep_landmarks_buffer = []
                self.current_rep_errors = []
                self.rep_start_frame = None

                return completed_rep

        return None

    def get_live_state(self, pose_landmarks=None) -> Dict[str, Any]:
        """Return the current assessment state for the live WebSocket client."""
        landmarks_output = []
        if pose_landmarks is not None:
            if hasattr(pose_landmarks, "landmark"):
                for lm in pose_landmarks.landmark:
                    landmarks_output.append({
                        "x": float(lm.x),
                        "y": float(lm.y),
                        "z": float(getattr(lm, "z", 0.0)),
                        "visibility": float(getattr(lm, "visibility", 1.0)),
                    })
            elif isinstance(pose_landmarks, (list, tuple)):
                for lm in pose_landmarks:
                    x, y, z, vis = get_coord(lm)
                    landmarks_output.append({"x": x, "y": y, "z": z, "visibility": vis})

        if self.state == "UP":
            if self.rep_count > 0:
                form = str(self.last_result.get("form", "Waiting")).lower()
                feedback = self.last_result.get("feedback", self.current_feedback)
                score = self.last_result.get("score", 0.0)
                rom = self.last_result.get("range_of_motion", 0.0)
                speed = self.last_result.get("speed", "Waiting")
                smoothness = self.last_result.get("smoothness", 0.0)
            else:
                form = "waiting"
                feedback = self.current_feedback
                score = 0.0
                rom = 0.0
                speed = "Waiting"
                smoothness = 0.0
        else:
            form = "incorrect" if self.active_error is not None else "correct"
            feedback = self.current_feedback
            score = self.last_result.get("score", 0.0)
            if self.rep_kinematics_buffer:
                angles = [k["angle"] for k in self.rep_kinematics_buffer]
                rom = float(np.max(angles) - np.min(angles))
            else:
                rom = 0.0

            if self.rep_start_frame is not None:
                elapsed = (self.frame_number - self.rep_start_frame) / self.fps
                if elapsed < 1.0:
                    speed = "Fast"
                elif elapsed <= 3.8:
                    speed = "Good"
                else:
                    speed = "Slow"
            else:
                speed = "Waiting"

            smoothness = 85.0

        return {
            "exercise": self.display_name,
            "exercise_id": self.canonical_name,
            "state": self.state,
            "rep_count": int(self.rep_count),
            "form": form,
            "error_type": self.active_error,
            "feedback": feedback,
            "score": float(score),
            "range_of_motion": float(rom),
            "speed": speed,
            "smoothness": float(smoothness),
            "angle": float(self.current_angle),
            "left_angle": float(self.current_left_angle),
            "right_angle": float(self.current_right_angle),
            "detected_view": self.current_view,
            "has_ml_model": self.model_eval.has_model(self.canonical_name),
            "landmarks": landmarks_output,
        }

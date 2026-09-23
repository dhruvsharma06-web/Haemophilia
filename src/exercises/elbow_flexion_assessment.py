"""WebSocket adapter for the elbow flexion/extension model."""

from pathlib import Path

from src.inference.elbow_inference import ElbowInference
from src.inference.elbow_live_tracker import LiveRepTracker
from src.pose.elbow_pose_extraction import _landmark_row


class ElbowFlexionAssessment:
    def __init__(
        self,
        model,
        device=None,
        fps: float = 20.0,
        data_dir: str = "data",
        save_artifacts: bool = True,
    ):
        self.fps = fps

        model_path = (
            Path(__file__).resolve().parents[2]
            / "models"
            / "elbow_flexion_lstm.pth"
        )

        self.predictor = ElbowInference(model_path)
        self.tracker = LiveRepTracker()

        self.last_rep_count = 0
        self.last_completed_rep = None

    def process_frame(
        self,
        frame,
        pose_landmarks,
        frame_number: int = 0,
    ):
        if pose_landmarks is None:
            self.tracker.update(None, self.predictor)
            return None

        row = _landmark_row(pose_landmarks)

        previous_count = self.tracker.rep_count

        result = self.tracker.update(
            row,
            self.predictor,
        )

        current_count = self.tracker.rep_count

        # No new completed rep.
        if current_count <= previous_count:
            return None

        # =========================================================
        # REP COMPLETED
        # =========================================================

        angle = float(
            result.get(
                "angle",
                0,
            )
        )

        rom = float(
            result.get(
                "rom",
                result.get(
                    "range_of_motion",
                    0,
                ),
            )
        )

        confidence = float(
            result.get(
                "prob",
                result.get(
                    "confidence",
                    0.5,
                ),
            )
        )

        # =========================================================
        # FORM
        #
        # For now:
        # - We still classify the completed rep.
        # - We DO NOT provide corrective feedback.
        # - We DO NOT provide an error message.
        # - We DO NOT provide an error image.
        #
        # Only ROM is used for this temporary form classification.
        # =========================================================

        if rom >= 75.0:
            form = "Correct"

            score = min(
                100.0,
                80.0 + (
                    (rom - 75.0)
                    / 25.0
                ) * 20.0,
            )

            error_type = ""

        elif rom >= 55.0:
            form = "Incorrect"

            score = (
                60.0
                + (
                    (rom - 55.0)
                    / 20.0
                ) * 15.0
            )

            error_type = "INSUFFICIENT_ROM"

        else:
            form = "Incorrect"

            score = max(
                30.0,
                (rom / 55.0) * 60.0,
            )

            error_type = "INSUFFICIENT_ROM"

        # =========================================================
        # MOVEMENT STATISTICS
        # =========================================================

        speed = str(
            result.get(
                "speed",
                "Unknown",
            )
        )

        smoothness = float(
            result.get(
                "smoothness",
                result.get(
                    "smoothness_raw",
                    0.0,
                ),
            )
        )

        duration = float(
            result.get(
                "duration",
                0.0,
            )
        )

        left_max_angle = float(
            result.get(
                "left_max_angle",
                0.0,
            )
        )

        right_max_angle = float(
            result.get(
                "right_max_angle",
                0.0,
            )
        )

        if confidence <= 1.0:
            confidence_percent = confidence * 100.0
        else:
            confidence_percent = confidence

        status = str(
            result.get(
                "rep_status",
                "COMPLETED",
            )
        )

        # =========================================================
        # COMPLETED REP
        # =========================================================

        completed = {
            "rep_number": current_count,

            "form": form,

            # Main statistics expected by Flutter.
            "score": round(
                score,
                1,
            ),

            "range_of_motion": round(
                rom,
                1,
            ),

            "rom": round(
                rom,
                1,
            ),

            "speed": speed,

            "smoothness": smoothness,

            "smoothness_raw": smoothness,

            "duration": round(
                duration,
                2,
            ),

            "left_max_angle": round(
                left_max_angle,
                1,
            ),

            "right_max_angle": round(
                right_max_angle,
                1,
            ),

            # Model confidence.
            "confidence": round(
                confidence_percent,
                1,
            ),

            "lstm_confidence": round(
                confidence_percent,
                1,
            ),

            # =====================================================
            # FEEDBACK TEMPORARILY DISABLED
            # =====================================================

            "error_type": error_type,

            "feedback": "",

            # Tracker information.
            "status": status,

            "rep_status": status,

            "angle": round(
                angle,
                1,
            ),
        }

        self.last_completed_rep = completed
        self.last_rep_count = current_count

        print(
            f"ELBOW REP {current_count}: "
            f"ROM={rom:.1f}°, "
            f"FORM={form}, "
            f"SCORE={score:.0f}"
        )

        return completed

    def get_live_state(
        self,
        pose_landmarks=None,
    ):
        result = self.tracker.result()

        # =========================================================
        # LANDMARKS FOR FLUTTER SKELETON
        # =========================================================

        landmarks = []

        if pose_landmarks is not None:
            for landmark in pose_landmarks.landmark:
                landmarks.append(
                    {
                        "x": float(
                            landmark.x
                        ),
                        "y": float(
                            landmark.y
                        ),
                        "z": float(
                            landmark.z
                        ),
                        "visibility": float(
                            landmark.visibility
                        ),
                    }
                )

        # =========================================================
        # CONFIDENCE
        # =========================================================

        confidence = float(
            result.get(
                "prob",
                0.5,
            )
        )

        if confidence <= 1.0:
            confidence *= 100.0

        # =========================================================
        # LIVE STATE
        # =========================================================

        state = result.get(
            "state",
            "DOWN",
        )

        angle = float(
            result.get(
                "angle",
                0,
            )
        )

        # Feedback is intentionally empty for now.
        #
        # We don't want the patient receiving corrective
        # feedback after bad reps at this stage.
        live_feedback = ""

        return {
            "exercise": "Elbow Flexion & Extension",

            "state": state,

            "rep_count": int(
                result.get(
                    "reps",
                    result.get(
                        "rep_count",
                        0,
                    ),
                )
            ),

            "form": result.get(
                "form",
                "Waiting",
            ),

            "confidence": confidence,

            "angle": angle,

            "score": float(
                result.get(
                    "rep_score",
                    0,
                )
                or 0
            ),

            "range_of_motion": float(
                result.get(
                    "rom",
                    0,
                )
                or 0
            ),

            "speed": result.get(
                "speed",
                "Waiting",
            ),

            "smoothness": float(
                result.get(
                    "smoothness",
                    0,
                )
                or 0
            ),

            # Feedback disabled.
            "error_type": "",

            "feedback": "",

            "rep_score": result.get(
                "rep_score",
                None,
            ),

            "rep_status": result.get(
                "rep_status",
                "WAITING",
            ),

            "calibrated": result.get(
                "calibrated",
                False,
            ),

            "flexion_threshold": result.get(
                "flexion_threshold",
                None,
            ),

            "extension_threshold": result.get(
                "extension_threshold",
                None,
            ),

            # Enables Flutter skeleton.
            "landmarks": landmarks,
        }
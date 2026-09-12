import uuid

import cv2
import mediapipe as mp
import numpy as np

from src.exercises.assisted_shoulder_flexion import (
    AssistedShoulderFlexionAssessment,
)
from backend.app.services.model_registry import model_registry


mp_pose = mp.solutions.pose


def to_python_value(value):
    """
    Convert NumPy values/arrays recursively into normal Python
    types so FastAPI can serialize the response as JSON.
    """

    if value is None:
        return None

    if isinstance(value, np.generic):
        return value.item()

    if isinstance(value, np.ndarray):
        return value.tolist()

    if isinstance(value, dict):
        return {
            key: to_python_value(val)
            for key, val in value.items()
        }

    if isinstance(value, (list, tuple)):
        return [
            to_python_value(item)
            for item in value
        ]

    return value


class AssessmentService:
    """
    Service responsible for running the AI assessment on uploaded videos.

    Current supported exercise:
        assisted_shoulder_flexion
    """

    def assess_video(self, video_path: str, exercise: str):
        """
        Run a complete video assessment.

        Parameters
        ----------
        video_path:
            Temporary/local path of the uploaded video.

        exercise:
            Exercise identifier.

        Returns
        -------
        dict
            JSON-serializable assessment response.
        """

        # ---------------------------------------------------------
        # Validate exercise
        # ---------------------------------------------------------

        if exercise != "assisted_shoulder_flexion":
            raise ValueError(
                f"Unsupported exercise: {exercise}"
            )

        # ---------------------------------------------------------
        # Load model
        # ---------------------------------------------------------

        model, device = model_registry.get_assisted_flexion()

        # ---------------------------------------------------------
        # Create assessment ID
        # ---------------------------------------------------------

        assessment_id = str(uuid.uuid4())

        # ---------------------------------------------------------
        # Open video
        # ---------------------------------------------------------

        capture = cv2.VideoCapture(video_path)

        if not capture.isOpened():
            raise ValueError(
                f"Could not open video: {video_path}"
            )

        # ---------------------------------------------------------
        # Get FPS
        # ---------------------------------------------------------

        fps = capture.get(cv2.CAP_PROP_FPS)

        if not fps or fps <= 0:
            fps = 30.0

        # ---------------------------------------------------------
        # Create exercise assessment processor
        # ---------------------------------------------------------

        assessment = AssistedShoulderFlexionAssessment(
            model=model,
            device=device,
            fps=fps,
            data_dir="data",
            save_artifacts=True,
        )

        reps = []

        try:

            # -----------------------------------------------------
            # MediaPipe Pose
            # -----------------------------------------------------

            with mp_pose.Pose(
                static_image_mode=False,
                model_complexity=1,
                smooth_landmarks=True,
                min_detection_confidence=0.5,
                min_tracking_confidence=0.5,
            ) as pose:

                frame_number = 0

                # -------------------------------------------------
                # Process every video frame
                # -------------------------------------------------

                while True:

                    success, frame = capture.read()

                    if not success:
                        break

                    frame_number += 1

                    # ---------------------------------------------
                    # BGR -> RGB for MediaPipe
                    # ---------------------------------------------

                    rgb_frame = cv2.cvtColor(
                        frame,
                        cv2.COLOR_BGR2RGB,
                    )

                    results = pose.process(rgb_frame)

                    # ---------------------------------------------
                    # No pose detected
                    # ---------------------------------------------

                    if results.pose_landmarks is None:
                        continue

                    # ---------------------------------------------
                    # Send frame to existing exercise logic
                    # ---------------------------------------------

                    result = assessment.process_frame(
                        frame,
                        results.pose_landmarks,
                        frame_number=frame_number,
                    )

                    # ---------------------------------------------
                    # A completed rep returns a result
                    # ---------------------------------------------

                    if result is not None:
                        reps.append(
                            to_python_value(result)
                        )

        finally:

            # -----------------------------------------------------
            # Always release video
            # -----------------------------------------------------

            capture.release()

        # ---------------------------------------------------------
        # Build API response
        # ---------------------------------------------------------

        response = {
            "assessment_id": assessment_id,
            "exercise": exercise,
            "media_type": "video",
            "status": "completed",
            "rep_count": len(reps),
            "reps": [
                self._format_rep(
                    rep,
                    index + 1,
                )
                for index, rep in enumerate(reps)
            ],
        }

        # ---------------------------------------------------------
        # Final NumPy -> Python conversion
        # ---------------------------------------------------------

        return to_python_value(response)

    @staticmethod
    def _format_rep(rep, rep_number: int):
        """
        Convert the internal exercise result into the stable
        API response format expected by Flutter.
        """

        # ---------------------------------------------------------
        # Form
        # ---------------------------------------------------------

        form = rep.get(
            "form",
            "Unknown",
        )

        # ---------------------------------------------------------
        # Predicted label
        # ---------------------------------------------------------

        form_lower = str(form).lower()

        if form_lower == "correct":
            predicted_label = "correct"

        elif form_lower == "incorrect":
            predicted_label = "incorrect"

        else:
            predicted_label = form_lower

        # ---------------------------------------------------------
        # Error frame
        # ---------------------------------------------------------

        error_frame_path = rep.get(
            "error_frame_path"
        )

        if error_frame_path:

            # Convert Windows backslashes to URL-style slashes
            # and keep only the generated filename.

            filename = (
                str(error_frame_path)
                .replace("\\", "/")
                .split("/")[-1]
            )

            error_frame_url = (
                "/v1/assets/error-frames/"
                + filename
            )

        else:

            error_frame_url = None

        # ---------------------------------------------------------
        # Return Flutter-friendly structure
        # ---------------------------------------------------------

        return {
            "rep_number": int(rep_number),

            "form": form,

            "predicted_label": predicted_label,

            "confidence": to_python_value(
                rep.get("confidence")
            ),

            "score": to_python_value(
                rep.get("score")
            ),

            "feedback": rep.get(
                "feedback"
            ),

            "error_type": rep.get(
                "error_type"
            ),

            "error_frame_url": error_frame_url,

            "measurements": {
                "range_of_motion": to_python_value(
                    rep.get("range_of_motion")
                ),

                "duration": to_python_value(
                    rep.get("duration")
                ),

                "smoothness": to_python_value(
                    rep.get("smoothness")
                ),
            },
        }


# -------------------------------------------------------------
# Global service instance
# -------------------------------------------------------------

assessment_service = AssessmentService()
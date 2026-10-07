import uuid

import cv2
import mediapipe as mp
import numpy as np

from backend.app.services.exercise_factory import create_assessment, normalize_exercise


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

    Uploaded-video assessment for all four exercise adapters.
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
        # Exercise processor dispatch
        # ---------------------------------------------------------

        exercise_norm = normalize_exercise(exercise)
        assessment_id = str(uuid.uuid4())
        capture = cv2.VideoCapture(str(video_path))
        reps = []

        try:
            source_fps = capture.get(cv2.CAP_PROP_FPS)
            if not capture.isOpened() or not np.isfinite(source_fps) or source_fps <= 0:
                raise ValueError("Provide a readable video with valid frame timing.")
            is_rotation = exercise_norm == "shoulder_rotation"
            if is_rotation and source_fps < 19.5:
                raise ValueError("Shoulder rotation videos must be recorded at 20 FPS or higher.")
            fps = 20.0 if is_rotation else source_fps
            assessment = create_assessment(exercise_norm, fps=fps)

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
                source_number, next_time = 0, 0.0

                # -------------------------------------------------
                # Process every video frame
                # -------------------------------------------------

                while True:

                    success, frame = capture.read()

                    if not success:
                        break

                    time = source_number / source_fps
                    source_number += 1
                    if is_rotation:
                        if time + 1e-6 < next_time:
                            continue
                        next_time += 1 / fps
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

                    if results.pose_landmarks is None and not is_rotation:
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
            "exercise": exercise_norm,
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

                "smoothness": None,
                "right_rom": to_python_value(rep.get("right_rom")),
                "left_rom": to_python_value(rep.get("left_rom")),
                "speed_deg_per_sec": to_python_value(rep.get("speed_deg_per_sec")),
            },
        }


# -------------------------------------------------------------
# Global service instance
# -------------------------------------------------------------

assessment_service = AssessmentService()

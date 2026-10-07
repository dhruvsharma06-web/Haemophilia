import json
import time

import cv2
import mediapipe as mp
import numpy as np
from fastapi import APIRouter, WebSocket
from starlette.websockets import WebSocketDisconnect

from backend.app.services.model_registry import model_registry
from src.exercises.assisted_shoulder_flexion import (
    AssistedShoulderFlexionAssessment,
)
from src.exercises.assisted_elbow_v2_assessment import (
    AssistedElbowV2Assessment,
)
from src.exercises.elbow_flexion_assessment import (
    ElbowFlexionAssessment,
)
from src.exercises.shoulder_rotation_assessment import (
    ShoulderRotationAssessment,
)


router = APIRouter(
    prefix="/v1/assessments",
    tags=["Live Assessments"],
)

mp_pose = mp.solutions.pose


def make_json_safe(value):
    if isinstance(value, dict):
        return {
            str(key): make_json_safe(val)
            for key, val in value.items()
        }

    if isinstance(value, (list, tuple)):
        return [
            make_json_safe(item)
            for item in value
        ]

    if isinstance(value, np.ndarray):
        return value.tolist()

    if isinstance(value, np.generic):
        return value.item()

    return value


from backend.app.services.exercise_factory import create_assessment as _create_assessment


@router.websocket("/live")
async def live_assessment(
    websocket: WebSocket,
):
    await websocket.accept()

    exercise = websocket.query_params.get(
        "exercise",
        "Assisted Shoulder Flexion",
    )

    print(
        "Live assessment WebSocket connected. "
        f"Exercise: {exercise}"
    )

    try:
        save_artifacts = websocket.query_params.get('practice', 'false').lower() != 'true'
        assessment = _create_assessment(exercise, save_artifacts=save_artifacts,
            starting_hand="Right" if websocket.query_params.get("starting_hand") == "Right" else "Left")

        with mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        ) as pose:

            frame_number = 0
            last_error_frame = None

            while True:
                message = (
                    await websocket.receive()
                )

                if (
                    message.get("type")
                    == "websocket.disconnect"
                ):
                    break

                # -------------------------------------------------
                # TEXT CONTROL MESSAGE
                # -------------------------------------------------

                text_message = message.get("text")

                if text_message:
                    try:
                        control = json.loads(
                            text_message
                        )
                    except json.JSONDecodeError:
                        control = {}

                    if (
                        control.get("type")
                        == "switch_exercise"
                    ):
                        next_exercise = (
                            control
                            .get("exercise")
                        )

                        if not next_exercise:
                            await websocket.send_json({
                                "type": "error",
                                "message":
                                    "Exercise name is required.",
                            })
                            continue

                        print(
                            "Switching exercise: "
                            f"{exercise} -> "
                            f"{next_exercise}"
                        )

                        assessment = (
                            _create_assessment(
                                next_exercise, save_artifacts=save_artifacts,
                                starting_hand="Right" if control.get("starting_hand") == "Right" else "Left"
                            )
                        )

                        exercise = next_exercise
                        frame_number = 0
                        last_error_frame = None

                        await websocket.send_json({
                            "type":
                                "exercise_switched",
                            "exercise":
                                exercise,
                        })

                    continue

                # -------------------------------------------------
                # CAMERA FRAME
                # -------------------------------------------------

                frame_bytes = message.get(
                    "bytes"
                )

                if not frame_bytes:
                    continue

                frame_number += 1

                if frame_number % 30 == 0:
                    print(
                        f"Received {frame_number} "
                        f"frames. Exercise: {exercise}"
                    )

                encoded = np.frombuffer(
                    frame_bytes,
                    dtype=np.uint8,
                )

                frame = cv2.imdecode(
                    encoded,
                    cv2.IMREAD_COLOR,
                )

                if frame is None:
                    await websocket.send_json({
                        "type": "error",
                        "message":
                            "Could not decode "
                            "camera frame.",
                    })
                    continue

                rgb_frame = cv2.cvtColor(
                    frame,
                    cv2.COLOR_BGR2RGB,
                )

                results = pose.process(
                    rgb_frame
                )

                extra = {}
                if getattr(assessment, 'uses_world_landmarks', False):
                    extra = {'world_landmarks': results.pose_world_landmarks,
                             'timestamp_sec': time.monotonic()}
                elif getattr(assessment, 'uses_timestamps', False):
                    extra = {'timestamp_sec': time.monotonic()}
                completed_rep = assessment.process_frame(
                    frame, results.pose_landmarks, frame_number=frame_number, **extra)

                live_state = (
                    assessment.get_live_state(
                        results.pose_landmarks
                    )
                )

                error_frame = live_state.pop('error_frame_path', None)
                if error_frame and error_frame != last_error_frame:
                    live_state['error_frame_path'] = error_frame
                    last_error_frame = error_frame

                response = {
                    "type": "live_state",
                    "exercise": exercise,
                    **live_state,
                }

                if completed_rep is not None:
                    response[
                        "completed_rep"
                    ] = completed_rep

                response = make_json_safe(
                    response
                )

                await websocket.send_json(
                    response
                )

    except WebSocketDisconnect:
        print(
            "Live assessment client disconnected."
        )

    except Exception as exc:
        print(
            f"Live assessment error: {exc}"
        )

        try:
            await websocket.send_json({
                "type": "error",
                "message": str(exc),
            })
        except Exception:
            pass

    finally:
        print(
            "Live assessment session ended. "
            f"Exercise: {exercise}"
        )

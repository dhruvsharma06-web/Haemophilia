import json
import time

import cv2
import mediapipe as mp
import numpy as np
from fastapi import APIRouter, WebSocket
from starlette.websockets import WebSocketDisconnect
from starlette.concurrency import run_in_threadpool

from backend.app.services.exercise_factory import create_assessment, normalize_exercise


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


def _create_assessment(exercise: str):
    return create_assessment(exercise, fps=20.0)


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
        exercise = normalize_exercise(exercise)
        assessment = _create_assessment(exercise)

        with mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        ) as pose:

            frame_number = 0
            pending_timestamp = None

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
                    if not isinstance(control, dict):
                        continue

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
                                normalize_exercise(next_exercise)
                            )
                        )

                        exercise = normalize_exercise(next_exercise)
                        frame_number = 0
                        pending_timestamp = None

                        await websocket.send_json({
                            "type":
                                "exercise_switched",
                            "exercise":
                                exercise,
                        })

                    elif control.get("type") == "frame_metadata":
                        value = control.get("timestamp_ms")
                        if isinstance(value, (int, float)) and np.isfinite(value):
                            pending_timestamp = float(value)
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
                frame_timestamp = pending_timestamp
                pending_timestamp = None

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

                results = await run_in_threadpool(
                    pose.process,
                    rgb_frame
                )

                timing = {}
                if exercise == "shoulder_rotation":
                    timing["timestamp_ms"] = (frame_timestamp if frame_timestamp is not None
                                               else time.monotonic() * 1000)
                completed_rep = assessment.process_frame(
                        frame,
                        results.pose_landmarks,
                        frame_number=frame_number,
                        **timing,
                    )

                live_state = (
                    assessment.get_live_state(
                        results.pose_landmarks
                    )
                )

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

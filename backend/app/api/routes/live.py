import cv2
import mediapipe as mp
import numpy as np

from fastapi import APIRouter, WebSocket
from starlette.websockets import WebSocketDisconnect

from backend.app.services.model_registry import (
    model_registry,
)

from src.exercises.assisted_shoulder_flexion import (
    AssistedShoulderFlexionAssessment,
)


router = APIRouter(
    prefix="/v1/assessments",
    tags=["Live Assessments"],
)

mp_pose = mp.solutions.pose


def make_json_safe(value):
    """
    Convert NumPy/Python values into JSON-serializable values.
    """
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


@router.websocket("/live")
async def live_assessment(
    websocket: WebSocket,
):
    await websocket.accept()

    print(
        "Live assessment WebSocket connected."
    )

    try:
        model, device = (
            model_registry.get_assisted_flexion()
        )

        assessment = (
            AssistedShoulderFlexionAssessment(
                model=model,
                device=device,
                fps=20.0,
                data_dir="data",
                save_artifacts=True,
            )
        )

        with mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        ) as pose:

            frame_number = 0

            while True:
                message = await websocket.receive()

                if message.get("type") == (
                    "websocket.disconnect"
                ):
                    break

                frame_bytes = message.get(
                    "bytes"
                )

                if not frame_bytes:
                    continue

                frame_number += 1

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
                        "message": (
                            "Could not decode camera frame."
                        ),
                    })
                    continue

                rgb_frame = cv2.cvtColor(
                    frame,
                    cv2.COLOR_BGR2RGB,
                )

                results = pose.process(
                    rgb_frame
                )

                completed_rep = (
                    assessment.process_frame(
                        frame,
                        results.pose_landmarks,
                        frame_number=frame_number,
                    )
                )

                live_state = (
                    assessment.get_live_state(
                        results.pose_landmarks
                    )
                )

                response = {
                    "type": "live_state",
                    **live_state,
                }

                if completed_rep is not None:
                    response[
                        "completed_rep"
                    ] = completed_rep

                # Convert NumPy float32/int32/etc.
                # into normal JSON-compatible types.
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
            "Live assessment session ended."
        )
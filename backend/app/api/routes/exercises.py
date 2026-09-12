from fastapi import APIRouter

router = APIRouter(prefix="/v1", tags=["Exercises"])


@router.get("/exercises")
def get_exercises():
    return {
        "exercises": [
            {
                "id": "assisted_shoulder_flexion",
                "name": "Assisted Shoulder Flexion",
                "available": True,
            },
            {
                "id": "shoulder_rotation",
                "name": "Shoulder Rotation",
                "available": False,
            },
        ]
    }
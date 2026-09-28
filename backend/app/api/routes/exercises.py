from fastapi import APIRouter

router = APIRouter(prefix="/v1", tags=["Exercises"])


@router.get("/exercises")
def get_exercises():
    return {
        "exercises": [
            {
                "id": "assisted_shoulder_flexion",
                "name": "Assisted Shoulder Flexion with Bar",
                "target_joint": "Shoulders",
                "status": "validated",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Two-handed bar elevation exercise targeting shoulder mobility "
                    "and joint preservation."
                ),
            },
            {
                "id": "shoulder_rotation",
                "name": "Shoulder Rotation",
                "target_joint": "Rotator Cuff",
                "status": "work_in_progress",
                "available": True,
                "is_work_in_progress": True,
                "description": (
                    "Bilateral internal and external rotation with elbows flexed 90° "
                    "pinned to torso (Work in Progress • Prototype movement)."
                ),
            },
            {
                "id": "assisted_elbow_flexion",
                "name": "Assisted Elbow Flexion",
                "target_joint": "Elbow Joint",
                "status": "validated",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Supported elbow bending using contralateral hand guidance to "
                    "protect recovering joints."
                ),
            },
            {
                "id": "elbow_flexion_extension",
                "name": "Elbow Flexion & Extension",
                "target_joint": "Elbow Joint",
                "status": "validated",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Smooth, controlled elbow bending and straightening throughout "
                    "comfortable pain-free range of motion."
                ),
            },
        ]
    }
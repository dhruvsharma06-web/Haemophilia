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
                "model_version": "Shoulder_Rotation_LSTM",
                "clinically_validated": False,
                "name": "Shoulder Rotation",
                "target_joint": "Rotator Cuff",
                "status": "available",
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Bilateral internal and external rotation with elbows flexed 90° "
                    "pinned to torso. Follow the clinician-prescribed range and pace."
                ),
            },
            {
                "id": "assisted_elbow_flexion_v5",
                "name": "Assisted Elbow Flexion",
                "target_joint": "Elbow Joint",
                "status": "experimental", "experimental": True,
                "model_version": "SVM_V5_Controller_V6_Telemetry2",
                "clinically_validated": False, "available": True,
                "is_work_in_progress": False,
                "description": "Alternate left and right with opposite-hand support. Experimental model feedback.",
            },
            {
                "id": "elbow_flexion_extension",
                "name": "Elbow Flexion & Extension",
                "target_joint": "Elbow Joint",
                "status": "available",
                "model_version": "Elbow_LSTM_V4_22F",
                "clinically_validated": False,
                "available": True,
                "is_work_in_progress": False,
                "description": (
                    "Smooth, controlled elbow bending and straightening throughout "
                    "comfortable pain-free range of motion."
                ),
            },
        ]
    }

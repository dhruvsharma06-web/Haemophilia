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
        ] + [
            {
                "id": exercise_id,
                "name": name,
                "target_joint": "Knee / Hip",
                "status": "experimental",
                "experimental": True,
                "clinically_validated": False,
                "available": True,
                "is_work_in_progress": False,
                "assessment_method": "experimental_rules",
                "model_version": "LowerBody_Rules_v1",
                "description": description,
            }
            for exercise_id, name, description in (
                ("heel_slide", "Heel Slide", "Slide your heel on the surface through your prescribed comfortable range."),
                ("mini_squat", "Mini Squat", "Controlled shallow squat with knee and heel tracking."),
                ("seated_knee_extension", "Seated Knee Extension", "Seated knee straightening with posture tracking."),
                ("straight_leg_raise", "Straight Leg Raise", "Lying leg raise with knee and trunk tracking."),
                ("terminal_knee_extension", "Terminal Knee Extension", "Knee straightening over a support with thigh tracking."),
                ("squat", "Squat", "Controlled squat within the range prescribed by your clinician."),
            )
        ]
    }

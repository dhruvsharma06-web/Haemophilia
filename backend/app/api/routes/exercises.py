from fastapi import APIRouter

router = APIRouter(prefix="/v1", tags=["Exercises"])


@router.get("/exercises")
def get_exercises():
    return {
        "exercises": [
            # Upper-body exercises (existing)
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
                    "pinned to torso (Work in Progress — Prototype movement)."
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
            # Lower-body exercises (integrated from senior implementations)
            {
                "id": "heel_slide",
                "name": "Heel Slide",
                "target_joint": "Knee / Hip Joint",
                "status": "ready",
                "available": True,
                "is_work_in_progress": False,
                "has_trained_model": False,
                "description": (
                    "Supine knee flexion and extension sliding the heel along the "
                    "treatment surface to safely restore knee range of motion."
                ),
            },
            {
                "id": "mini_squat",
                "name": "Mini Squat",
                "target_joint": "Knee / Quadriceps",
                "status": "ready",
                "available": True,
                "is_work_in_progress": False,
                "has_trained_model": True,
                "description": (
                    "Controlled shallow squat assessing knee varus/valgus alignment, "
                    "heel contact, and knees-past-toes displacement."
                ),
            },
            {
                "id": "seated_knee_extension",
                "name": "Seated Knee Extension",
                "target_joint": "Quadriceps / Knee",
                "status": "ready",
                "available": True,
                "is_work_in_progress": False,
                "has_trained_model": True,
                "description": (
                    "Seated knee extension strengthening quadriceps with real-time "
                    "monitoring for hip lifting, back slouching, and trunk rocking."
                ),
            },
            {
                "id": "straight_leg_raise",
                "name": "Straight Leg Raise",
                "target_joint": "Hip Flexors / Quadriceps",
                "status": "ready",
                "available": True,
                "is_work_in_progress": False,
                "has_trained_model": True,
                "description": (
                    "Supine straight leg elevation maintaining complete knee extension "
                    "and evaluating hip lifting and head position."
                ),
            },
            {
                "id": "terminal_knee_extension",
                "name": "Terminal Knee Extension",
                "target_joint": "Knee / VMO",
                "status": "ready",
                "available": True,
                "is_work_in_progress": False,
                "has_trained_model": False,
                "description": (
                    "Supine knee straightening over a bolster or pillow to isolate "
                    "the vastus medialis obliquus and restore terminal extension."
                ),
            },
            {
                "id": "squat",
                "name": "Squat",
                "target_joint": "Lower Body / Hips / Knees",
                "status": "ready",
                "available": True,
                "is_work_in_progress": False,
                "has_trained_model": False,
                "description": (
                    "Full functional squat assessment tracking knee valgus, depth target, "
                    "torso lean, heel lift, and lumbar rounding."
                ),
            },
        ]
    }

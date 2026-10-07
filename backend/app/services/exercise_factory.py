"""Canonical exercise dispatch shared by uploaded videos and live sessions."""
import re

from backend.app.core.config import PROJECT_ROOT
from backend.app.services.model_registry import model_registry

SUPPORTED_EXERCISES = {
    "assisted_shoulder_flexion", "shoulder_rotation",
    "assisted_elbow_flexion", "elbow_flexion_extension",
}


def normalize_exercise(exercise):
    value = re.sub(r"[\s_-]+", "_", (exercise or "").strip().lower().replace("&", "and"))
    aliases = {
        "assisted_shoulder_flexion_with_bar": "assisted_shoulder_flexion",
        "assisted_elbow": "assisted_elbow_flexion",
        "elbow_flexion": "elbow_flexion_extension",
        "elbow_flexion_and_extension": "elbow_flexion_extension",
    }
    value = aliases.get(value, value)
    if value not in SUPPORTED_EXERCISES:
        raise ValueError(f"Unsupported exercise: {exercise}")
    return value


def create_assessment(exercise, fps=20.0, save_artifacts=True):
    exercise = normalize_exercise(exercise)
    if exercise == "shoulder_rotation":
        from src.exercises.shoulder_rotation_assessment import ShoulderRotationAssessment
        model, device = model_registry.get_shoulder_rotation()
        assessment_type = ShoulderRotationAssessment
    elif exercise == "assisted_shoulder_flexion":
        from src.exercises.assisted_shoulder_flexion import AssistedShoulderFlexionAssessment
        model, device = model_registry.get_assisted_flexion()
        assessment_type = AssistedShoulderFlexionAssessment
    elif exercise == "assisted_elbow_flexion":
        from src.exercises.assisted_elbow_flexion import AssistedElbowFlexionAssessment
        model, device = model_registry.get_assisted_elbow_flexion()
        assessment_type = AssistedElbowFlexionAssessment
    else:
        from src.exercises.elbow_flexion_assessment import ElbowFlexionAssessment
        model, device = model_registry.get_elbow_flexion_extension()
        assessment_type = ElbowFlexionAssessment
    return assessment_type(model=model, device=device, fps=fps,
                           data_dir=PROJECT_ROOT / "data", save_artifacts=save_artifacts)

from backend.app.services.model_registry import model_registry
from src.exercises.assisted_shoulder_flexion import (
    AssistedShoulderFlexionAssessment,
)
from src.exercises.elbow_v4_assessment import ElbowV4Assessment
from src.exercises.shoulder_rotation_assessment import (
    ShoulderRotationAssessment,
)

def create_assessment(exercise: str, save_artifacts: bool = True, fps: float = 20.0, starting_hand: str = "Left"):
    exercise_normalized = (
        (exercise or "")
        .strip()
        .lower()
        .replace("-", "_")
        .replace(" ", "_")
    )

    if 'assisted_elbow' in exercise_normalized:
        from src.exercises.assisted_elbow_v5_assessment import AssistedElbowV5Assessment
        model, device = model_registry.get_assisted_elbow_v5()
        return AssistedElbowV5Assessment(model, device, fps, 'data', save_artifacts,
                                        starting_hand=starting_hand)

    if (
        "elbow" in exercise_normalized
        or exercise_normalized in {
            "elbow_flexion",
            "elbow_flexion_extension",
            "elbow_flexion_and_extension",
        }
    ):
        model, device = model_registry.get_elbow_flexion_extension()
        return ElbowV4Assessment(
            model=model,
            device=device,
            fps=fps,
            data_dir="data",
            save_artifacts=save_artifacts,
        )

    if (
        "rotation" in exercise_normalized
        or exercise_normalized in {
            "shoulder_rotation",
        }
    ):
        model, device = (
            model_registry.get_shoulder_rotation()
        )

        return ShoulderRotationAssessment(
            model=model,
            device=device,
            fps=fps,
            data_dir="data",
            save_artifacts=save_artifacts,
        )

    if exercise_normalized not in {"assisted_shoulder_flexion", "assisted_shoulder_flexion_with_bar", "assisted_shoulder_flexion_with_a_bar"}:
        raise ValueError(f"Unsupported exercise: {exercise}")
    model, device = model_registry.get_assisted_flexion()

    return AssistedShoulderFlexionAssessment(
        model=model,
        device=device,
        fps=fps,
        data_dir="data",
        save_artifacts=save_artifacts,
    )

from pathlib import Path
from typing import Optional

from src.exercises.assisted_shoulder_flexion import load_model


class ModelRegistry:
    def __init__(self):
        self._assisted_flexion_model = None
        self._assisted_flexion_device = None

    def get_assisted_flexion(self):
        """Return the shared assisted shoulder flexion LSTM model."""
        if self._assisted_flexion_model is None:
            model_path = (
                Path(__file__).resolve().parents[3]
                / "models"
                / "assisted_shoulder_lstm.pth"
            )

            if not model_path.exists():
                raise FileNotFoundError(
                    f"Assisted flexion model not found: {model_path}"
                )

            (
                self._assisted_flexion_model,
                self._assisted_flexion_device,
            ) = load_model(model_path)

        return (
            self._assisted_flexion_model,
            self._assisted_flexion_device,
        )


model_registry = ModelRegistry()
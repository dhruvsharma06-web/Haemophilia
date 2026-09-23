from pathlib import Path

from src.exercises.assisted_shoulder_flexion import load_model
from src.models.lstm_model import ExerciseLSTM
import torch


class ModelRegistry:
    def __init__(self):
        self._assisted_flexion_model = None
        self._assisted_flexion_device = None

        self._shoulder_rotation_model = None
        self._shoulder_rotation_device = None

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

    def get_shoulder_rotation(self):
        """Return the shared shoulder rotation LSTM model."""
        if self._shoulder_rotation_model is None:
            model_path = (
                Path(__file__).resolve().parents[3]
                / "models"
                / "shoulder_rotation_lstm.pth"
            )

            if not model_path.exists():
                raise FileNotFoundError(
                    f"Shoulder rotation model not found: {model_path}"
                )

            device = torch.device(
                "cuda"
                if torch.cuda.is_available()
                else "cpu"
            )

            model = ExerciseLSTM(
                input_size=10,
                hidden_size=64,
                num_layers=2,
                num_classes=2,
                dropout=0.3,
            )

            checkpoint = torch.load(
                model_path,
                map_location=device,
                weights_only=True,
            )

            if isinstance(checkpoint, dict):
                if "model_state_dict" in checkpoint:
                    state_dict = checkpoint["model_state_dict"]
                elif "state_dict" in checkpoint:
                    state_dict = checkpoint["state_dict"]
                else:
                    state_dict = checkpoint
            else:
                state_dict = checkpoint

            model.load_state_dict(state_dict)
            model.to(device)
            model.eval()

            self._shoulder_rotation_model = model
            self._shoulder_rotation_device = device

        return (
            self._shoulder_rotation_model,
            self._shoulder_rotation_device,
        )


model_registry = ModelRegistry()
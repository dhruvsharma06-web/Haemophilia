from pathlib import Path
import os

from src.exercises.assisted_shoulder_flexion import load_model
import torch


class ModelRegistry:
    def __init__(self):
        self._assisted_flexion_model = None
        self._assisted_flexion_device = None

        self._shoulder_rotation_model = None
        self._shoulder_rotation_device = None
        self.shoulder_rotation_model_path = None

        self._assisted_elbow_model_human_verified = None
        self._assisted_elbow_device_human_verified = None

        self._elbow_flexion_extension_model = None
        self._elbow_flexion_extension_device = None

    def get_elbow_flexion_extension(self):
        """Return the authoritative haemophilia-final elbow flexion & extension LSTM model."""
        if self._elbow_flexion_extension_model is None:
            model_path = (
                Path(__file__).resolve().parents[3]
                / "models"
                / "elbow_lstm.pth"
            )

            if not model_path.exists():
                raise FileNotFoundError(
                    f"Elbow flexion extension model not found: {model_path}"
                )

            device = torch.device(
                "cuda"
                if torch.cuda.is_available()
                else "cpu"
            )

            from src.models.elbow_lstm import ElbowLSTM

            model = ElbowLSTM(
                input_size=8,
                hidden_size=128,
                num_layers=2,
            )

            model.load_state_dict(
                torch.load(
                    model_path,
                    map_location=device,
                    weights_only=True,
                )
            )
            model.to(device)
            model.eval()

            self._elbow_flexion_extension_model = model
            self._elbow_flexion_extension_device = device

        return (
            self._elbow_flexion_extension_model,
            self._elbow_flexion_extension_device,
        )

    def get_assisted_elbow_flexion_human_verified(self):
        """Return the shared human-verified assisted elbow flexion LSTM model."""
        if self._assisted_elbow_model_human_verified is None:
            model_path = (
                Path(__file__).resolve().parents[3]
                / "models"
                / "assisted_elbow_lstm_human_verified.pth"
            )

            if not model_path.exists():
                raise FileNotFoundError(
                    f"Assisted elbow flexion human-verified model not found: {model_path}"
                )

            from src.exercises.assisted_elbow_flexion import (
                load_model as load_elbow_model,
            )

            (
                self._assisted_elbow_model_human_verified,
                self._assisted_elbow_device_human_verified,
            ) = load_elbow_model(model_path)

        return (
            self._assisted_elbow_model_human_verified,
            self._assisted_elbow_device_human_verified,
        )

    def get_assisted_elbow_flexion(self):
        """Return the authoritative assisted elbow flexion LSTM model."""
        return self.get_assisted_elbow_flexion_human_verified()

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
        """Return the installed shoulder model or an explicit model override."""
        if self._shoulder_rotation_model is None:
            from src.models.shoulder_rotation_loader import load_shoulder_rotation_model
            root = Path(__file__).resolve().parents[3]
            model_path = Path(os.environ.get(
                "SHOULDER_ROTATION_MODEL",
                "models/shoulder_rotation/shoulder_rotation_classifier.joblib",
            ))
            if not model_path.is_absolute():
                model_path = root / model_path
            model, device = load_shoulder_rotation_model(model_path)

            self._shoulder_rotation_model = model
            self._shoulder_rotation_device = device
            self.shoulder_rotation_model_path = model_path

        return (
            self._shoulder_rotation_model,
            self._shoulder_rotation_device,
        )


model_registry = ModelRegistry()

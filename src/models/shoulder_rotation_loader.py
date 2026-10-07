"""Load either a shoulder LSTM checkpoint or the compact trained classifier."""
from pathlib import Path

import torch

from src.models.lstm_model import ExerciseLSTM


def load_shoulder_rotation_model(path):
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"Shoulder rotation model not found: {path}")
    if path.suffix == ".joblib":
        from src.models.shoulder_rotation_tabular import load_tabular_model
        return load_tabular_model(path), torch.device("cpu")
    if path.suffix != ".pth":
        raise ValueError("Shoulder rotation models must use .pth or .joblib.")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = ExerciseLSTM(input_size=10, hidden_size=64, num_layers=2,
                         num_classes=2, dropout=0.3)
    checkpoint = torch.load(path, map_location=device, weights_only=True)
    if isinstance(checkpoint, dict):
        checkpoint = checkpoint.get("model_state_dict", checkpoint.get("state_dict", checkpoint))
    model.load_state_dict(checkpoint)
    return model.to(device).eval(), device

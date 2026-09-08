import sys
from pathlib import Path

import numpy as np
import torch

# Project root
BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.models.lstm_model import ExerciseLSTM


SEQUENCE_LENGTH = 128

MODEL_PATH = BASE_DIR / "models" / "assisted_shoulder_lstm.pth"


def load_model():

    device = torch.device(
        "cuda" if torch.cuda.is_available() else "cpu"
    )

    model = ExerciseLSTM(
        input_size=6,
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3
    )

    model.load_state_dict(
        torch.load(
            MODEL_PATH,
            map_location=device
        )
    )

    model.to(device)
    model.eval()

    return model, device


def prepare_sequence(sequence_file):

    sequence = np.load(sequence_file).astype(np.float32)

    # Safety check
    if sequence.shape != (SEQUENCE_LENGTH, 2):
        raise ValueError(
            f"Expected sequence shape "
            f"(128, 2), got {sequence.shape}"
        )

    tensor = torch.tensor(
        sequence,
        dtype=torch.float32
    )

    # Add batch dimension
    tensor = tensor.unsqueeze(0)

    return tensor


def predict(sequence_file):

    model, device = load_model()

    x = prepare_sequence(sequence_file)
    x = x.to(device)

    with torch.no_grad():

        output = model(x)

        probabilities = torch.softmax(
            output,
            dim=1
        )

        prediction = torch.argmax(
            probabilities,
            dim=1
        ).item()

    labels = {
        0: "correct",
        1: "incorrect"
    }

    predicted_label = labels[prediction]

    confidence = (
        probabilities[0][prediction].item() * 100
    )

    print("\n" + "=" * 50)
    print("EXERCISE PREDICTION")
    print("=" * 50)

    print(f"Sequence : {Path(sequence_file).name}")
    print(f"Prediction: {predicted_label.upper()}")
    print(f"Confidence: {confidence:.2f}%")

    print("\nClass probabilities:")

    print(
        f"Correct   : "
        f"{probabilities[0][0].item() * 100:.2f}%"
    )

    print(
        f"Incorrect : "
        f"{probabilities[0][1].item() * 100:.2f}%"
    )


if __name__ == "__main__":

    if len(sys.argv) < 2:

        print("Usage:")
        print(
            "python src/inference/predict_exercise.py "
            "<sequence.npy>"
        )

        sys.exit(1)

    predict(sys.argv[1])
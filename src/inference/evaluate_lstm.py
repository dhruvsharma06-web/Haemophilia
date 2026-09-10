import sys
from pathlib import Path

import numpy as np
import torch

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.models.lstm_model import ExerciseLSTM


SEQUENCE_DIR = BASE_DIR / "processed_data" / "sequences"
MODEL_PATH = BASE_DIR / "models" / "assisted_shoulder_lstm.pth"


def get_person(file_name):
    if file_name.startswith("20260825_12"):
        return "person1"

    if file_name.startswith("20260825_14"):
        return "person2"

    if file_name.startswith("VID20260825"):
        return "person3"

    return "unknown"


def load_model(device):

    model = ExerciseLSTM(
        input_size=10,
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

    return model


def main():

    device = torch.device(
        "cuda" if torch.cuda.is_available() else "cpu"
    )

    model = load_model(device)

    # Person 3 was never used for training
    test_files = []

    for file in sorted(SEQUENCE_DIR.glob("*.npy")):

        if get_person(file.name) == "person3":
            test_files.append(file)

    if not test_files:
        print("No test sequences found.")
        return

    correct_predictions = 0

    total = len(test_files)

    # Confusion matrix
    true_correct_pred_correct = 0
    true_correct_pred_incorrect = 0
    true_incorrect_pred_correct = 0
    true_incorrect_pred_incorrect = 0

    confidences = []

    print("=" * 70)
    print("LSTM TEST SET EVALUATION")
    print("=" * 70)

    print(f"Test samples: {total}")
    print(f"Device: {device}\n")

    for file in test_files:

        sequence = np.load(file).astype(np.float32)

        x = torch.tensor(
            sequence,
            dtype=torch.float32
        ).unsqueeze(0).to(device)

        # True label from filename
        if "_correct.npy" in file.name:
            true_label = "correct"
            true_class = 0
        else:
            true_label = "incorrect"
            true_class = 1

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

        predicted_label = (
            "correct"
            if prediction == 0
            else "incorrect"
        )

        confidence = (
            probabilities[0][prediction].item() * 100
        )

        confidences.append(confidence)

        if prediction == true_class:
            correct_predictions += 1

        # Confusion matrix counts
        if true_class == 0 and prediction == 0:
            true_correct_pred_correct += 1

        elif true_class == 0 and prediction == 1:
            true_correct_pred_incorrect += 1

        elif true_class == 1 and prediction == 0:
            true_incorrect_pred_correct += 1

        elif true_class == 1 and prediction == 1:
            true_incorrect_pred_incorrect += 1

        print(
            f"{file.name:<55} "
            f"True: {true_label:<9} "
            f"Pred: {predicted_label:<9} "
            f"{confidence:5.1f}%"
        )

    accuracy = (
        correct_predictions / total * 100
    )

    avg_confidence = np.mean(confidences)

    # Precision / recall
    tp_correct = true_correct_pred_correct
    fp_correct = true_incorrect_pred_correct
    fn_correct = true_correct_pred_incorrect

    precision_correct = (
        tp_correct / (tp_correct + fp_correct)
        if (tp_correct + fp_correct) > 0
        else 0
    )

    recall_correct = (
        tp_correct / (tp_correct + fn_correct)
        if (tp_correct + fn_correct) > 0
        else 0
    )

    tp_incorrect = true_incorrect_pred_incorrect
    fp_incorrect = true_correct_pred_incorrect
    fn_incorrect = true_incorrect_pred_correct

    precision_incorrect = (
        tp_incorrect / (tp_incorrect + fp_incorrect)
        if (tp_incorrect + fp_incorrect) > 0
        else 0
    )

    recall_incorrect = (
        tp_incorrect / (tp_incorrect + fn_incorrect)
        if (tp_incorrect + fn_incorrect) > 0
        else 0
    )

    print("\n" + "=" * 70)
    print("RESULTS")
    print("=" * 70)

    print(
        f"Correct predictions : "
        f"{correct_predictions}/{total}"
    )

    print(f"Accuracy            : {accuracy:.2f}%")

    print(
        f"Average confidence  : "
        f"{avg_confidence:.2f}%"
    )

    print("\nConfusion Matrix:")
    print()
    print("                 Pred Correct   Pred Incorrect")
    print(
        f"True Correct        "
        f"{true_correct_pred_correct:^12}   "
        f"{true_correct_pred_incorrect:^14}"
    )
    print(
        f"True Incorrect      "
        f"{true_incorrect_pred_correct:^12}   "
        f"{true_incorrect_pred_incorrect:^14}"
    )

    print("\nClassification metrics:")

    print(
        f"Correct   → "
        f"Precision: {precision_correct * 100:.2f}%  "
        f"Recall: {recall_correct * 100:.2f}%"
    )

    print(
        f"Incorrect → "
        f"Precision: {precision_incorrect * 100:.2f}%  "
        f"Recall: {recall_incorrect * 100:.2f}%"
    )


if __name__ == "__main__":
    main()
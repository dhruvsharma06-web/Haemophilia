import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.models.lstm_model import ExerciseLSTM


SEQUENCE_DIR = BASE_DIR / "processed_data" / "sequences"
MODEL_DIR = BASE_DIR / "models"

BATCH_SIZE = 8
EPOCHS = 50
LEARNING_RATE = 0.001


class ExerciseDataset(Dataset):

    def __init__(self, files):
        self.files = files

    def __len__(self):
        return len(self.files)

    def __getitem__(self, index):

        file = self.files[index]

        x = np.load(file).astype(np.float32)

        if "_correct.npy" in file.name:
            label = 0
        else:
            label = 1

        return (
            torch.tensor(x),
            torch.tensor(label, dtype=torch.long)
        )


def get_person(file_name):

    if file_name.startswith("20260825_12"):
        return "person1"

    if file_name.startswith("20260825_14"):
        return "person2"

    if file_name.startswith("VID20260825"):
        return "person3"

    return "unknown"


def main():

    files = sorted(SEQUENCE_DIR.glob("*.npy"))

    if not files:
        print("No sequence files found.")
        return

    train_files = []
    test_files = []

    for file in files:

        person = get_person(file.name)

        if person in ["person1", "person2"]:
            train_files.append(file)

        elif person == "person3":
            test_files.append(file)

    print("=" * 60)
    print("LSTM TRAINING")
    print("=" * 60)

    print(f"Total sequences : {len(files)}")
    print(f"Training        : {len(train_files)}")
    print(f"Testing         : {len(test_files)}")

    train_dataset = ExerciseDataset(train_files)
    test_dataset = ExerciseDataset(test_files)

    train_loader = DataLoader(
        train_dataset,
        batch_size=BATCH_SIZE,
        shuffle=True
    )

    test_loader = DataLoader(
        test_dataset,
        batch_size=BATCH_SIZE,
        shuffle=False
    )

    device = torch.device(
        "cuda" if torch.cuda.is_available() else "cpu"
    )

    print(f"\nDevice: {device}")

    if device.type == "cuda":
        print(
            f"GPU: {torch.cuda.get_device_name(0)}"
        )

    model = ExerciseLSTM(
        input_size=10,
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3
    ).to(device)

    criterion = nn.CrossEntropyLoss()

    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=LEARNING_RATE
    )

    best_test_accuracy = 0.0
    best_epoch = 0

    MODEL_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    model_path = (
        MODEL_DIR /
        "assisted_shoulder_lstm.pth"
    )

    print("\nStarting training...\n")

    for epoch in range(EPOCHS):

        # -------------------------
        # Training
        # -------------------------

        model.train()

        total_loss = 0
        train_correct = 0
        train_total = 0

        for x, y in train_loader:

            x = x.to(device)
            y = y.to(device)

            optimizer.zero_grad()

            outputs = model(x)

            loss = criterion(
                outputs,
                y
            )

            loss.backward()

            optimizer.step()

            total_loss += loss.item()

            predictions = torch.argmax(
                outputs,
                dim=1
            )

            train_correct += (
                predictions == y
            ).sum().item()

            train_total += y.size(0)

        train_accuracy = (
            100 * train_correct / train_total
        )

        # -------------------------
        # Testing
        # -------------------------

        model.eval()

        test_correct = 0
        test_total = 0

        with torch.no_grad():

            for x, y in test_loader:

                x = x.to(device)
                y = y.to(device)

                outputs = model(x)

                predictions = torch.argmax(
                    outputs,
                    dim=1
                )

                test_correct += (
                    predictions == y
                ).sum().item()

                test_total += y.size(0)

        test_accuracy = (
            100 * test_correct / test_total
        )

        average_loss = (
            total_loss / len(train_loader)
        )

        # -------------------------
        # Save best model
        # -------------------------

        if test_accuracy > best_test_accuracy:

            best_test_accuracy = test_accuracy
            best_epoch = epoch + 1

            torch.save(
                model.state_dict(),
                model_path
            )

            marker = "  <-- BEST"

        else:
            marker = ""

        print(
            f"Epoch [{epoch + 1:02d}/{EPOCHS}] "
            f"Loss: {average_loss:.4f} "
            f"Train Acc: {train_accuracy:.2f}% "
            f"Test Acc: {test_accuracy:.2f}%"
            f"{marker}"
        )

    print("\n" + "=" * 60)
    print("TRAINING COMPLETE")
    print("=" * 60)

    print(
        f"Best test accuracy: "
        f"{best_test_accuracy:.2f}%"
    )

    print(
        f"Best epoch: {best_epoch}"
    )

    print(
        f"\nBest model saved to:\n"
        f"{model_path}"
    )


if __name__ == "__main__":
    main()
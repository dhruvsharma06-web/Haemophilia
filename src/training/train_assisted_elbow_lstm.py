"""Training pipeline for Assisted Elbow Flexion LSTM.

Strict Methodological Rules:
1. Training and internal validation use ONLY Persons 1 and 2.
2. Checkpoint selection is based strictly on internal validation within Persons 1 and 2.
3. Person 3 is NEVER loaded during training, threshold calibration, or checkpoint selection.
4. Saves weights to models/assisted_elbow_lstm.pth and full configuration to models/assisted_elbow_config.json.
5. Performs an automated zero-leakage audit.
"""

import json
import random
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.metrics import classification_report, confusion_matrix, f1_score, precision_score, recall_score
from torch.utils.data import DataLoader, Dataset

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.append(str(BASE_DIR))

from src.features.assisted_elbow_features import FEATURE_NAMES, NORM_CONSTANTS
from src.feedback.assisted_elbow_rep_counter import AssistedElbowRepCounter
from src.models.lstm_model import ExerciseLSTM

DATA_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion"
SEQUENCE_DIR = DATA_DIR / "sequences"
MANIFEST_FILE = DATA_DIR / "dataset_manifest.csv"
DEFAULT_CLEAN_DATA = BASE_DIR / "data" / "clean_elbow_train.csv"
MODEL_DIR = BASE_DIR / "models"
MODEL_PATH = MODEL_DIR / "assisted_elbow_lstm_human_verified.pth"
CONFIG_PATH = MODEL_DIR / "assisted_elbow_config_human_verified.json"

RANDOM_SEED = 42
BATCH_SIZE = 8
EPOCHS = 50
LEARNING_RATE = 0.001
SEQUENCE_LENGTH = 128
INPUT_SIZE = len(FEATURE_NAMES)


def set_seed(seed: int = RANDOM_SEED):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


class ElbowSequenceDataset(Dataset):
    def __init__(self, df: pd.DataFrame, sequence_dir: Path):
        self.records = df.to_dict("records")
        self.sequence_dir = sequence_dir

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx: int):
        rec = self.records[idx]
        file_path = self.sequence_dir / rec["sequence_file"]
        x = np.load(file_path).astype(np.float32)
        y = int(rec["numeric_label"])
        return torch.tensor(x, dtype=torch.float32), torch.tensor(y, dtype=torch.long)


def verify_leakage_audit(train_df: pd.DataFrame, val_df: pd.DataFrame) -> bool:
    """Verify that no data from Person 3 exists in train or internal validation."""
    p3_in_train = (train_df["subject_id"] == "person3").sum()
    p3_in_val = (val_df["subject_id"] == "person3").sum()

    print("\n" + "=" * 60)
    print("DATA LEAKAGE AUDIT (TRAINING & VALIDATION)")
    print("=" * 60)
    print(f"Person 3 sequences in training set   : {p3_in_train}")
    print(f"Person 3 sequences in validation set : {p3_in_val}")

    if p3_in_train > 0 or p3_in_val > 0:
        raise ValueError(
            "CRITICAL ERROR: Data leakage detected! Person 3 sequences found in training/val splits!"
        )

    # Verify no video overlap between train and internal val
    train_videos = set(train_df["video_id"])
    val_videos = set(val_df["video_id"])
    video_overlap = train_videos.intersection(val_videos)
    print(f"Video overlap between train and internal val : {len(video_overlap)}")
    if video_overlap:
        raise ValueError(f"CRITICAL ERROR: Video leakage between train and val: {video_overlap}")

    print("Audit passed: 100% isolated training and validation splits. Zero Person 3 leakage.\n")
    return True


def train_model(
    data_path: Path = DEFAULT_CLEAN_DATA,
    sequence_dir: Path = SEQUENCE_DIR,
    model_save_path: Path = MODEL_PATH,
    config_save_path: Path = CONFIG_PATH,
    epochs: int = EPOCHS,
    batch_size: int = BATCH_SIZE,
    learning_rate: float = LEARNING_RATE,
) -> Dict:
    set_seed(RANDOM_SEED)

    if not data_path.exists():
        raise FileNotFoundError(f"Clean dataset not found: {data_path}. Export clean dataset first.")

    df = pd.read_csv(data_path)

    # Strictly verify ground_truth_label presence
    if "ground_truth_label" not in df.columns:
        raise RuntimeError(
            "CRITICAL ERROR: 'ground_truth_label' column is missing from dataset! "
            "Falling back to folder_label or auto_label is strictly forbidden."
        )

    gt_clean = df["ground_truth_label"].fillna("").astype(str).str.strip().str.lower()
    valid_mask = gt_clean.isin(["correct", "incorrect"])
    valid_df = df[valid_mask].copy()

    if len(valid_df) == 0:
        raise RuntimeError(
            "CRITICAL ERROR: 0 human-verified annotations found in 'ground_truth_label'! "
            "Falling back to folder_label or auto_label is strictly forbidden."
        )

    print("\n" + "=" * 60)
    print("AUTHORITATIVE HUMAN GROUND TRUTH TRAINING ACTIVE")
    print("=" * 60)
    print(f"Target Column                        : ground_truth_label")
    print(f"Total verified sequences loaded      : {len(valid_df)}")
    print(f"  Verified Correct                   : {(gt_clean == 'correct').sum()}")
    print(f"  Verified Incorrect                 : {(gt_clean == 'incorrect').sum()}")
    print(f"Excluded Ambiguous / Unverified      : {len(df) - len(valid_df)}")

    valid_df["label"] = valid_df["ground_truth_label"].str.lower()
    valid_df["numeric_label"] = (valid_df["label"] == "incorrect").astype(int)

    if "video_id" not in valid_df.columns:
        valid_df["video_id"] = valid_df["video_name"].apply(lambda v: Path(v).stem)

    # Filter out Person 3 completely: Training & internal validation from Persons 1 & 2 ONLY
    p1_p2_df = valid_df[valid_df["subject_id"].isin(["person1", "person2"])].copy()

    # Video-level internal validation split within Persons 1 & 2
    # Hold out 2 videos (1 predominantly correct, 1 predominantly incorrect)
    # Using consistent internal validation videos: '20260825_135545' and '20260825_135701'
    val_video_ids = {"20260825_135545", "20260825_135701"}
    train_df = p1_p2_df[~p1_p2_df["video_id"].isin(val_video_ids)].reset_index(drop=True)
    val_df = p1_p2_df[p1_p2_df["video_id"].isin(val_video_ids)].reset_index(drop=True)

    # Run Leakage Audit
    verify_leakage_audit(train_df, val_df)

    print("=" * 60)
    print("ASSISTED ELBOW LSTM TRAINING")
    print(f"Target Source                        : ground_truth_label")
    print("=" * 60)
    print(f"Total available Persons 1+2 sequences: {len(p1_p2_df)}")
    print(f"Internal Training sequences          : {len(train_df)} (Correct: {(train_df['label'] == 'correct').sum()}, Incorrect: {(train_df['label'] == 'incorrect').sum()})")
    print(f"Internal Validation sequences        : {len(val_df)} (Correct: {(val_df['label'] == 'correct').sum()}, Incorrect: {(val_df['label'] == 'incorrect').sum()})")
    print(f"Internal Val Videos                  : {list(val_video_ids)}")

    train_dataset = ElbowSequenceDataset(train_df, sequence_dir)
    val_dataset = ElbowSequenceDataset(val_df, sequence_dir)

    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size, shuffle=False)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Training Device: {device}")

    model = ExerciseLSTM(
        input_size=INPUT_SIZE,
        hidden_size=64,
        num_layers=2,
        num_classes=2,
        dropout=0.3,
    ).to(device)

    # Class-weighted loss to handle imbalance naturally
    labels = train_df["numeric_label"].values
    class_counts = np.bincount(labels)
    class_weights = torch.tensor(
        [len(labels) / (2.0 * count) for count in class_counts],
        dtype=torch.float32,
    ).to(device)

    criterion = nn.CrossEntropyLoss(weight=class_weights)
    optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate, weight_decay=1e-4)

    best_val_f1 = -1.0
    best_val_loss = float("inf")
    best_epoch = 0
    best_val_acc = 0.0

    model_save_path.parent.mkdir(parents=True, exist_ok=True)

    history = []

    print("\nStarting training...\n")

    for epoch in range(epochs):
        model.train()
        train_loss = 0.0
        train_correct = 0
        train_total = 0
        train_preds_list = []
        train_targets_list = []

        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            optimizer.zero_grad()
            out = model(x)
            loss = criterion(out, y)
            loss.backward()
            optimizer.step()

            train_loss += loss.item() * y.size(0)
            preds = torch.argmax(out, dim=1)
            train_correct += (preds == y).sum().item()
            train_total += y.size(0)
            train_preds_list.extend(preds.cpu().numpy())
            train_targets_list.extend(y.cpu().numpy())

        epoch_train_loss = train_loss / train_total
        epoch_train_acc = (train_correct / train_total) * 100.0
        epoch_train_f1 = f1_score(train_targets_list, train_preds_list, average="macro", zero_division=0) * 100.0

        # Internal validation
        model.eval()
        val_loss = 0.0
        val_correct = 0
        val_total = 0
        val_preds_list = []
        val_targets_list = []

        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                out = model(x)
                loss = criterion(out, y)
                val_loss += loss.item() * y.size(0)
                preds = torch.argmax(out, dim=1)
                val_correct += (preds == y).sum().item()
                val_total += y.size(0)
                val_preds_list.extend(preds.cpu().numpy())
                val_targets_list.extend(y.cpu().numpy())

        epoch_val_loss = val_loss / val_total
        epoch_val_acc = (val_correct / val_total) * 100.0
        val_f1 = f1_score(val_targets_list, val_preds_list, average="macro", zero_division=0) * 100.0

        marker = ""
        # Checkpoint selection strictly on internal validation macro F1 / accuracy (after warm-up)
        if epoch >= 4 and (val_f1 > best_val_f1 or (val_f1 == best_val_f1 and epoch_val_loss < best_val_loss)):
            best_val_f1 = val_f1
            best_val_loss = epoch_val_loss
            best_val_acc = epoch_val_acc
            best_epoch = epoch + 1
            best_train_loss = epoch_train_loss
            best_train_acc = epoch_train_acc
            best_train_f1 = epoch_train_f1
            torch.save(model.state_dict(), model_save_path)
            marker = f" <-- BEST VAL F1: {val_f1:.1f}% (SAVED)"

        if (epoch + 1) % 5 == 0 or marker:
            print(
                f"Epoch [{epoch + 1:02d}/{epochs}] "
                f"Train Loss: {epoch_train_loss:.4f} "
                f"Train Acc: {epoch_train_acc:5.1f}% "
                f"Train F1: {epoch_train_f1:5.1f}% | "
                f"Val Loss: {epoch_val_loss:.4f} "
                f"Val Acc: {epoch_val_acc:5.1f}% "
                f"Val F1: {val_f1:5.1f}%"
                f"{marker}"
            )

        history.append({
            "epoch": epoch + 1,
            "train_loss": epoch_train_loss,
            "train_acc": epoch_train_acc,
            "train_f1": epoch_train_f1,
            "val_loss": epoch_val_loss,
            "val_acc": epoch_val_acc,
            "val_f1": val_f1,
        })

    # Save complete configuration artifact
    rep_counter_cfg = AssistedElbowRepCounter().get_config()
    config_record = {
        "exercise": "Assisted Elbow Flexion",
        "model_architecture": {
            "model_type": "ExerciseLSTM",
            "input_size": INPUT_SIZE,
            "hidden_size": 64,
            "num_layers": 2,
            "num_classes": 2,
            "dropout": 0.3,
            "sequence_length": SEQUENCE_LENGTH,
        },
        "feature_specification": {
            "feature_names": FEATURE_NAMES,
            "num_features": len(FEATURE_NAMES),
            "canonical_semantics": (
                "Feature 0 is active arm angle, Feature 1 is assisting arm angle; "
                "Feature 8 is active elbow flare, Feature 9 is assisting elbow flare; "
                "ensures arm-invariance across left/right/both exercises."
            ),
        },
        "normalization_constants": NORM_CONSTANTS,
        "repetition_detection_thresholds": rep_counter_cfg,
        "training_metadata": {
            "random_seed": RANDOM_SEED,
            "epochs": epochs,
            "batch_size": batch_size,
            "learning_rate": learning_rate,
            "train_subjects": ["person1", "person2"],
            "internal_val_videos": list(val_video_ids),
            "held_out_final_test_subject": "person3",
            "best_epoch": best_epoch,
            "best_val_loss": best_val_loss,
            "best_val_acc": best_val_acc,
            "best_val_f1": best_val_f1,
            "best_train_loss": best_train_loss if "best_train_loss" in locals() else None,
            "best_train_acc": best_train_acc if "best_train_acc" in locals() else None,
            "best_train_f1": best_train_f1 if "best_train_f1" in locals() else None,
            "train_counts": {"total": len(train_df), "correct": int((train_df['label'] == 'correct').sum()), "incorrect": int((train_df['label'] == 'incorrect').sum())},
            "val_counts": {"total": len(val_df), "correct": int((val_df['label'] == 'correct').sum()), "incorrect": int((val_df['label'] == 'incorrect').sum())},
        },
    }

    with open(config_save_path, "w", encoding="utf-8") as f:
        json.dump(config_record, f, indent=2)

    print("\n" + "=" * 60)
    print("TRAINING FINISHED")
    print("=" * 60)
    print(f"Best internal validation epoch : {best_epoch}")
    print(f"Best internal validation loss  : {best_val_loss:.4f}")
    print(f"Best internal validation acc   : {best_val_acc:.1f}%")
    print(f"Best internal validation F1    : {best_val_f1:.1f}%")
    print(f"Model checkpoint saved to      : {model_save_path}")
    print(f"Configuration record saved to  : {config_save_path}")

    return {
        "best_epoch": best_epoch,
        "best_val_loss": best_val_loss,
        "best_val_acc": best_val_acc,
        "best_val_f1": best_val_f1,
        "train_samples": len(train_df),
        "val_samples": len(val_df),
        "history": history,
    }


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Train Assisted Elbow LSTM Model with Human-Verified Target")
    parser.add_argument("--data", type=Path, default=DEFAULT_CLEAN_DATA, help="Path to clean supervised CSV")
    parser.add_argument("--model-save-path", type=Path, default=MODEL_PATH, help="Destination for model weights")
    parser.add_argument("--config-save-path", type=Path, default=CONFIG_PATH, help="Destination for config JSON")
    parser.add_argument("--epochs", type=int, default=EPOCHS, help="Number of training epochs")
    parser.add_argument("--batch_size", type=int, default=BATCH_SIZE, help="Batch size")
    parser.add_argument("--lr", type=float, default=LEARNING_RATE, help="Learning rate")
    args = parser.parse_args()

    train_model(
        data_path=args.data,
        model_save_path=args.model_save_path,
        config_save_path=args.config_save_path,
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.lr,
    )

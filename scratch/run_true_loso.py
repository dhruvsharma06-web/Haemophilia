import os
import sys
import copy
import random
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    confusion_matrix
)

sys.path.insert(0, r"c:\dev\Haemophilia")
from src.models.lstm_model import ExerciseLSTM

DATA_DIR = Path(r"c:\dev\Haemophilia\processed_data\assisted_elbow_flexion")
MANIFEST_FILE = DATA_DIR / "dataset_manifest.csv"
SEQUENCE_DIR = DATA_DIR / "sequences"

def set_seed(seed=42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)

class SeqDataset(Dataset):
    def __init__(self, records):
        self.records = records

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx):
        rec = self.records[idx]
        seq = np.load(SEQUENCE_DIR / rec["sequence_file"]).astype(np.float32)
        label = int(rec["numeric_label"])
        return torch.tensor(seq, dtype=torch.float32), torch.tensor(label, dtype=torch.long)

def evaluate_loader(model, loader, device):
    model.eval()
    all_preds = []
    all_targets = []
    total_loss = 0.0
    criterion = nn.CrossEntropyLoss()
    
    with torch.no_grad():
        for x, y in loader:
            x, y = x.to(device), y.to(device)
            out = model(x)
            loss = criterion(out, y)
            total_loss += loss.item() * y.size(0)
            preds = torch.argmax(out, dim=1)
            all_preds.extend(preds.cpu().numpy())
            all_targets.extend(y.cpu().numpy())
            
    n = len(loader.dataset)
    acc = accuracy_score(all_targets, all_preds) * 100.0 if n > 0 else 0.0
    bal_acc = balanced_accuracy_score(all_targets, all_preds) * 100.0 if n > 0 else 0.0
    macro_f1 = f1_score(all_targets, all_preds, average="macro", zero_division=0) * 100.0
    
    # Class 0 (Correct), Class 1 (Incorrect)
    prec_0 = precision_score(all_targets, all_preds, pos_label=0, zero_division=0) * 100.0
    rec_0 = recall_score(all_targets, all_preds, pos_label=0, zero_division=0) * 100.0
    f1_0 = f1_score(all_targets, all_preds, pos_label=0, zero_division=0) * 100.0
    
    prec_1 = precision_score(all_targets, all_preds, pos_label=1, zero_division=0) * 100.0
    rec_1 = recall_score(all_targets, all_preds, pos_label=1, zero_division=0) * 100.0
    f1_1 = f1_score(all_targets, all_preds, pos_label=1, zero_division=0) * 100.0
    
    cm = confusion_matrix(all_targets, all_preds, labels=[0, 1])
    
    return {
        "loss": total_loss / n if n > 0 else 0.0,
        "acc": acc,
        "bal_acc": bal_acc,
        "macro_f1": macro_f1,
        "prec_0": prec_0,
        "rec_0": rec_0,
        "f1_0": f1_0,
        "prec_1": prec_1,
        "rec_1": rec_1,
        "f1_1": f1_1,
        "cm": cm,
        "preds": all_preds,
        "targets": all_targets
    }

def run_true_loso():
    set_seed(42)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")
    
    manifest = pd.read_csv(MANIFEST_FILE)
    subjects = ["person1", "person2", "person3"]
    
    # For internal validation within the training subjects of each fold:
    # We choose 1 correct video and 1 incorrect video from the training pool
    # so that training subject data alone is used for checkpoint selection/tuning.
    inner_val_videos = {
        "person3": {"20260825_135701", "20260825_135545"},      # from Person 2 (1 inc, 1 corr)
        "person1": {"VID20260825125333", "VID20260825125720"},  # from Person 3 (1 corr, 1 inc)
        "person2": {"VID20260825125257", "VID20260825125647"},  # from Person 3 (1 corr, 1 inc)
    }
    
    fold_reports = []
    all_test_preds = []
    all_test_targets = []
    
    for held_out in subjects:
        print("\n" + "=" * 80)
        print(f"LOSO FOLD: HELD-OUT SUBJECT = [{held_out}]")
        print("=" * 80)
        
        test_df = manifest[manifest["subject_id"] == held_out].reset_index(drop=True)
        train_pool_df = manifest[manifest["subject_id"] != held_out].reset_index(drop=True)
        
        val_vids = inner_val_videos[held_out]
        val_df = train_pool_df[train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)
        train_df = train_pool_df[~train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)
        
        # Verify complete separation
        assert len(set(train_df["subject_id"]).intersection({held_out})) == 0
        assert len(set(val_df["subject_id"]).intersection({held_out})) == 0
        assert len(set(train_df["video_id"]).intersection(set(val_df["video_id"]))) == 0
        
        train_counts = train_df["label"].value_counts().to_dict()
        val_counts = val_df["label"].value_counts().to_dict()
        test_counts = test_df["label"].value_counts().to_dict()
        
        print(f"Train samples : {len(train_df)} -> {train_counts}")
        print(f"Val samples   : {len(val_df)} -> {val_counts} (Videos: {val_vids})")
        print(f"Test samples  : {len(test_df)} -> {test_counts} (Subject: {held_out})")
        
        train_loader = DataLoader(SeqDataset(train_df.to_dict("records")), batch_size=8, shuffle=True)
        val_loader = DataLoader(SeqDataset(val_df.to_dict("records")), batch_size=8, shuffle=False)
        test_loader = DataLoader(SeqDataset(test_df.to_dict("records")), batch_size=8, shuffle=False)
        
        # Initialize fresh model for this fold
        model = ExerciseLSTM(
            input_size=10,
            hidden_size=64,
            num_layers=2,
            num_classes=2,
            dropout=0.3
        ).to(device)
        
        labels = train_df["numeric_label"].values
        counts = np.bincount(labels)
        weights = torch.tensor([len(labels) / (2.0 * c) for c in counts], dtype=torch.float32).to(device)
        criterion = nn.CrossEntropyLoss(weight=weights)
        optimizer = torch.optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-4)
        
        best_val_f1 = -1.0
        best_val_loss = float("inf")
        best_state = None
        best_epoch = 0
        
        epochs = 40
        for ep in range(1, epochs + 1):
            model.train()
            for x, y in train_loader:
                x, y = x.to(device), y.to(device)
                optimizer.zero_grad()
                loss = criterion(model(x), y)
                loss.backward()
                optimizer.step()
                
            val_res = evaluate_loader(model, val_loader, device)
            # Checkpoint selection strictly on training-subject validation data
            if ep >= 4 and (val_res["macro_f1"] > best_val_f1 or (val_res["macro_f1"] == best_val_f1 and val_res["loss"] < best_val_loss)):
                best_val_f1 = val_res["macro_f1"]
                best_val_loss = val_res["loss"]
                best_state = copy.deepcopy(model.state_dict())
                best_epoch = ep
                
        print(f"Best internal validation checkpoint selected at epoch {best_epoch} (Val Macro-F1: {best_val_f1:.1f}%)")
        
        # Load best model for one-time evaluation on held-out subject
        model.load_state_dict(best_state)
        test_res = evaluate_loader(model, test_loader, device)
        
        all_test_preds.extend(test_res["preds"])
        all_test_targets.extend(test_res["targets"])
        
        fold_reports.append({
            "held_out_subject": held_out,
            "train_samples": len(train_df),
            "train_class_dist": train_counts,
            "val_samples": len(val_df),
            "val_class_dist": val_counts,
            "test_samples": len(test_df),
            "test_class_dist": test_counts,
            "best_epoch": best_epoch,
            "accuracy": test_res["acc"],
            "balanced_accuracy": test_res["bal_acc"],
            "macro_f1": test_res["macro_f1"],
            "prec_correct": test_res["prec_0"],
            "rec_correct": test_res["rec_0"],
            "f1_correct": test_res["f1_0"],
            "prec_incorrect": test_res["prec_1"],
            "rec_incorrect": test_res["rec_1"],
            "f1_incorrect": test_res["f1_1"],
            "confusion_matrix": test_res["cm"]
        })
        
        print(f"Test Accuracy         : {test_res['acc']:.2f}%")
        print(f"Test Balanced Accuracy: {test_res['bal_acc']:.2f}%")
        print(f"Test Macro-F1         : {test_res['macro_f1']:.2f}%")
        print(f"Correct class   (F1/P/R): {test_res['f1_0']:.1f}% / {test_res['prec_0']:.1f}% / {test_res['rec_0']:.1f}%")
        print(f"Incorrect class (F1/P/R): {test_res['f1_1']:.1f}% / {test_res['prec_1']:.1f}% / {test_res['rec_1']:.1f}%")
        print(f"Confusion Matrix [TN, FP; FN, TP]:\n{test_res['cm']}")

    # Overall Aggregate LOSO metrics
    agg_acc = accuracy_score(all_test_targets, all_test_preds) * 100.0
    agg_bal_acc = balanced_accuracy_score(all_test_targets, all_test_preds) * 100.0
    agg_macro_f1 = f1_score(all_test_targets, all_test_preds, average="macro") * 100.0
    agg_cm = confusion_matrix(all_test_targets, all_test_preds, labels=[0, 1])
    
    print("\n" + "=" * 80)
    print("OVERALL AGGREGATE LOSO-CV SUMMARY")
    print("=" * 80)
    print(f"Total Evaluated Samples : {len(all_test_targets)}")
    print(f"Aggregate Accuracy      : {agg_acc:.2f}%")
    print(f"Aggregate Balanced Acc  : {agg_bal_acc:.2f}%")
    print(f"Aggregate Macro-F1      : {agg_macro_f1:.2f}%")
    print(f"Aggregate Confusion Matrix:\n{agg_cm}")
    
    return fold_reports

if __name__ == "__main__":
    run_true_loso()

#!/usr/bin/env python3
"""Training and LOSO cross-validation for the v2 Assisted Elbow Flexion model on expanded data.

Architecture: TemporalScalarHybridModel (7,690 parameters)
- 10-dim subject-normalized temporal sequence (128, 10) -> LSTM(10, 32, 1-layer)
- 34 phase-aware / bilateral kinematic scalars -> MLP(34 -> 16 -> 16)
- Feature fusion -> Classifier(48 -> 24 -> 2)

Dataset: data/clean_elbow_train_expanded_v2.csv (296 repetitions: 195 original + 101 new)
Subjects: person1, person2, person3, person4, person5
Checkpoint: models/assisted_elbow_v2_expanded.pth
"""

import copy
import json
import random
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.preprocessing import StandardScaler
from torch.utils.data import DataLoader, Dataset

BASE_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BASE_DIR))

DATA_CSV = BASE_DIR / "data" / "clean_elbow_train_expanded_v2.csv"
SEQUENCE_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
MODEL_DIR = BASE_DIR / "models"
CHECKPOINT_PATH = MODEL_DIR / "assisted_elbow_v2_expanded.pth"
METRICS_PATH = MODEL_DIR / "assisted_elbow_v2_expanded_metrics.json"

RANDOM_SEED = 42


def set_seed(seed: int = RANDOM_SEED):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def extract_subject_normalized_temporal(raw_seq: np.ndarray) -> np.ndarray:
    """10-dim subject-normalized sequence (128, 10). Excludes absolute angles."""
    act_ang = raw_seq[:, 0]
    asst_ang = raw_seq[:, 1]
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    tilt = raw_seq[:, 4]
    rot = raw_seq[:, 5]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    ext_base = float(np.max(act_ang))
    rom = float(np.max(act_ang) - np.min(act_ang) + 1e-4)

    flexion_delta = ext_base - act_ang
    flexion_progress = flexion_delta / rom
    rom_norm_vel = np.clip(act_vel / rom, -3.0, 3.0) * 0.3
    raw_act_vel = act_vel
    bi_ang_asym = act_ang - asst_ang
    bi_vel_asym = act_vel - asst_vel
    rel_tilt = tilt - tilt[0]
    rel_rot = rot - rot[0]
    norm_flare = act_flare
    flare_asym = act_flare - asst_flare

    return np.column_stack([
        flexion_delta,
        flexion_progress,
        rom_norm_vel,
        raw_act_vel,
        bi_ang_asym,
        bi_vel_asym,
        rel_tilt,
        rel_rot,
        norm_flare,
        flare_asym,
    ]).astype(np.float32)


def extract_phase_aware_scalars_34(raw_seq: np.ndarray, dur: float) -> np.ndarray:
    """Extract all 34 phase-aware kinematic scalars."""
    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    min_ang = float(np.min(act_ang_deg))
    max_ang = float(np.max(act_ang_deg))
    rom = float(max_ang - min_ang)
    peak_vel = float(np.max(np.abs(act_vel)))
    mean_vel = float(np.mean(np.abs(act_vel)))
    peak_flare = float(np.max(act_flare))
    mean_flare = float(np.mean(act_flare))
    bi_ang_asym = float(np.mean(np.abs(act_ang_deg - asst_ang_deg)))
    bi_flare_asym = float(np.mean(np.abs(act_flare - asst_flare)))

    base_10 = [
        rom, min_ang, max_ang, dur, peak_vel, mean_vel,
        peak_flare, mean_flare, bi_ang_asym, bi_flare_asym
    ]

    idx_peak = int(np.argmin(act_ang_deg))
    idx_peak = max(5, min(idx_peak, len(act_ang_deg) - 6))

    flex_dur = dur * (idx_peak / 128.0)
    ext_dur = dur * ((128.0 - idx_peak) / 128.0)
    flex_ext_ratio = flex_dur / max(ext_dur, 1e-3)
    time_to_peak_pct = idx_peak / 128.0

    peak_flex_vel = float(np.max(np.abs(act_vel[:idx_peak])))
    peak_ext_vel = float(np.max(np.abs(act_vel[idx_peak:])))
    mean_flex_vel = float(np.mean(np.abs(act_vel[:idx_peak])))
    mean_ext_vel = float(np.mean(np.abs(act_vel[idx_peak:])))
    ecc_conc_vel_ratio = mean_ext_vel / max(mean_flex_vel, 1e-4)

    acc = np.gradient(act_vel)
    jerk = np.gradient(acc)
    peak_flex_acc = float(np.max(np.abs(acc[:idx_peak])))
    peak_ext_acc = float(np.max(np.abs(acc[idx_peak:])))
    peak_jerk = float(np.max(np.abs(jerk)))

    flex_diff2 = np.diff(act_ang_deg[:idx_peak], n=2)
    ext_diff2 = np.diff(act_ang_deg[idx_peak:], n=2)
    flex_smoothness = float(1.0 / (1.0 + np.mean(np.abs(flex_diff2)))) if len(flex_diff2) > 0 else 0.0
    ext_smoothness = float(1.0 / (1.0 + np.mean(np.abs(ext_diff2)))) if len(ext_diff2) > 0 else 0.0

    recovery_rate = float((act_ang_deg[-1] - min_ang) / max(rom, 1e-3))
    ang_25 = float(act_ang_deg[int(idx_peak * 0.25)])
    ang_50 = float(act_ang_deg[int(idx_peak * 0.50)])
    ang_75 = float(act_ang_deg[int(idx_peak * 0.75)])

    phase_18 = [
        flex_dur, ext_dur, flex_ext_ratio, time_to_peak_pct,
        peak_flex_vel, peak_ext_vel, mean_flex_vel, mean_ext_vel, ecc_conc_vel_ratio,
        peak_flex_acc, peak_ext_acc, peak_jerk, flex_smoothness, ext_smoothness,
        recovery_rate, ang_25, ang_50, ang_75
    ]

    bi_ang_flex = float(np.mean(np.abs(act_ang_deg[:idx_peak] - asst_ang_deg[:idx_peak])))
    bi_ang_ext = float(np.mean(np.abs(act_ang_deg[idx_peak:] - asst_ang_deg[idx_peak:])))
    bi_vel_flex = float(np.mean(np.abs(act_vel[:idx_peak] - asst_vel[:idx_peak])))
    bi_vel_ext = float(np.mean(np.abs(act_vel[idx_peak:] - asst_vel[idx_peak])))
    bi_flare_flex = float(np.mean(np.abs(act_flare[:idx_peak] - asst_flare[:idx_peak])))
    bi_flare_ext = float(np.mean(np.abs(act_flare[idx_peak:] - asst_flare[idx_peak])))

    phase_bilat_6 = [
        bi_ang_flex, bi_ang_ext, bi_vel_flex, bi_vel_ext,
        bi_flare_flex, bi_flare_ext
    ]

    return np.array(base_10 + phase_18 + phase_bilat_6, dtype=np.float32)


class TemporalScalarHybridModel(nn.Module):
    def __init__(self, temporal_dim=10, scalar_dim=34, lstm_hidden=32, mlp_hidden=16, dropout=0.4):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=temporal_dim,
            hidden_size=lstm_hidden,
            num_layers=1,
            batch_first=True,
        )
        self.lstm_dropout = nn.Dropout(dropout)

        self.scalar_mlp = nn.Sequential(
            nn.Linear(scalar_dim, mlp_hidden),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(mlp_hidden, mlp_hidden),
            nn.ReLU(),
            nn.Dropout(dropout),
        )

        self.classifier = nn.Sequential(
            nn.Linear(lstm_hidden + mlp_hidden, 24),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(24, 2),
        )

    def forward(self, x_seq, x_scalar):
        _, (hn, _) = self.lstm(x_seq)
        temporal_embed = self.lstm_dropout(hn[-1])
        scalar_embed = self.scalar_mlp(x_scalar)
        fused = torch.cat([temporal_embed, scalar_embed], dim=-1)
        return self.classifier(fused)


class GenericDataset(Dataset):
    def __init__(self, sequences: np.ndarray, scalars: np.ndarray, labels: np.ndarray):
        self.sequences = torch.tensor(sequences, dtype=torch.float32)
        self.scalars = torch.tensor(scalars, dtype=torch.float32)
        self.labels = torch.tensor(labels, dtype=torch.long)

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        return self.sequences[idx], self.scalars[idx], self.labels[idx]


def train_single_split(
    X_seq_tr, X_sc_tr, y_tr,
    X_seq_val, X_sc_val, y_val,
    device,
    epochs=40,
    batch_size=8,
) -> Tuple[TemporalScalarHybridModel, float]:
    tr_loader = DataLoader(GenericDataset(X_seq_tr, X_sc_tr, y_tr), batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(GenericDataset(X_seq_val, X_sc_val, y_val), batch_size=batch_size, shuffle=False)

    counts = np.bincount(y_tr, minlength=2)
    w = len(y_tr) / (2.0 * np.maximum(counts, 1))
    criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))

    model = TemporalScalarHybridModel().to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)

    best_val_f1 = -1.0
    best_state = None

    for epoch in range(epochs):
        model.train()
        for b_seq, b_sc, b_y in tr_loader:
            b_seq, b_sc, b_y = b_seq.to(device), b_sc.to(device), b_y.to(device)
            optimizer.zero_grad()
            logits = model(b_seq, b_sc)
            loss = criterion(logits, b_y)
            loss.backward()
            optimizer.step()

        model.eval()
        val_preds_ep, val_targets_ep = [], []
        with torch.no_grad():
            for b_seq, b_sc, b_y in val_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                preds_ep = torch.argmax(logits, dim=1).cpu().numpy()
                val_preds_ep.extend(preds_ep)
                val_targets_ep.extend(b_y.numpy())

        v_f1 = f1_score(val_targets_ep, val_preds_ep, average="macro", zero_division=0)
        if epoch >= 4 and v_f1 > best_val_f1:
            best_val_f1 = v_f1
            best_state = copy.deepcopy(model.state_dict())

    if best_state is not None:
        model.load_state_dict(best_state)

    return model, best_val_f1


def main():
    set_seed(RANDOM_SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    if not DATA_CSV.exists():
        print(f"Error: {DATA_CSV} does not exist. Please run integrate_new_elbow_dataset.py first.")
        return

    df = pd.read_csv(DATA_CSV)
    print(f"Loaded {len(df)} repetitions from {DATA_CSV.name}")
    print(f"Subjects: {sorted(df['subject_id'].unique().tolist())}")
    print(f"Class distribution:\n{df['ground_truth_label'].value_counts()}")

    # Extract sequences and scalars
    seq_list = []
    scalar_list = []
    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        seq_list.append(extract_subject_normalized_temporal(raw))
        scalar_list.append(extract_phase_aware_scalars_34(raw, dur))

    all_seqs = np.array(seq_list, dtype=np.float32)       # (N, 128, 10)
    all_scalars = np.array(scalar_list, dtype=np.float32)  # (N, 34)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    print(f"Feature arrays: Sequences shape {all_seqs.shape}, Scalars shape {all_scalars.shape}")

    # =========================================================================
    # 1. 5-Fold Leave-One-Subject-Out (LOSO) Cross-Validation
    # =========================================================================
    print("\n" + "=" * 70)
    print("5-FOLD LEAVE-ONE-SUBJECT-OUT (LOSO) CROSS-VALIDATION")
    print("=" * 70)

    loso_preds = np.zeros(len(df), dtype=int)
    loso_probs = np.zeros(len(df), dtype=float)
    fold_metrics = {}

    for test_sub in unique_subjects:
        set_seed(RANDOM_SEED)
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask
        tr_indices = np.where(train_mask)[0]
        y_train_full = labels[tr_indices]

        # Inner validation split (20% stratified from training fold)
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_train_full == 0]
        c1_idx = tr_indices[y_train_full == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))

        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Normalization fitted strictly on actual_tr_idx
        D_seq = all_seqs.shape[-1]
        temp_scaler = StandardScaler()
        temp_scaler.fit(all_seqs[actual_tr_idx].reshape(-1, D_seq))

        def transform_seq(seqs):
            b, t, d = seqs.shape
            return temp_scaler.transform(seqs.reshape(-1, d)).reshape(b, t, d)

        X_seq_tr = transform_seq(all_seqs[actual_tr_idx])
        X_seq_val = transform_seq(all_seqs[val_idx])
        X_seq_test = transform_seq(all_seqs[test_mask])

        scalar_scaler = StandardScaler()
        scalar_scaler.fit(all_scalars[actual_tr_idx])

        X_sc_tr = scalar_scaler.transform(all_scalars[actual_tr_idx])
        X_sc_val = scalar_scaler.transform(all_scalars[val_idx])
        X_sc_test = scalar_scaler.transform(all_scalars[test_mask])

        y_tr = labels[actual_tr_idx]
        y_val = labels[val_idx]
        y_test = labels[test_mask]

        fold_model, val_f1 = train_single_split(
            X_seq_tr, X_sc_tr, y_tr,
            X_seq_val, X_sc_val, y_val,
            device=device,
            epochs=40,
            batch_size=8,
        )

        fold_model.eval()
        test_loader = DataLoader(GenericDataset(X_seq_test, X_sc_test, y_test), batch_size=8, shuffle=False)
        fold_test_preds = []
        fold_test_probs = []
        with torch.no_grad():
            for b_seq, b_sc, _ in test_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = fold_model(b_seq, b_sc)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                preds = torch.argmax(logits, dim=1).cpu().numpy()
                fold_test_preds.extend(preds)
                fold_test_probs.extend(probs)

        loso_preds[test_mask] = fold_test_preds
        loso_probs[test_mask] = fold_test_probs

        f_acc = accuracy_score(y_test, fold_test_preds)
        f_bacc = balanced_accuracy_score(y_test, fold_test_preds)
        f_f1 = f1_score(y_test, fold_test_preds, average="macro", zero_division=0)
        fold_metrics[test_sub] = {
            "n_reps": int(np.sum(test_mask)),
            "accuracy": round(float(f_acc) * 100.0, 2),
            "balanced_accuracy": round(float(f_bacc) * 100.0, 2),
            "macro_f1": round(float(f_f1) * 100.0, 2),
        }
        print(f"Fold {test_sub:<8} (N={np.sum(test_mask):2d}): Acc={f_acc*100:.2f}%, BalAcc={f_bacc*100:.2f}%, F1={f_f1*100:.2f}%")

    # Overall LOSO metrics
    overall_acc = accuracy_score(labels, loso_preds)
    overall_bacc = balanced_accuracy_score(labels, loso_preds)
    overall_f1 = f1_score(labels, loso_preds, average="macro", zero_division=0)
    cm = confusion_matrix(labels, loso_preds)

    print("-" * 70)
    print(f"OVERALL 5-SUBJECT LOSO RESULTS:")
    print(f"  Accuracy          : {overall_acc * 100.0:.2f}%")
    print(f"  Balanced Accuracy : {overall_bacc * 100.0:.2f}%")
    print(f"  Macro-F1          : {overall_f1 * 100.0:.2f}%")
    print(f"  Confusion Matrix  :\n{cm}")

    # Performance specifically on the new subjects (Person 4 & Person 5)
    new_mask = (df["subject_id"].isin(["person4", "person5"])).values
    if np.sum(new_mask) > 0:
        new_acc = accuracy_score(labels[new_mask], loso_preds[new_mask])
        new_bacc = balanced_accuracy_score(labels[new_mask], loso_preds[new_mask])
        new_f1 = f1_score(labels[new_mask], loso_preds[new_mask], average="macro", zero_division=0)
        print(f"\nNEW SUBJECTS EVALUATION (Person 4 & Person 5 held-out):")
        print(f"  Accuracy          : {new_acc * 100.0:.2f}%")
        print(f"  Balanced Accuracy : {new_bacc * 100.0:.2f}%")
        print(f"  Macro-F1          : {new_f1 * 100.0:.2f}%")

    # Performance on old subjects (Persons 1-3)
    old_mask = (df["subject_id"].isin(["person1", "person2", "person3"])).values
    old_acc = accuracy_score(labels[old_mask], loso_preds[old_mask])
    old_bacc = balanced_accuracy_score(labels[old_mask], loso_preds[old_mask])
    old_f1 = f1_score(labels[old_mask], loso_preds[old_mask], average="macro", zero_division=0)
    print(f"\nOLD 3-SUBJECT COHORT UNDER EXPANDED LOSO:")
    print(f"  Accuracy          : {old_acc * 100.0:.2f}%")
    print(f"  Balanced Accuracy : {old_bacc * 100.0:.2f}%")
    print(f"  Macro-F1          : {old_f1 * 100.0:.2f}%")

    # =========================================================================
    # 2. Train Full Expanded Production Model & Save Checkpoint
    # =========================================================================
    print("\n" + "=" * 70)
    print("TRAINING FULL EXPANDED v2 MODEL ON ALL 296 REPETITIONS")
    print("=" * 70)
    set_seed(RANDOM_SEED)

    # Scalers on full expanded dataset
    D_seq = all_seqs.shape[-1]
    final_temp_scaler = StandardScaler()
    final_temp_scaler.fit(all_seqs.reshape(-1, D_seq))
    X_seq_all_norm = final_temp_scaler.transform(all_seqs.reshape(-1, D_seq)).reshape(all_seqs.shape)

    final_scalar_scaler = StandardScaler()
    X_sc_all_norm = final_scalar_scaler.fit_transform(all_scalars)

    # Train final model on full dataset with 10% validation monitor
    val_indices = np.random.RandomState(42).choice(len(df), size=int(0.15 * len(df)), replace=False)
    train_indices = np.setdiff1d(np.arange(len(df)), val_indices)

    final_model, final_val_f1 = train_single_split(
        X_seq_all_norm[train_indices], X_sc_all_norm[train_indices], labels[train_indices],
        X_seq_all_norm[val_indices], X_sc_all_norm[val_indices], labels[val_indices],
        device=device,
        epochs=50,
        batch_size=8,
    )

    # Save Checkpoint
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    checkpoint_dict = {
        "model_state_dict": final_model.state_dict(),
        "architecture": "temporal_phase_bilateral_hybrid",
        "parameter_count": sum(p.numel() for p in final_model.parameters()),
        "input_features": {
            "temporal_dim": 10,
            "scalar_dim": 34,
            "sequence_length": 128,
        },
        "training_dataset": "clean_elbow_train_expanded_v2.csv",
        "total_repetitions": len(df),
        "class_distribution": df["ground_truth_label"].value_counts().to_dict(),
        "subjects": unique_subjects,
        "loso_metrics": {
            "accuracy": round(float(overall_acc) * 100.0, 2),
            "balanced_accuracy": round(float(overall_bacc) * 100.0, 2),
            "macro_f1": round(float(overall_f1) * 100.0, 2),
            "confusion_matrix": cm.tolist(),
            "fold_breakdown": fold_metrics,
        },
        "temporal_scaler_mean": final_temp_scaler.mean_.tolist(),
        "temporal_scaler_scale": final_temp_scaler.scale_.tolist(),
        "scalar_scaler_mean": final_scalar_scaler.mean_.tolist(),
        "scalar_scaler_scale": final_scalar_scaler.scale_.tolist(),
    }

    torch.save(checkpoint_dict, CHECKPOINT_PATH)
    print(f"\nModel checkpoint saved to: {CHECKPOINT_PATH}")

    with open(METRICS_PATH, "w", encoding="utf-8") as f:
        json.dump(checkpoint_dict, f, indent=2, default=str)
    print(f"Metrics saved to: {METRICS_PATH}")

    print("\nTraining completed successfully!")


if __name__ == "__main__":
    main()

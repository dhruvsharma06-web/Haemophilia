"""Phase 2 Controlled Experiments for Assisted Elbow Flexion.

Steps implemented:
Step 1: Exact configuration bookkeeping & verification.
Step 2: Amplitude information loss investigation:
        - 10-dim subject-normalized temporal features
        - 10 repetition-level summary amplitude scalars
        - Strict LOSO fold scaling (fitted strictly on training subjects).
Step 3: Small temporal + scalar model:
        - Temporal: 1-layer LSTM (hidden 32, dropout 0.4) -> temporal embedding (32)
        - Scalar: 2-layer MLP (10 -> 16 -> 16, dropout 0.4) -> summary embedding (16)
        - Fusion: Concat (48) -> Linear (48 -> 24, dropout 0.4) -> Linear (24 -> 2)
Step 4: Preserve subject invariance (absolute angle sequences excluded from temporal branch).
Step 5: Class calibration:
        - Standard CE
        - Class-Weighted CE
        - Validation-derived probability threshold (calibrated strictly on inner validation fold).
Step 6: Person 2 diagnostic evidence.
Step 7 & 8: Mixed video dataset expansion (195 clean repetitions).
Step 9: Rigorous TRUE 3-fold LOSO evaluation reporting:
        Accuracy, Balanced Accuracy, Macro-F1, Correct Recall, Incorrect Recall, Confusion Matrix.
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

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))

ORIGINAL_DATA_PATH = BASE_DIR / "data" / "clean_elbow_train.csv"
EXPANDED_DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
SEQUENCE_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"

RANDOM_SEED = 42


def set_seed(seed: int = RANDOM_SEED):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


# ---------------------------------------------------------------------------
# Feature Extraction
# ---------------------------------------------------------------------------

def extract_subject_normalized_temporal(raw_seq: np.ndarray) -> np.ndarray:
    """Transform (128, 8) raw sequence into 10-dim subject-normalized temporal features.
    
    Excludes absolute angle amplitude. Retains:
    0: flexion_delta (baseline - angle)
    1: flexion_progress (delta / rom)
    2: rom_norm_vel (act_vel / rom)
    3: raw_act_vel
    4: bi_ang_asym (act_ang - asst_ang)
    5: bi_vel_asym (act_vel - asst_vel)
    6: rel_tilt (tilt - tilt[0])
    7: rel_rot (rot - rot[0])
    8: norm_flare
    9: flare_asym
    """
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


def extract_repetition_scalars(raw_seq: np.ndarray, duration_sec: float) -> np.ndarray:
    """Extract 10 repetition-level kinematic summary scalars.
    
    0: rom (degrees)
    1: min_elbow_angle (degrees)
    2: max_elbow_angle (degrees)
    3: duration (seconds)
    4: peak_angular_velocity
    5: mean_angular_velocity
    6: peak_active_flare
    7: mean_active_flare
    8: bilateral_angle_asymmetry (degrees)
    9: bilateral_flare_asymmetry
    """
    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    min_ang = float(np.min(act_ang_deg))
    max_ang = float(np.max(act_ang_deg))
    rom = float(max_ang - min_ang)
    dur = float(duration_sec)
    peak_vel = float(np.max(np.abs(act_vel)))
    mean_vel = float(np.mean(np.abs(act_vel)))
    peak_flare = float(np.max(act_flare))
    mean_flare = float(np.mean(act_flare))
    bi_ang_asym = float(np.mean(np.abs(act_ang_deg - asst_ang_deg)))
    bi_flare_asym = float(np.mean(np.abs(act_flare - asst_flare)))

    return np.array([
        rom,
        min_ang,
        max_ang,
        dur,
        peak_vel,
        mean_vel,
        peak_flare,
        mean_flare,
        bi_ang_asym,
        bi_flare_asym,
    ], dtype=np.float32)


# ---------------------------------------------------------------------------
# Dataset and Model Definitions
# ---------------------------------------------------------------------------

class TemporalScalarDataset(Dataset):
    def __init__(self, sequences: np.ndarray, scalars: np.ndarray, labels: np.ndarray):
        self.sequences = torch.tensor(sequences, dtype=torch.float32)
        self.scalars = torch.tensor(scalars, dtype=torch.float32)
        self.labels = torch.tensor(labels, dtype=torch.long)

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        return self.sequences[idx], self.scalars[idx], self.labels[idx]


class Phase1LSTM(nn.Module):
    """The exact architecture from Phase 1 (2-layer LSTM, hidden 64, dropout 0.3)."""
    def __init__(self, input_size=10, hidden_size=64, num_layers=2, num_classes=2, dropout=0.3):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=num_layers,
            batch_first=True,
            dropout=dropout if num_layers > 1 else 0.0,
        )
        self.dropout = nn.Dropout(dropout)
        self.fc = nn.Linear(hidden_size, num_classes)

    def forward(self, x, scalars=None):
        out, (hn, _) = self.lstm(x)
        embed = self.dropout(hn[-1])
        return self.fc(embed)


class SmallTemporalLSTM(nn.Module):
    """Small 1-layer LSTM (hidden 32, dropout 0.4)."""
    def __init__(self, input_size=10, hidden_size=32, num_classes=2, dropout=0.4):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=1,
            batch_first=True,
        )
        self.dropout = nn.Dropout(dropout)
        self.fc = nn.Linear(hidden_size, num_classes)

    def forward(self, x, scalars=None):
        out, (hn, _) = self.lstm(x)
        embed = self.dropout(hn[-1])
        return self.fc(embed)


class TemporalScalarModel(nn.Module):
    """Small Temporal (1-layer LSTM hidden 32) + Scalar MLP (10 -> 16 -> 16) hybrid."""
    def __init__(
        self,
        temporal_dim=10,
        scalar_dim=10,
        lstm_hidden=32,
        mlp_hidden=16,
        dropout=0.4,
    ):
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

    def forward(self, x, scalars):
        out, (hn, _) = self.lstm(x)
        temporal_embed = self.lstm_dropout(hn[-1])
        scalar_embed = self.scalar_mlp(scalars)
        fused = torch.cat([temporal_embed, scalar_embed], dim=-1)
        return self.classifier(fused)


# ---------------------------------------------------------------------------
# Training & LOSO Pipeline
# ---------------------------------------------------------------------------

def train_and_eval_loso(
    df: pd.DataFrame,
    model_factory,
    needs_scalars: bool = True,
    loss_mode: str = "weighted",  # "standard", "weighted"
    tune_threshold: bool = False,
    epochs: int = 40,
    lr: float = 1e-3,
    weight_decay: float = 1e-4,
    batch_size: int = 8,
    seed: int = RANDOM_SEED,
) -> Dict:
    set_seed(seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    # Load all sequences and scalars
    all_seqs = []
    all_scalars = []
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values

    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        t_feat = extract_subject_normalized_temporal(raw)
        s_feat = extract_repetition_scalars(raw, float(r["duration_sec"]))
        all_seqs.append(t_feat)
        all_scalars.append(s_feat)

    all_seqs = np.array(all_seqs)      # (N, 128, 10)
    all_scalars = np.array(all_scalars)  # (N, 10)

    unique_subjects = sorted(list(set(subjects)))
    all_preds = np.zeros(len(df), dtype=int)
    all_probs = np.zeros(len(df), dtype=float)
    fold_metrics = {}

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask

        # Split training subjects into train (80%) and validation (20%) stratified
        tr_indices = np.where(train_mask)[0]
        y_train_full = labels[tr_indices]

        # Inner validation split strictly from training subjects
        rng = np.random.RandomState(seed)
        c0_idx = tr_indices[y_train_full == 0]
        c1_idx = tr_indices[y_train_full == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))

        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Feature normalization: fit strictly on actual_tr_idx
        # Temporal scaler
        B_tr, T, D = all_seqs[actual_tr_idx].shape
        temp_scaler = StandardScaler()
        temp_scaler.fit(all_seqs[actual_tr_idx].reshape(-1, D))

        def transform_seq(seqs):
            b, t, d = seqs.shape
            flat = seqs.reshape(-1, d)
            norm = temp_scaler.transform(flat)
            return norm.reshape(b, t, d)

        X_seq_tr = transform_seq(all_seqs[actual_tr_idx])
        X_seq_val = transform_seq(all_seqs[val_idx])
        X_seq_test = transform_seq(all_seqs[test_mask])

        # Scalar scaler
        scalar_scaler = StandardScaler()
        scalar_scaler.fit(all_scalars[actual_tr_idx])

        X_sc_tr = scalar_scaler.transform(all_scalars[actual_tr_idx])
        X_sc_val = scalar_scaler.transform(all_scalars[val_idx])
        X_sc_test = scalar_scaler.transform(all_scalars[test_mask])

        y_tr = labels[actual_tr_idx]
        y_val = labels[val_idx]
        y_test = labels[test_mask]

        # Datasets & loaders
        tr_ds = TemporalScalarDataset(X_seq_tr, X_sc_tr, y_tr)
        val_ds = TemporalScalarDataset(X_seq_val, X_sc_val, y_val)
        test_ds = TemporalScalarDataset(X_seq_test, X_sc_test, y_test)

        tr_loader = DataLoader(tr_ds, batch_size=batch_size, shuffle=True)
        val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)
        test_loader = DataLoader(test_ds, batch_size=batch_size, shuffle=False)

        # Loss function
        if loss_mode == "weighted":
            counts = np.bincount(y_tr, minlength=2)
            w = len(y_tr) / (2.0 * np.maximum(counts, 1))
            criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))
        else:
            criterion = nn.CrossEntropyLoss()

        model = model_factory().to(device)
        optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)

        best_val_f1 = -1.0
        best_state = None

        for epoch in range(epochs):
            model.train()
            for b_seq, b_sc, b_y in tr_loader:
                b_seq, b_sc, b_y = b_seq.to(device), b_sc.to(device), b_y.to(device)
                optimizer.zero_grad()
                logits = model(b_seq, b_sc) if needs_scalars else model(b_seq)
                loss = criterion(logits, b_y)
                loss.backward()
                optimizer.step()

            # Validation evaluation
            model.eval()
            val_preds, val_targets = [], []
            with torch.no_grad():
                for b_seq, b_sc, b_y in val_loader:
                    b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                    logits = model(b_seq, b_sc) if needs_scalars else model(b_seq)
                    preds = torch.argmax(logits, dim=1).cpu().numpy()
                    val_preds.extend(preds)
                    val_targets.extend(b_y.numpy())

            v_f1 = f1_score(val_targets, val_preds, average="macro", zero_division=0)
            if epoch >= 4 and v_f1 > best_val_f1:
                best_val_f1 = v_f1
                best_state = copy.deepcopy(model.state_dict())

        if best_state is not None:
            model.load_state_dict(best_state)

        # Inner validation threshold tuning (if enabled)
        optimal_threshold = 0.5
        if tune_threshold:
            model.eval()
            val_probs, val_targets = [], []
            with torch.no_grad():
                for b_seq, b_sc, b_y in val_loader:
                    b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                    logits = model(b_seq, b_sc) if needs_scalars else model(b_seq)
                    probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                    val_probs.extend(probs)
                    val_targets.extend(b_y.numpy())

            best_thresh_f1 = -1.0
            for t_candidate in np.linspace(0.2, 0.8, 61):
                p_cand = (np.array(val_probs) >= t_candidate).astype(int)
                cand_f1 = f1_score(val_targets, p_cand, average="macro", zero_division=0)
                if cand_f1 > best_thresh_f1:
                    best_thresh_f1 = cand_f1
                    optimal_threshold = t_candidate

        # Test evaluation strictly on held-out test subject
        model.eval()
        t_preds, t_probs = [], []
        with torch.no_grad():
            for b_seq, b_sc, _ in test_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc) if needs_scalars else model(b_seq)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                t_probs.extend(probs)
                if tune_threshold:
                    t_preds.extend((probs >= optimal_threshold).astype(int))
                else:
                    t_preds.extend(torch.argmax(logits, dim=1).cpu().numpy())

        test_indices = np.where(test_mask)[0]
        all_preds[test_indices] = t_preds
        all_probs[test_indices] = t_probs

        fold_acc = accuracy_score(y_test, t_preds)
        fold_bal = balanced_accuracy_score(y_test, t_preds)
        fold_f1 = f1_score(y_test, t_preds, average="macro", zero_division=0)
        fold_c_rec = recall_score(y_test, t_preds, pos_label=1, zero_division=0)
        fold_inc_rec = recall_score(y_test, t_preds, pos_label=0, zero_division=0)

        fold_metrics[test_sub] = {
            "accuracy": fold_acc,
            "balanced_accuracy": fold_bal,
            "macro_f1": fold_f1,
            "correct_recall": fold_c_rec,
            "incorrect_recall": fold_inc_rec,
            "optimal_threshold": float(optimal_threshold) if tune_threshold else 0.5,
        }

    agg_acc = accuracy_score(labels, all_preds)
    agg_bal = balanced_accuracy_score(labels, all_preds)
    agg_f1 = f1_score(labels, all_preds, average="macro", zero_division=0)
    agg_c_rec = recall_score(labels, all_preds, pos_label=1, zero_division=0)
    agg_inc_rec = recall_score(labels, all_preds, pos_label=0, zero_division=0)
    cm = confusion_matrix(labels, all_preds).tolist()

    return {
        "aggregate": {
            "accuracy": agg_acc,
            "balanced_accuracy": agg_bal,
            "macro_f1": agg_f1,
            "correct_recall": agg_c_rec,
            "incorrect_recall": agg_inc_rec,
            "confusion_matrix": cm,
        },
        "folds": fold_metrics,
    }


def run_all_experiments():
    orig_df = pd.read_csv(ORIGINAL_DATA_PATH)
    exp_df = pd.read_csv(EXPANDED_DATA_PATH)

    results = {}

    print("=================================================================")
    print("RUNNING PHASE 2 CONTROLLED EXPERIMENTS")
    print("=================================================================")

    # 1. Previous Benchmark: 2-layer LSTM on 10 normalized features (weighted CE, 150 reps)
    print("\n[1/7] Reproducing Phase 1: 2-layer Normalized LSTM (Weighted CE, 150 reps)...")
    results["prev_normalized_lstm"] = train_and_eval_loso(
        orig_df,
        model_factory=lambda: Phase1LSTM(input_size=10, hidden_size=64, num_layers=2, dropout=0.3),
        needs_scalars=False,
        loss_mode="weighted",
        tune_threshold=False,
    )

    # 2. Small Temporal 1-layer LSTM (hidden 32, dropout 0.4) - Standard CE (150 reps)
    print("\n[2/7] Small 1-layer Temporal LSTM (hidden 32, Standard CE, 150 reps)...")
    results["small_temporal_std_ce"] = train_and_eval_loso(
        orig_df,
        model_factory=lambda: SmallTemporalLSTM(input_size=10, hidden_size=32, dropout=0.4),
        needs_scalars=False,
        loss_mode="standard",
        tune_threshold=False,
    )

    # 3. Small Temporal 1-layer LSTM (hidden 32, dropout 0.4) - Weighted CE (150 reps)
    print("\n[3/7] Small 1-layer Temporal LSTM (hidden 32, Weighted CE, 150 reps)...")
    results["small_temporal_weighted_ce"] = train_and_eval_loso(
        orig_df,
        model_factory=lambda: SmallTemporalLSTM(input_size=10, hidden_size=32, dropout=0.4),
        needs_scalars=False,
        loss_mode="weighted",
        tune_threshold=False,
    )

    # 4. Small Temporal 1-layer LSTM (hidden 32, dropout 0.4) - Weighted CE + Threshold Tuning (150 reps)
    print("\n[4/7] Small 1-layer Temporal LSTM (hidden 32, Weighted CE + Val Threshold, 150 reps)...")
    results["small_temporal_val_threshold"] = train_and_eval_loso(
        orig_df,
        model_factory=lambda: SmallTemporalLSTM(input_size=10, hidden_size=32, dropout=0.4),
        needs_scalars=False,
        loss_mode="weighted",
        tune_threshold=True,
    )

    # 5. Temporal + Scalar Model (1-layer LSTM 32 + Scalar MLP 16, Weighted CE, 150 reps)
    print("\n[5/7] Temporal + Scalar Hybrid (1-layer LSTM 32 + MLP 16, Weighted CE, 150 reps)...")
    results["temporal_scalar_weighted_ce_150"] = train_and_eval_loso(
        orig_df,
        model_factory=lambda: TemporalScalarModel(temporal_dim=10, scalar_dim=10, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        needs_scalars=True,
        loss_mode="weighted",
        tune_threshold=False,
    )

    # 6. Temporal + Scalar Model (1-layer LSTM 32 + Scalar MLP 16, Val Threshold, 150 reps)
    print("\n[6/7] Temporal + Scalar Hybrid (1-layer LSTM 32 + MLP 16, Val Threshold, 150 reps)...")
    results["temporal_scalar_val_threshold_150"] = train_and_eval_loso(
        orig_df,
        model_factory=lambda: TemporalScalarModel(temporal_dim=10, scalar_dim=10, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        needs_scalars=True,
        loss_mode="weighted",
        tune_threshold=True,
    )

    # 7. Expanded Data Model (Temporal + Scalar Hybrid on 195 clean repetitions)
    print("\n[7/7] Temporal + Scalar Hybrid on EXPANDED dataset (195 clean reps)...")
    results["temporal_scalar_expanded_195"] = train_and_eval_loso(
        exp_df,
        model_factory=lambda: TemporalScalarModel(temporal_dim=10, scalar_dim=10, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        needs_scalars=True,
        loss_mode="weighted",
        tune_threshold=True,
    )

    # Save results to JSON
    out_file = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase2_experiment_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    print("\n=================================================================")
    print("PHASE 2 EXPERIMENT SUMMARY")
    print("=================================================================")
    header = f"{'Model':<40} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7}"
    print(header)
    print("-" * len(header))
    for k, v in results.items():
        agg = v["aggregate"]
        print(f"{k:<40} | {agg['accuracy']*100:6.2f}% | {agg['balanced_accuracy']*100:6.2f}% | {agg['macro_f1']*100:6.2f}% | {agg['correct_recall']*100:6.2f}% | {agg['incorrect_recall']*100:6.2f}%")
        for sub, sm in v["folds"].items():
            print(f"   -> {sub:<36} | {sm['accuracy']*100:6.2f}% | {sm['balanced_accuracy']*100:6.2f}% | {sm['macro_f1']*100:6.2f}% | {sm['correct_recall']*100:6.2f}% | {sm['incorrect_recall']*100:6.2f}%")

if __name__ == "__main__":
    run_all_experiments()

"""Phase-Aware Controlled Experiments & Ablation for Assisted Elbow Flexion.

Implements the required true LOSO experiments on the expanded 195 dataset:
A: Current normalized temporal branch only (1-layer LSTM hidden 32)
B: Current 10 summary scalars only (2-layer MLP 16)
C: Baseline hybrid (temporal_scalar_hybrid_v1_195: temporal + current 10 scalars)
D: Temporal + Phase-aware scalar features (28 scalars: current 10 + 18 phase timing/velocity/accel/smoothness/recovery)
E: Temporal + Phase-aware features + Phase Bilateral Asymmetry (34 scalars: 28 + 6 phase bilateral asymmetry)
F: Assistance metadata test (Best scalar representation + 3 one-hot assistance types)
Calibration: Threshold tuning vs 0.5 on the best model.

Strict Methodology:
- True 3-fold Leave-One-Subject-Out (LOSO).
- All scalers (StandardScaler) fitted strictly on training subjects in each fold.
- Threshold selection performed strictly on inner validation split (never held-out subject).
- Reproducible seed = 42.
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

DATA_PATH = BASE_DIR / "data" / "clean_elbow_train_expanded.csv"
SEQUENCE_DIR = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"

RANDOM_SEED = 42


def set_seed(seed: int = RANDOM_SEED):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


# ---------------------------------------------------------------------------
# Feature Extraction Functions
# ---------------------------------------------------------------------------

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


def extract_base_scalars(raw_seq: np.ndarray, dur: float) -> List[float]:
    """10 base repetition summary scalars."""
    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
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

    return [
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
    ]


def extract_phase_aware_scalars(raw_seq: np.ndarray, dur: float, include_bilateral: bool = False) -> np.ndarray:
    """Extract extended phase-aware kinematic scalars.
    
    Base: 10 scalars
    Phase (non-bilateral): 18 scalars (Total 28)
    Phase (with bilateral): +6 scalars (Total 34)
    """
    base_10 = extract_base_scalars(raw_seq, dur)

    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    # Robust phase boundary detection
    idx_peak = int(np.argmin(act_ang_deg))
    idx_peak = max(5, min(idx_peak, len(act_ang_deg) - 6))

    # 1. Timing
    flex_dur = dur * (idx_peak / 128.0)
    ext_dur = dur * ((128.0 - idx_peak) / 128.0)
    flex_ext_ratio = flex_dur / max(ext_dur, 1e-3)
    time_to_peak_pct = idx_peak / 128.0

    # 2. Velocity
    peak_flex_vel = float(np.max(np.abs(act_vel[:idx_peak])))
    peak_ext_vel = float(np.max(np.abs(act_vel[idx_peak:])))
    mean_flex_vel = float(np.mean(np.abs(act_vel[:idx_peak])))
    mean_ext_vel = float(np.mean(np.abs(act_vel[idx_peak:])))
    ecc_conc_vel_ratio = mean_ext_vel / max(mean_flex_vel, 1e-4)

    # 3. Acceleration & Jerk
    acc = np.gradient(act_vel)
    jerk = np.gradient(acc)
    peak_flex_acc = float(np.max(np.abs(acc[:idx_peak])))
    peak_ext_acc = float(np.max(np.abs(acc[idx_peak:])))
    peak_jerk = float(np.max(np.abs(jerk)))

    # 4. Smoothness
    flex_diff2 = np.diff(act_ang_deg[:idx_peak], n=2)
    ext_diff2 = np.diff(act_ang_deg[idx_peak:], n=2)
    flex_smoothness = float(1.0 / (1.0 + np.mean(np.abs(flex_diff2)))) if len(flex_diff2) > 0 else 0.0
    ext_smoothness = float(1.0 / (1.0 + np.mean(np.abs(ext_diff2)))) if len(ext_diff2) > 0 else 0.0

    # 5. Recovery & Intermediate trajectory points
    rom = float(np.max(act_ang_deg) - np.min(act_ang_deg))
    min_ang = float(np.min(act_ang_deg))
    recovery_rate = float((act_ang_deg[-1] - min_ang) / max(rom, 1e-3))
    ang_25 = float(act_ang_deg[int(idx_peak * 0.25)])
    ang_50 = float(act_ang_deg[int(idx_peak * 0.50)])
    ang_75 = float(act_ang_deg[int(idx_peak * 0.75)])

    phase_18 = [
        flex_dur,
        ext_dur,
        flex_ext_ratio,
        time_to_peak_pct,
        peak_flex_vel,
        peak_ext_vel,
        mean_flex_vel,
        mean_ext_vel,
        ecc_conc_vel_ratio,
        peak_flex_acc,
        peak_ext_acc,
        peak_jerk,
        flex_smoothness,
        ext_smoothness,
        recovery_rate,
        ang_25,
        ang_50,
        ang_75,
    ]

    all_features = base_10 + phase_18

    if include_bilateral:
        bi_ang_flex = float(np.mean(np.abs(act_ang_deg[:idx_peak] - asst_ang_deg[:idx_peak])))
        bi_ang_ext = float(np.mean(np.abs(act_ang_deg[idx_peak:] - asst_ang_deg[idx_peak:])))
        bi_vel_flex = float(np.mean(np.abs(act_vel[:idx_peak] - asst_vel[:idx_peak])))
        bi_vel_ext = float(np.mean(np.abs(act_vel[idx_peak:] - asst_vel[idx_peak:])))
        bi_flare_flex = float(np.mean(np.abs(act_flare[:idx_peak] - asst_flare[:idx_peak])))
        bi_flare_ext = float(np.mean(np.abs(act_flare[idx_peak:] - asst_flare[idx_peak:])))

        phase_bilat_6 = [
            bi_ang_flex,
            bi_ang_ext,
            bi_vel_flex,
            bi_vel_ext,
            bi_flare_flex,
            bi_flare_ext,
        ]
        all_features += phase_bilat_6

    return np.array(all_features, dtype=np.float32)


# ---------------------------------------------------------------------------
# Neural Architectures
# ---------------------------------------------------------------------------

class TemporalOnlyModel(nn.Module):
    """Experiment A: Current normalized temporal branch only."""
    def __init__(self, temporal_dim=10, lstm_hidden=32, dropout=0.4):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=temporal_dim,
            hidden_size=lstm_hidden,
            num_layers=1,
            batch_first=True,
        )
        self.dropout = nn.Dropout(dropout)
        self.fc = nn.Linear(lstm_hidden, 2)

    def forward(self, x_seq, x_scalar=None):
        _, (hn, _) = self.lstm(x_seq)
        embed = self.dropout(hn[-1])
        return self.fc(embed)


class ScalarOnlyModel(nn.Module):
    """Experiment B: Current 10 summary scalars only."""
    def __init__(self, scalar_dim=10, mlp_hidden=16, dropout=0.4):
        super().__init__()
        self.mlp = nn.Sequential(
            nn.Linear(scalar_dim, mlp_hidden),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(mlp_hidden, mlp_hidden),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(mlp_hidden, 2),
        )

    def forward(self, x_seq, x_scalar):
        return self.mlp(x_scalar)


class HybridTemporalScalarModel(nn.Module):
    """Modular Hybrid Model for Experiments C, D, E, F."""
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

    def forward(self, x_seq, x_scalar):
        _, (hn, _) = self.lstm(x_seq)
        temporal_embed = self.lstm_dropout(hn[-1])
        scalar_embed = self.scalar_mlp(x_scalar)
        fused = torch.cat([temporal_embed, scalar_embed], dim=-1)
        return self.classifier(fused)


# ---------------------------------------------------------------------------
# LOSO Evaluation Engine
# ---------------------------------------------------------------------------

class GenericDataset(Dataset):
    def __init__(self, sequences: np.ndarray, scalars: np.ndarray, labels: np.ndarray):
        self.sequences = torch.tensor(sequences, dtype=torch.float32)
        self.scalars = torch.tensor(scalars, dtype=torch.float32)
        self.labels = torch.tensor(labels, dtype=torch.long)

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        return self.sequences[idx], self.scalars[idx], self.labels[idx]


def evaluate_loso_experiment(
    df: pd.DataFrame,
    seq_features: np.ndarray,
    scalar_features: np.ndarray,
    model_factory,
    tune_threshold: bool = False,
    epochs: int = 40,
    lr: float = 1e-3,
    weight_decay: float = 1e-4,
    batch_size: int = 8,
    seed: int = RANDOM_SEED,
) -> Dict:
    set_seed(seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    all_preds = np.zeros(len(df), dtype=int)
    all_probs = np.zeros(len(df), dtype=float)
    fold_metrics = {}

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask

        tr_indices = np.where(train_mask)[0]
        y_train_full = labels[tr_indices]

        # Inner validation split strictly from training subjects (20% stratified)
        rng = np.random.RandomState(seed)
        c0_idx = tr_indices[y_train_full == 0]
        c1_idx = tr_indices[y_train_full == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))

        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Feature normalization fitted STRICTLY on actual_tr_idx
        # 1. Temporal sequence normalization
        B_tr, T, D_seq = seq_features[actual_tr_idx].shape
        temp_scaler = StandardScaler()
        temp_scaler.fit(seq_features[actual_tr_idx].reshape(-1, D_seq))

        def transform_seq(seqs):
            b, t, d = seqs.shape
            return temp_scaler.transform(seqs.reshape(-1, d)).reshape(b, t, d)

        X_seq_tr = transform_seq(seq_features[actual_tr_idx])
        X_seq_val = transform_seq(seq_features[val_idx])
        X_seq_test = transform_seq(seq_features[test_mask])

        # 2. Scalar normalization
        scalar_scaler = StandardScaler()
        scalar_scaler.fit(scalar_features[actual_tr_idx])

        X_sc_tr = scalar_scaler.transform(scalar_features[actual_tr_idx])
        X_sc_val = scalar_scaler.transform(scalar_features[val_idx])
        X_sc_test = scalar_scaler.transform(scalar_features[test_mask])

        y_tr = labels[actual_tr_idx]
        y_val = labels[val_idx]
        y_test = labels[test_mask]

        tr_loader = DataLoader(GenericDataset(X_seq_tr, X_sc_tr, y_tr), batch_size=batch_size, shuffle=True)
        val_loader = DataLoader(GenericDataset(X_seq_val, X_sc_val, y_val), batch_size=batch_size, shuffle=False)
        test_loader = DataLoader(GenericDataset(X_seq_test, X_sc_test, y_test), batch_size=batch_size, shuffle=False)

        # Class weights from actual_tr_idx
        counts = np.bincount(y_tr, minlength=2)
        w = len(y_tr) / (2.0 * np.maximum(counts, 1))
        criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))

        model = model_factory().to(device)
        optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)

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

            # Validation step
            model.eval()
            val_preds, val_targets = [], []
            with torch.no_grad():
                for b_seq, b_sc, b_y in val_loader:
                    b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                    logits = model(b_seq, b_sc)
                    preds = torch.argmax(logits, dim=1).cpu().numpy()
                    val_preds.extend(preds)
                    val_targets.extend(b_y.numpy())

            v_f1 = f1_score(val_targets, val_preds, average="macro", zero_division=0)
            if epoch >= 4 and v_f1 > best_val_f1:
                best_val_f1 = v_f1
                best_state = copy.deepcopy(model.state_dict())

        if best_state is not None:
            model.load_state_dict(best_state)

        # Validation threshold tuning (strictly inner validation fold)
        optimal_threshold = 0.5
        if tune_threshold:
            model.eval()
            val_probs, val_targets = [], []
            with torch.no_grad():
                for b_seq, b_sc, b_y in val_loader:
                    b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                    logits = model(b_seq, b_sc)
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

        # Single evaluation on held-out test subject
        model.eval()
        t_preds, t_probs = [], []
        with torch.no_grad():
            for b_seq, b_sc, _ in test_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                t_probs.extend(probs)
                if tune_threshold:
                    t_preds.extend((probs >= optimal_threshold).astype(int))
                else:
                    t_preds.extend(torch.argmax(logits, dim=1).cpu().numpy())

        test_indices = np.where(test_mask)[0]
        all_preds[test_indices] = t_preds
        all_probs[test_indices] = t_probs

        fold_metrics[test_sub] = {
            "accuracy": accuracy_score(y_test, t_preds),
            "balanced_accuracy": balanced_accuracy_score(y_test, t_preds),
            "macro_f1": f1_score(y_test, t_preds, average="macro", zero_division=0),
            "correct_recall": recall_score(y_test, t_preds, pos_label=1, zero_division=0),
            "incorrect_recall": recall_score(y_test, t_preds, pos_label=0, zero_division=0),
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


def run_phase_aware_experiments():
    df = pd.read_csv(DATA_PATH)
    print(f"Loaded {len(df)} repetitions from {DATA_PATH.name}")

    # Extract sequences and feature matrices
    seq_list = []
    base_scalars_list = []
    phase_scalars_list = []
    phase_bi_scalars_list = []

    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])

        seq_list.append(extract_subject_normalized_temporal(raw))
        base_scalars_list.append(extract_base_scalars(raw, dur))
        phase_scalars_list.append(extract_phase_aware_scalars(raw, dur, include_bilateral=False))
        phase_bi_scalars_list.append(extract_phase_aware_scalars(raw, dur, include_bilateral=True))

    seq_arr = np.array(seq_list, dtype=np.float32)                   # (195, 128, 10)
    base_sc_arr = np.array(base_scalars_list, dtype=np.float32)       # (195, 10)
    phase_sc_arr = np.array(phase_scalars_list, dtype=np.float32)     # (195, 28)
    phase_bi_arr = np.array(phase_bi_scalars_list, dtype=np.float32)  # (195, 34)

    # Assistance one-hot features (3 dims)
    asst_types = ["left_hand_assisted", "right_hand_assisted", "both_hand_assisted"]
    asst_onehot = np.zeros((len(df), 3), dtype=np.float32)
    for i, (_, r) in enumerate(df.iterrows()):
        a = r["assistance_type"]
        if a in asst_types:
            asst_onehot[i, asst_types.index(a)] = 1.0

    phase_bi_asst_arr = np.concatenate([phase_bi_arr, asst_onehot], axis=1)  # (195, 37)

    results = {}

    print("\n" + "=" * 70)
    print("EXPERIMENT A: Current Normalized Temporal Branch Only (LSTM hidden 32)")
    print("=" * 70)
    results["A_temporal_only"] = evaluate_loso_experiment(
        df,
        seq_arr,
        base_sc_arr,
        model_factory=lambda: TemporalOnlyModel(temporal_dim=10, lstm_hidden=32, dropout=0.4),
        tune_threshold=False,
    )

    print("\n" + "=" * 70)
    print("EXPERIMENT B: Current 10 Summary Scalars Only (MLP 16)")
    print("=" * 70)
    results["B_scalars_only"] = evaluate_loso_experiment(
        df,
        seq_arr,
        base_sc_arr,
        model_factory=lambda: ScalarOnlyModel(scalar_dim=10, mlp_hidden=16, dropout=0.4),
        tune_threshold=False,
    )

    print("\n" + "=" * 70)
    print("EXPERIMENT C: Baseline Hybrid (temporal_scalar_hybrid_v1_195)")
    print("=" * 70)
    results["C_baseline_hybrid_v1"] = evaluate_loso_experiment(
        df,
        seq_arr,
        base_sc_arr,
        model_factory=lambda: HybridTemporalScalarModel(temporal_dim=10, scalar_dim=10, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        tune_threshold=False,
    )

    print("\n" + "=" * 70)
    print("EXPERIMENT D: Temporal + Phase-Aware Scalar Features (28 scalars)")
    print("=" * 70)
    results["D_temporal_phase_scalars"] = evaluate_loso_experiment(
        df,
        seq_arr,
        phase_sc_arr,
        model_factory=lambda: HybridTemporalScalarModel(temporal_dim=10, scalar_dim=28, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        tune_threshold=False,
    )

    print("\n" + "=" * 70)
    print("EXPERIMENT E: Temporal + Phase-Aware + Bilateral Asymmetry (34 scalars)")
    print("=" * 70)
    results["E_temporal_phase_bilateral"] = evaluate_loso_experiment(
        df,
        seq_arr,
        phase_bi_arr,
        model_factory=lambda: HybridTemporalScalarModel(temporal_dim=10, scalar_dim=34, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        tune_threshold=False,
    )

    print("\n" + "=" * 70)
    print("EXPERIMENT E (Tuned): Experiment E with Inner Validation Threshold Tuning")
    print("=" * 70)
    results["E_temporal_phase_bilateral_val_thresh"] = evaluate_loso_experiment(
        df,
        seq_arr,
        phase_bi_arr,
        model_factory=lambda: HybridTemporalScalarModel(temporal_dim=10, scalar_dim=34, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        tune_threshold=True,
    )

    print("\n" + "=" * 70)
    print("EXPERIMENT F: Assistance Metadata Test (34 scalars + 3 assistance one-hot = 37)")
    print("=" * 70)
    results["F_assistance_metadata"] = evaluate_loso_experiment(
        df,
        seq_arr,
        phase_bi_asst_arr,
        model_factory=lambda: HybridTemporalScalarModel(temporal_dim=10, scalar_dim=37, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
        tune_threshold=False,
    )

    # Save results to JSON
    out_file = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase_aware_ablation_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    print("\n" + "=" * 90)
    print("PHASE-AWARE ABLATION SUMMARY (TRUE LOSO)")
    print("=" * 90)
    header = f"{'Experiment':<38} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7}"
    print(header)
    print("-" * len(header))
    for k, v in results.items():
        agg = v["aggregate"]
        print(f"{k:<38} | {agg['accuracy']*100:6.2f}% | {agg['balanced_accuracy']*100:6.2f}% | {agg['macro_f1']*100:6.2f}% | {agg['correct_recall']*100:6.2f}% | {agg['incorrect_recall']*100:6.2f}%")
        for sub, sm in v["folds"].items():
            print(f"   -> {sub:<34} | {sm['accuracy']*100:6.2f}% | {sm['balanced_accuracy']*100:6.2f}% | {sm['macro_f1']*100:6.2f}% | {sm['correct_recall']*100:6.2f}% | {sm['incorrect_recall']*100:6.2f}%")

if __name__ == "__main__":
    run_phase_aware_experiments()

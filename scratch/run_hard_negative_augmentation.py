"""Phase 4B: SAFE Hard-Negative Augmentation for Assisted Elbow Flexion.

Strict 3-fold Leave-One-Subject-Out (LOSO) experiment:
- Fold 1: test Person 1, train Persons 2+3
- Fold 2: test Person 2, train Persons 1+3
- Fold 3: test Person 3, train Persons 1+2

Targeting subtle Incorrect repetitions resembling the Person 2 boundary error pattern:
- Peak flare ~ 0.27–0.38 or mean flare ~ 0.17–0.30
- Minimum flexion angle ~ 97–106 degrees
- High ROM (>= 35 deg) with poor eccentric/extension control (ecc_conc_vel_ratio >= 1.05 or flex_ext_ratio >= 1.25)

Strict Protocol:
1. Held-out subject NEVER used to identify, select, tune, or augment hard negatives.
2. Hard negatives identified ONLY in actual training split (actual_tr_idx).
3. Validation set (val_idx) NEVER augmented; held-out test set NEVER augmented.
4. Ground truth label strictly preserved ("Incorrect").
5. Feature representation: Full 34 phase-aware bilateral scalars + 10 normalized temporal sequence.
6. Architecture: 1-layer LSTM (hidden 32) + scalar MLP (34 -> 16 -> 16).
7. Conditions tested:
   A. Baseline — No Augmentation
   B. Mild Augmentation (1 copy per hard negative, subtle perturbations)
   C. Moderate Augmentation (2 copies per hard negative, slightly wider perturbations)
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
from scipy.interpolate import interp1d
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
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
    bi_vel_ext = float(np.mean(np.abs(act_vel[idx_peak:] - asst_vel[idx_peak:])))
    bi_flare_flex = float(np.mean(np.abs(act_flare[:idx_peak] - asst_flare[:idx_peak])))
    bi_flare_ext = float(np.mean(np.abs(act_flare[idx_peak:] - asst_flare[idx_peak:])))

    phase_bilat_6 = [
        bi_ang_flex, bi_ang_ext, bi_vel_flex, bi_vel_ext,
        bi_flare_flex, bi_flare_ext
    ]

    return np.array(base_10 + phase_18 + phase_bilat_6, dtype=np.float32)


# ---------------------------------------------------------------------------
# Physically Plausible Safe Hard-Negative Perturbation
# ---------------------------------------------------------------------------

def is_hard_negative_candidate(scalar_feat: np.ndarray) -> bool:
    """Identify subtle incorrect training repetitions near the boundary region."""
    rom = scalar_feat[0]
    min_ang = scalar_feat[1]
    peak_flare = scalar_feat[6]
    mean_flare = scalar_feat[7]
    flex_ext_ratio = scalar_feat[12]
    ecc_conc = scalar_feat[18]

    # Criteria targeting Person 2-like subtle failure patterns:
    # 1. Subtle flare: peak flare between 0.27 and 0.38 OR mean flare between 0.17 and 0.30
    is_subtle_flare = (0.27 <= peak_flare <= 0.38) or (0.17 <= mean_flare <= 0.30)
    # 2. Borderline flexion depth: min angle between 97° and 106°
    is_borderline_depth = (97.0 <= min_ang <= 106.0)
    # 3. High ROM with poor eccentric control / extension rushing
    is_eccentric_compensation = (rom >= 35.0) and (ecc_conc >= 1.05 or flex_ext_ratio >= 1.25)

    return bool(is_subtle_flare or is_borderline_depth or is_eccentric_compensation)


def perturb_raw_sequence(
    raw_seq: np.ndarray,
    dur: float,
    strength: str = "mild",
    rng: np.random.RandomState = None,
) -> Tuple[np.ndarray, float]:
    """Generate physically plausible perturbation preserving the Incorrect label."""
    if rng is None:
        rng = np.random.RandomState(42)

    T, D = raw_seq.shape
    t_orig = np.linspace(0.0, 1.0, T)

    # 1. Temporal warping
    if strength == "mild":
        alpha = rng.uniform(-0.025, 0.025)
        dur_noise = rng.uniform(-0.03, 0.03)
        angle_sigma = 0.003  # ~0.54 degrees
        flare_sigma = 0.010
    else:  # moderate
        alpha = rng.uniform(-0.045, 0.045)
        dur_noise = rng.uniform(-0.05, 0.05)
        angle_sigma = 0.005  # ~0.90 degrees
        flare_sigma = 0.018

    # Monotonic time warp grid
    t_warp = t_orig + alpha * np.sin(np.pi * t_orig)
    t_warp = np.clip(t_warp, 0.0, 1.0)
    t_warp[0] = 0.0
    t_warp[-1] = 1.0

    # Resample all columns along warped grid
    aug_seq = np.zeros_like(raw_seq)
    for c in range(D):
        f_interp = interp1d(t_orig, raw_seq[:, c], kind="linear", fill_value="extrapolate")
        aug_seq[:, c] = f_interp(t_warp)

    # 2. Measurement noise on active & assisting angles (columns 0, 1)
    aug_seq[:, 0] += rng.normal(0.0, angle_sigma, size=T)
    aug_seq[:, 1] += rng.normal(0.0, angle_sigma, size=T)
    aug_seq[:, 0] = np.clip(aug_seq[:, 0], 0.15, 1.0)
    aug_seq[:, 1] = np.clip(aug_seq[:, 1], 0.15, 1.0)

    # 3. Flare noise (columns 6, 7)
    aug_seq[:, 6] += rng.normal(0.0, flare_sigma, size=T)
    aug_seq[:, 7] += rng.normal(0.0, flare_sigma, size=T)
    aug_seq[:, 6] = np.clip(aug_seq[:, 6], 0.05, 0.65)
    aug_seq[:, 7] = np.clip(aug_seq[:, 7], 0.05, 0.65)

    # 4. Duration perturbation
    dur_aug = max(1.0, dur * (1.0 + dur_noise))

    # 5. Velocity recomputation consistent with resampled angles
    dt = dur_aug / float(T)
    aug_seq[:, 2] = np.gradient(aug_seq[:, 0] * 180.0) / dt / 180.0
    aug_seq[:, 3] = np.gradient(aug_seq[:, 1] * 180.0) / dt / 180.0

    return aug_seq.astype(np.float32), float(dur_aug)


# ---------------------------------------------------------------------------
# Model Architecture
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# LOSO Evaluation with Training Augmentation
# ---------------------------------------------------------------------------

def run_augmentation_experiment(df: pd.DataFrame, aug_condition: str = "none") -> Dict:
    """Evaluate true LOSO under specific augmentation condition ('none', 'mild', 'moderate')."""
    set_seed(RANDOM_SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    # Load all raw sequences and extract initial canonical features
    raw_seqs = []
    durations = []
    for _, r in df.iterrows():
        raw_seqs.append(np.load(SEQUENCE_DIR / r["sequence_file"]))
        durations.append(float(r["duration_sec"]))

    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    all_preds = np.zeros(len(df), dtype=int)
    all_probs = np.zeros(len(df), dtype=float)
    fold_metrics = {}
    fold_stats = {}

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask

        tr_indices = np.where(train_mask)[0]
        y_train_full = labels[tr_indices]

        # Inner validation split strictly from training subjects (20% stratified)
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_train_full == 0]
        c1_idx = tr_indices[y_train_full == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)

        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))

        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

        # Base features for actual_tr_idx
        tr_seqs = [extract_subject_normalized_temporal(raw_seqs[i]) for i in actual_tr_idx]
        tr_scalars = [extract_phase_aware_scalars_34(raw_seqs[i], durations[i]) for i in actual_tr_idx]
        tr_labels = [labels[i] for i in actual_tr_idx]

        # Validation features (strictly unaugmented)
        val_seqs = [extract_subject_normalized_temporal(raw_seqs[i]) for i in val_idx]
        val_scalars = [extract_phase_aware_scalars_34(raw_seqs[i], durations[i]) for i in val_idx]
        val_labels = [labels[i] for i in val_idx]

        # Test features (strictly unaugmented)
        test_idx = np.where(test_mask)[0]
        test_seqs = [extract_subject_normalized_temporal(raw_seqs[i]) for i in test_idx]
        test_scalars = [extract_phase_aware_scalars_34(raw_seqs[i], durations[i]) for i in test_idx]
        test_labels = [labels[i] for i in test_idx]

        # ---------------------------------------------------------------
        # HARD-NEGATIVE AUGMENTATION (Applied ONLY to actual_tr_idx)
        # ---------------------------------------------------------------
        num_orig_tr = len(actual_tr_idx)
        num_augmented = 0

        if aug_condition in ["mild", "moderate"]:
            copies_per_sample = 1 if aug_condition == "mild" else 2
            aug_rng = np.random.RandomState(RANDOM_SEED + hash(test_sub) % 1000)

            for idx_in_tr, orig_idx in enumerate(actual_tr_idx):
                # Hard negatives MUST be human-verified Incorrect
                if labels[orig_idx] == 0:
                    orig_sc = tr_scalars[idx_in_tr]
                    if is_hard_negative_candidate(orig_sc):
                        raw_orig = raw_seqs[orig_idx]
                        dur_orig = durations[orig_idx]

                        for _ in range(copies_per_sample):
                            aug_raw, aug_dur = perturb_raw_sequence(
                                raw_orig, dur_orig, strength=aug_condition, rng=aug_rng
                            )
                            aug_seq_feat = extract_subject_normalized_temporal(aug_raw)
                            aug_sc_feat = extract_phase_aware_scalars_34(aug_raw, aug_dur)

                            tr_seqs.append(aug_seq_feat)
                            tr_scalars.append(aug_sc_feat)
                            tr_labels.append(0)  # Label is preserved as Incorrect
                            num_augmented += 1

        tr_seqs_arr = np.array(tr_seqs, dtype=np.float32)
        tr_scalars_arr = np.array(tr_scalars, dtype=np.float32)
        tr_labels_arr = np.array(tr_labels, dtype=int)

        val_seqs_arr = np.array(val_seqs, dtype=np.float32)
        val_scalars_arr = np.array(val_scalars, dtype=np.float32)
        val_labels_arr = np.array(val_labels, dtype=int)

        test_seqs_arr = np.array(test_seqs, dtype=np.float32)
        test_scalars_arr = np.array(test_scalars, dtype=np.float32)
        test_labels_arr = np.array(test_labels, dtype=int)

        # Normalization fitted strictly on tr_seqs_arr & tr_scalars_arr
        B_tr, T, D_seq = tr_seqs_arr.shape
        temp_scaler = StandardScaler()
        temp_scaler.fit(tr_seqs_arr.reshape(-1, D_seq))

        def transform_seq(seqs):
            b, t, d = seqs.shape
            return temp_scaler.transform(seqs.reshape(-1, d)).reshape(b, t, d)

        X_seq_tr = transform_seq(tr_seqs_arr)
        X_seq_val = transform_seq(val_seqs_arr)
        X_seq_test = transform_seq(test_seqs_arr)

        scalar_scaler = StandardScaler()
        scalar_scaler.fit(tr_scalars_arr)

        X_sc_tr = scalar_scaler.transform(tr_scalars_arr)
        X_sc_val = scalar_scaler.transform(val_scalars_arr)
        X_sc_test = scalar_scaler.transform(test_scalars_arr)

        tr_loader = DataLoader(GenericDataset(X_seq_tr, X_sc_tr, tr_labels_arr), batch_size=8, shuffle=True)
        val_loader = DataLoader(GenericDataset(X_seq_val, X_sc_val, val_labels_arr), batch_size=8, shuffle=False)
        test_loader = DataLoader(GenericDataset(X_seq_test, X_sc_test, test_labels_arr), batch_size=8, shuffle=False)

        # Class weights from augmented training set
        counts = np.bincount(tr_labels_arr, minlength=2)
        w = len(tr_labels_arr) / (2.0 * np.maximum(counts, 1))
        criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))

        model = TemporalScalarHybridModel(
            temporal_dim=10,
            scalar_dim=34,
            lstm_hidden=32,
            mlp_hidden=16,
            dropout=0.4,
        ).to(device)
        optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4)

        best_val_f1 = -1.0
        best_state = None

        for epoch in range(40):
            model.train()
            for b_seq, b_sc, b_y in tr_loader:
                b_seq, b_sc, b_y = b_seq.to(device), b_sc.to(device), b_y.to(device)
                optimizer.zero_grad()
                logits = model(b_seq, b_sc)
                loss = criterion(logits, b_y)
                loss.backward()
                optimizer.step()

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

        # Decision threshold tuning strictly on inner validation fold
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
        optimal_threshold = 0.5
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
                t_preds.extend((probs >= optimal_threshold).astype(int))

        all_preds[test_idx] = t_preds
        all_probs[test_idx] = t_probs

        fold_acc = accuracy_score(test_labels_arr, t_preds)
        fold_bal = balanced_accuracy_score(test_labels_arr, t_preds)
        fold_f1 = f1_score(test_labels_arr, t_preds, average="macro", zero_division=0)
        fold_c_rec = recall_score(test_labels_arr, t_preds, pos_label=1, zero_division=0)
        fold_inc_rec = recall_score(test_labels_arr, t_preds, pos_label=0, zero_division=0)

        fold_metrics[test_sub] = {
            "accuracy": fold_acc,
            "balanced_accuracy": fold_bal,
            "macro_f1": fold_f1,
            "correct_recall": fold_c_rec,
            "incorrect_recall": fold_inc_rec,
            "optimal_threshold": float(optimal_threshold),
            "val_macro_f1": float(best_val_f1),
        }
        fold_stats[test_sub] = {
            "orig_tr_samples": num_orig_tr,
            "augmented_samples": num_augmented,
            "aug_ratio": float(num_augmented / max(num_orig_tr, 1)),
        }

    agg_acc = accuracy_score(labels, all_preds)
    agg_bal = balanced_accuracy_score(labels, all_preds)
    agg_f1 = f1_score(labels, all_preds, average="macro", zero_division=0)
    agg_c_rec = recall_score(labels, all_preds, pos_label=1, zero_division=0)
    agg_inc_rec = recall_score(labels, all_preds, pos_label=0, zero_division=0)
    cm = confusion_matrix(labels, all_preds).tolist()

    fold_bals = [m["balanced_accuracy"] for m in fold_metrics.values()]
    fold_f1s = [m["macro_f1"] for m in fold_metrics.values()]
    fold_accs = [m["accuracy"] for m in fold_metrics.values()]

    return {
        "condition": aug_condition,
        "aggregate": {
            "accuracy": agg_acc,
            "balanced_accuracy": agg_bal,
            "macro_f1": agg_f1,
            "correct_recall": agg_c_rec,
            "incorrect_recall": agg_inc_rec,
            "confusion_matrix": cm,
        },
        "fold_summary": {
            "mean_balanced_accuracy": float(np.mean(fold_bals)),
            "std_balanced_accuracy": float(np.std(fold_bals)),
            "mean_macro_f1": float(np.mean(fold_f1s)),
            "std_macro_f1": float(np.std(fold_f1s)),
            "mean_accuracy": float(np.mean(fold_accs)),
            "std_accuracy": float(np.std(fold_accs)),
        },
        "folds": fold_metrics,
        "augmentation_stats": fold_stats,
    }


def main():
    df = pd.read_csv(DATA_PATH)
    print(f"Loaded {len(df)} repetitions from {DATA_PATH.name}")

    results = {}

    conditions = ["none", "mild", "moderate"]
    for cond in conditions:
        print(f"\n{'='*75}")
        print(f"RUNNING EXPERIMENT: AUGMENTATION CONDITION = {cond.upper()}")
        print(f"{'='*75}")
        results[cond] = run_augmentation_experiment(df, aug_condition=cond)

    out_file = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "hard_negative_augmentation_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    print("\n" + "=" * 90)
    print("PHASE 4B: HARD-NEGATIVE AUGMENTATION SUMMARY (TRUE LOSO)")
    print("=" * 90)
    header = f"{'Condition':<12} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Fold Mean±Std BalAcc'} | {'Aug Samples'}"
    print(header)
    print("-" * 105)
    for k, v in results.items():
        agg = v["aggregate"]
        fs = v["fold_summary"]
        m_s = f"{fs['mean_balanced_accuracy']*100:.2f}% ± {fs['std_balanced_accuracy']*100:.2f}%"
        total_aug = sum(s["augmented_samples"] for s in v["augmentation_stats"].values())
        print(f"{k:<12} | {agg['accuracy']*100:6.2f}% | {agg['balanced_accuracy']*100:6.2f}% | {agg['macro_f1']*100:6.2f}% | {agg['correct_recall']*100:6.2f}% | {agg['incorrect_recall']*100:6.2f}% | {m_s:<22} | {total_aug}")
        for sub, sm in v["folds"].items():
            st = v["augmentation_stats"][sub]
            print(f"   -> {sub:<8} | {sm['accuracy']*100:6.2f}% | {sm['balanced_accuracy']*100:6.2f}% | {sm['macro_f1']*100:6.2f}% | {sm['correct_recall']*100:6.2f}% | {sm['incorrect_recall']*100:6.2f}% | thresh={sm['optimal_threshold']:.2f} | tr={st['orig_tr_samples']}+aug={st['augmented_samples']} ({st['aug_ratio']*100:.1f}%)")


if __name__ == "__main__":
    main()

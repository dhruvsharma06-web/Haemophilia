"""Phase 5: Cross-validated Rule + ML Hybrid Evaluation for Assisted Elbow Flexion.

Evaluates 6 conditions under strict 3-fold Leave-One-Subject-Out (LOSO):
A. Rule-only baseline
B. ML-only frozen v2 baseline (temporal_phase_bilateral_hybrid)
C. Simple logical hybrid (override only when rule is ambiguous)
D. Probability blending (alpha * ml_prob + (1 - alpha) * rule_score)
E. Rule-confidence gating (gate near boundary to ML)
F. ML-assisted error correction (learned override policy from inner validation)

CRITICAL NO-LEAKAGE RULE:
All parameters (alpha, thresholds, gate margins, override policies) are learned/tuned
STRICTLY on the inner validation split of each fold.
Held-out test subject is evaluated exactly once at the end of each fold.
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
from sklearn.ensemble import RandomForestClassifier
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
# Biomechanical Deterministic Rule & Margin Functions
# ---------------------------------------------------------------------------

def compute_rule_metrics(row: pd.Series) -> Tuple[int, float, float]:
    """Compute rule prediction, continuous rule margin, and continuous rule score.
    
    Rule thresholds:
    - min_elbow_angle <= 101.0
    - elbow_flare <= 0.30
    - rom >= 25.0
    - torso_tilt <= 5.0
    """
    min_a = float(row["min_elbow_angle"])
    flare = float(row["elbow_flare"])
    rom = float(row["rom"])
    tilt = float(row["torso_tilt"])

    m_ang = (101.0 - min_a) / 10.0
    m_flare = (0.30 - flare) / 0.10
    m_rom = (rom - 25.0) / 10.0
    m_tilt = (5.0 - tilt) / 2.0

    # Margin: positive = safe (Correct), negative = violation (Incorrect)
    margin = min(m_ang, m_flare, m_rom, m_tilt)
    pred = 1 if margin >= 0 else 0

    # Continuous score via logistic sigmoid
    rule_score = float(1.0 / (1.0 + np.exp(-2.0 * margin)))

    return pred, margin, rule_score


# ---------------------------------------------------------------------------
# Feature Extraction Functions (Identical to Frozen v2 Baseline)
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
# Neural Architecture
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
# Pipeline Engine
# ---------------------------------------------------------------------------

def run_phase5_experiment():
    set_seed(RANDOM_SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    df = pd.read_csv(DATA_PATH)
    print(f"Loaded {len(df)} repetitions from {DATA_PATH.name}")

    # Compute rule metrics for all repetitions
    rule_preds = []
    rule_margins = []
    rule_scores = []
    for _, r in df.iterrows():
        p, m, s = compute_rule_metrics(r)
        rule_preds.append(p)
        rule_margins.append(m)
        rule_scores.append(s)

    rule_preds = np.array(rule_preds, dtype=int)
    rule_margins = np.array(rule_margins, dtype=np.float32)
    rule_scores = np.array(rule_scores, dtype=np.float32)

    # Extract ML features
    seq_list = []
    scalar_list = []
    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        seq_list.append(extract_subject_normalized_temporal(raw))
        scalar_list.append(extract_phase_aware_scalars_34(raw, dur))

    all_seqs = np.array(seq_list, dtype=np.float32)       # (195, 128, 10)
    all_scalars = np.array(scalar_list, dtype=np.float32)  # (195, 34)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    # Prediction containers for all 6 conditions
    preds = {
        "A_rule_only": np.zeros(len(df), dtype=int),
        "B_ml_v2": np.zeros(len(df), dtype=int),
        "C_simple_logical_hybrid": np.zeros(len(df), dtype=int),
        "D_prob_blending": np.zeros(len(df), dtype=int),
        "E_confidence_gating": np.zeros(len(df), dtype=int),
        "F_error_correction": np.zeros(len(df), dtype=int),
    }

    ml_probs_all = np.zeros(len(df), dtype=float)

    # Train ML models for each LOSO fold and calibrate hybrid parameters
    fold_details = {k: {} for k in preds}
    fold_tuned_params = {k: {} for k in preds}

    for test_sub in unique_subjects:
        set_seed(RANDOM_SEED)
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask
        test_idx = np.where(test_mask)[0]

        tr_indices = np.where(train_mask)[0]
        y_train_full = labels[tr_indices]

        # Align numpy RNG state with v2 baseline
        rf = RandomForestClassifier(n_estimators=100, random_state=42)
        rf.fit(all_scalars[tr_indices], y_train_full)

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
        B_tr, T, D_seq = all_seqs[actual_tr_idx].shape
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

        tr_loader = DataLoader(GenericDataset(X_seq_tr, X_sc_tr, y_tr), batch_size=8, shuffle=True)
        val_loader = DataLoader(GenericDataset(X_seq_val, X_sc_val, y_val), batch_size=8, shuffle=False)
        test_loader = DataLoader(GenericDataset(X_seq_test, X_sc_test, y_test), batch_size=8, shuffle=False)

        # Class weights from actual_tr_idx
        counts = np.bincount(y_tr, minlength=2)
        w = len(y_tr) / (2.0 * np.maximum(counts, 1))
        criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))

        model = TemporalScalarHybridModel(
            temporal_dim=10, scalar_dim=34, lstm_hidden=32, mlp_hidden=16, dropout=0.4
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

        # Compute validation probabilities
        model.eval()
        val_ml_probs = []
        with torch.no_grad():
            for b_seq, b_sc, _ in val_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                val_ml_probs.extend(probs)
        val_ml_probs = np.array(val_ml_probs)

        # Compute test probabilities
        test_ml_probs = []
        with torch.no_grad():
            for b_seq, b_sc, _ in test_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                test_ml_probs.extend(probs)
        test_ml_probs = np.array(test_ml_probs)
        ml_probs_all[test_idx] = test_ml_probs

        # Validation rule metrics
        val_r_preds = rule_preds[val_idx]
        val_r_margins = rule_margins[val_idx]
        val_r_scores = rule_scores[val_idx]

        # Test rule metrics
        test_r_preds = rule_preds[test_idx]
        test_r_margins = rule_margins[test_idx]
        test_r_scores = rule_scores[test_idx]

        # -------------------------------------------------------------------
        # Condition A: Rule-only
        # -------------------------------------------------------------------
        preds["A_rule_only"][test_idx] = test_r_preds

        # -------------------------------------------------------------------
        # Condition B: ML-only (v2 threshold tuning)
        # -------------------------------------------------------------------
        best_b_f1 = -1.0
        opt_b_thresh = 0.5
        for t_cand in np.linspace(0.2, 0.8, 61):
            cand_p = (val_ml_probs >= t_cand).astype(int)
            cand_f1 = f1_score(y_val, cand_p, average="macro", zero_division=0)
            if cand_f1 > best_b_f1:
                best_b_f1 = cand_f1
                opt_b_thresh = t_cand

        test_b_preds = (test_ml_probs >= opt_b_thresh).astype(int)
        preds["B_ml_v2"][test_idx] = test_b_preds
        fold_tuned_params["B_ml_v2"][test_sub] = {"threshold": float(opt_b_thresh)}

        # -------------------------------------------------------------------
        # Condition C: Simple Logical Hybrid (override only when rule is ambiguous)
        # -------------------------------------------------------------------
        # When |margin| <= theta_ambig, use ML prediction; else use Rule prediction.
        best_c_f1 = -1.0
        opt_c_theta = 0.0
        for theta in np.linspace(0.0, 1.2, 61):
            is_ambig = (np.abs(val_r_margins) <= theta)
            val_c_pred = np.where(is_ambig, (val_ml_probs >= opt_b_thresh).astype(int), val_r_preds)
            c_f1 = f1_score(y_val, val_c_pred, average="macro", zero_division=0)
            if c_f1 > best_c_f1:
                best_c_f1 = c_f1
                opt_c_theta = theta

        test_is_ambig = (np.abs(test_r_margins) <= opt_c_theta)
        test_c_preds = np.where(test_is_ambig, test_b_preds, test_r_preds)
        preds["C_simple_logical_hybrid"][test_idx] = test_c_preds
        fold_tuned_params["C_simple_logical_hybrid"][test_sub] = {"ambiguity_theta": float(opt_c_theta)}

        # -------------------------------------------------------------------
        # Condition D: Probability Blending
        # hybrid_score = alpha * ml_prob + (1 - alpha) * rule_score
        # -------------------------------------------------------------------
        best_d_f1 = -1.0
        opt_d_alpha = 0.5
        opt_d_tau = 0.5
        for alpha in np.linspace(0.0, 1.0, 21):
            blend_val = alpha * val_ml_probs + (1.0 - alpha) * val_r_scores
            for tau in np.linspace(0.3, 0.7, 41):
                cand_p = (blend_val >= tau).astype(int)
                d_f1 = f1_score(y_val, cand_p, average="macro", zero_division=0)
                if d_f1 > best_d_f1:
                    best_d_f1 = d_f1
                    opt_d_alpha = alpha
                    opt_d_tau = tau

        blend_test = opt_d_alpha * test_ml_probs + (1.0 - opt_d_alpha) * test_r_scores
        test_d_preds = (blend_test >= opt_d_tau).astype(int)
        preds["D_prob_blending"][test_idx] = test_d_preds
        fold_tuned_params["D_prob_blending"][test_sub] = {"alpha": float(opt_d_alpha), "tau": float(opt_d_tau)}

        # -------------------------------------------------------------------
        # Condition E: Rule-Confidence Gating
        # If |margin| <= theta_gate, use ML; else trust Rule
        # -------------------------------------------------------------------
        best_e_f1 = -1.0
        opt_e_theta = 0.0
        for theta in np.linspace(0.0, 1.5, 76):
            is_boundary = (np.abs(val_r_margins) <= theta)
            val_e_pred = np.where(is_boundary, (val_ml_probs >= opt_b_thresh).astype(int), val_r_preds)
            e_f1 = f1_score(y_val, val_e_pred, average="macro", zero_division=0)
            if e_f1 > best_e_f1:
                best_e_f1 = e_f1
                opt_e_theta = theta

        test_is_boundary = (np.abs(test_r_margins) <= opt_e_theta)
        test_e_preds = np.where(test_is_boundary, test_b_preds, test_r_preds)
        preds["E_confidence_gating"][test_idx] = test_e_preds
        fold_tuned_params["E_confidence_gating"][test_sub] = {"gate_theta": float(opt_e_theta)}

        # -------------------------------------------------------------------
        # Condition F: ML-Assisted Error Correction
        # Learn override thresholds strictly from validation errors:
        # Override Rule Correct -> Incorrect if ML is confident Incorrect (ml_prob <= tau_fp)
        # Override Rule Incorrect -> Correct if ML is confident Correct (ml_prob >= tau_fn)
        # -------------------------------------------------------------------
        best_f_f1 = -1.0
        opt_f_fp = 0.0
        opt_f_fn = 1.0
        for tau_fp in np.linspace(0.0, 0.45, 19):
            for tau_fn in np.linspace(0.55, 1.0, 19):
                val_f_pred = np.copy(val_r_preds)
                # Override rule Correct to Incorrect if ML says strong Incorrect
                val_f_pred[(val_r_preds == 1) & (val_ml_probs <= tau_fp)] = 0
                # Override rule Incorrect to Correct if ML says strong Correct
                val_f_pred[(val_r_preds == 0) & (val_ml_probs >= tau_fn)] = 1

                f_f1 = f1_score(y_val, val_f_pred, average="macro", zero_division=0)
                if f_f1 > best_f_f1:
                    best_f_f1 = f_f1
                    opt_f_fp = tau_fp
                    opt_f_fn = tau_fn

        test_f_preds = np.copy(test_r_preds)
        test_f_preds[(test_r_preds == 1) & (test_ml_probs <= opt_f_fp)] = 0
        test_f_preds[(test_r_preds == 0) & (test_ml_probs >= opt_f_fn)] = 1
        preds["F_error_correction"][test_idx] = test_f_preds
        fold_tuned_params["F_error_correction"][test_sub] = {"tau_fp": float(opt_f_fp), "tau_fn": float(opt_f_fn)}

    # -----------------------------------------------------------------------
    # Comprehensive Reporting & Metric Calculations
    # -----------------------------------------------------------------------
    results = {}
    r_preds = preds["A_rule_only"]
    ml_preds = preds["B_ml_v2"]

    # Rule vs ML Disagreement mask across the whole dataset
    disagree_mask = (r_preds != ml_preds)
    num_disagree = int(np.sum(disagree_mask))
    print(f"\nTotal Rule/ML Disagreements: {num_disagree} / {len(df)} ({num_disagree/len(df)*100:.1f}%)")

    for cond_k, cond_p in preds.items():
        acc = accuracy_score(labels, cond_p)
        bal = balanced_accuracy_score(labels, cond_p)
        f1 = f1_score(labels, cond_p, average="macro", zero_division=0)
        c_rec = recall_score(labels, cond_p, pos_label=1, zero_division=0)
        inc_rec = recall_score(labels, cond_p, pos_label=0, zero_division=0)
        cm = confusion_matrix(labels, cond_p).tolist()

        # Per subject metrics
        sub_metrics = {}
        for sub in unique_subjects:
            sub_m = (subjects == sub)
            y_s = labels[sub_m]
            p_s = cond_p[sub_m]
            sub_metrics[sub] = {
                "accuracy": accuracy_score(y_s, p_s),
                "balanced_accuracy": balanced_accuracy_score(y_s, p_s),
                "macro_f1": f1_score(y_s, p_s, average="macro", zero_division=0),
                "correct_recall": recall_score(y_s, p_s, pos_label=1, zero_division=0),
                "incorrect_recall": recall_score(y_s, p_s, pos_label=0, zero_division=0),
            }

        fold_bals = [sm["balanced_accuracy"] for sm in sub_metrics.values()]
        fold_f1s = [sm["macro_f1"] for sm in sub_metrics.values()]
        fold_accs = [sm["accuracy"] for sm in sub_metrics.values()]

        # Overrides compared to rule
        override_mask = (cond_p != r_preds)
        num_overrides = int(np.sum(override_mask))
        successful_overrides = int(np.sum(override_mask & (cond_p == labels)))
        harmful_overrides = int(np.sum(override_mask & (cond_p != labels)))

        # Performance on disagreement cases
        if num_disagree > 0:
            disagree_acc = accuracy_score(labels[disagree_mask], cond_p[disagree_mask])
            disagree_bal = balanced_accuracy_score(labels[disagree_mask], cond_p[disagree_mask])
            disagree_f1 = f1_score(labels[disagree_mask], cond_p[disagree_mask], average="macro", zero_division=0)
        else:
            disagree_acc, disagree_bal, disagree_f1 = 0.0, 0.0, 0.0

        results[cond_k] = {
            "aggregate": {
                "accuracy": acc,
                "balanced_accuracy": bal,
                "macro_f1": f1,
                "correct_recall": c_rec,
                "incorrect_recall": inc_rec,
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
            "sub_metrics": sub_metrics,
            "override_diagnostics": {
                "total_disagreements": num_disagree,
                "num_overrides": num_overrides,
                "successful_overrides": successful_overrides,
                "harmful_overrides": harmful_overrides,
                "net_gain": successful_overrides - harmful_overrides,
                "disagreement_accuracy": disagree_acc,
                "disagreement_balanced_accuracy": disagree_bal,
                "disagreement_macro_f1": disagree_f1,
            },
            "tuned_parameters": fold_tuned_params[cond_k],
        }

    # Save to JSON
    out_file = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "rule_ml_hybrid_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    # Print summary
    print("\n" + "=" * 105)
    print("PHASE 5: RULE + ML HYBRID EVALUATION SUMMARY (TRUE LOSO)")
    print("=" * 105)
    header = f"{'Condition':<26} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Fold BalAcc Mean±Std':<22} | {'Overrides (Succ/Harm)'}"
    print(header)
    print("-" * 125)
    for k, v in results.items():
        agg = v["aggregate"]
        fs = v["fold_summary"]
        od = v["override_diagnostics"]
        m_s = f"{fs['mean_balanced_accuracy']*100:.2f}% ± {fs['std_balanced_accuracy']*100:.2f}%"
        ov_str = f"{od['num_overrides']} ({od['successful_overrides']}/{od['harmful_overrides']})"
        print(f"{k:<26} | {agg['accuracy']*100:6.2f}% | {agg['balanced_accuracy']*100:6.2f}% | {agg['macro_f1']*100:6.2f}% | {agg['correct_recall']*100:6.2f}% | {agg['incorrect_recall']*100:6.2f}% | {m_s:<22} | {ov_str}")

    print("\n" + "=" * 105)
    print("PER-SUBJECT METRICS:")
    print("=" * 105)
    for k, v in results.items():
        print(f"\n--- {k} ---")
        for sub, sm in v["sub_metrics"].items():
            print(f"  {sub:<8}: Acc={sm['accuracy']*100:.2f}%, BalAcc={sm['balanced_accuracy']*100:.2f}%, F1={sm['macro_f1']*100:.2f}%, CorRec={sm['correct_recall']*100:.2f}%, IncRec={sm['incorrect_recall']*100:.2f}%")

    print("\n" + "=" * 105)
    print("DISAGREEMENT & OVERRIDE ANALYSIS (On the 37 disagreement cases):")
    print("=" * 105)
    print(f"Total Disagreements: {num_disagree}")
    rule_disagree_acc = accuracy_score(labels[disagree_mask], r_preds[disagree_mask])
    rule_disagree_bal = balanced_accuracy_score(labels[disagree_mask], r_preds[disagree_mask])
    ml_disagree_acc = accuracy_score(labels[disagree_mask], ml_preds[disagree_mask])
    ml_disagree_bal = balanced_accuracy_score(labels[disagree_mask], ml_preds[disagree_mask])
    print(f"Rule Performance on Disagreements: Accuracy={rule_disagree_acc*100:.2f}%, Balanced Acc={rule_disagree_bal*100:.2f}%")
    print(f"ML   Performance on Disagreements: Accuracy={ml_disagree_acc*100:.2f}%, Balanced Acc={ml_disagree_bal*100:.2f}%")

if __name__ == "__main__":
    run_phase5_experiment()

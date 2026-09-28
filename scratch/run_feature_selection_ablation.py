"""Phase 4A: Feature-Selection Ablation for Assisted Elbow Flexion.

Strict 3-fold Leave-One-Subject-Out (LOSO) experiment:
- Fold 1: test Person 1, train Persons 2+3
- Fold 2: test Person 2, train Persons 1+3
- Fold 3: test Person 3, train Persons 1+2

For EACH fold independently:
1. Compute Random Forest feature importance using ONLY that fold's training subjects.
2. Select top 8, top 12, top 16, and full 34 features.
3. Train/evaluate identical hybrid architecture (1-layer LSTM 32 + scalar MLP 16).
4. StandardScaler, class weighting, inner validation early stopping, and threshold tuning
   derived strictly from training data.
5. Single evaluation on held-out subject.
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
# Feature Extraction
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
        rom, min_ang, max_ang, dur, peak_vel, mean_vel,
        peak_flare, mean_flare, bi_ang_asym, bi_flare_asym
    ]


def extract_phase_aware_scalars_34(raw_seq: np.ndarray, dur: float) -> np.ndarray:
    """Extract all 34 phase-aware kinematic scalars."""
    base_10 = extract_base_scalars(raw_seq, dur)

    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    idx_peak = int(np.argmin(act_ang_deg))
    idx_peak = max(5, min(idx_peak, len(act_ang_deg) - 6))

    # Timing
    flex_dur = dur * (idx_peak / 128.0)
    ext_dur = dur * ((128.0 - idx_peak) / 128.0)
    flex_ext_ratio = flex_dur / max(ext_dur, 1e-3)
    time_to_peak_pct = idx_peak / 128.0

    # Velocity
    peak_flex_vel = float(np.max(np.abs(act_vel[:idx_peak])))
    peak_ext_vel = float(np.max(np.abs(act_vel[idx_peak:])))
    mean_flex_vel = float(np.mean(np.abs(act_vel[:idx_peak])))
    mean_ext_vel = float(np.mean(np.abs(act_vel[idx_peak:])))
    ecc_conc_vel_ratio = mean_ext_vel / max(mean_flex_vel, 1e-4)

    # Acceleration & Jerk
    acc = np.gradient(act_vel)
    jerk = np.gradient(acc)
    peak_flex_acc = float(np.max(np.abs(acc[:idx_peak])))
    peak_ext_acc = float(np.max(np.abs(acc[idx_peak:])))
    peak_jerk = float(np.max(np.abs(jerk)))

    # Smoothness
    flex_diff2 = np.diff(act_ang_deg[:idx_peak], n=2)
    ext_diff2 = np.diff(act_ang_deg[idx_peak:], n=2)
    flex_smoothness = float(1.0 / (1.0 + np.mean(np.abs(flex_diff2)))) if len(flex_diff2) > 0 else 0.0
    ext_smoothness = float(1.0 / (1.0 + np.mean(np.abs(ext_diff2)))) if len(ext_diff2) > 0 else 0.0

    # Recovery & Intermediate progress angles
    rom = float(np.max(act_ang_deg) - np.min(act_ang_deg))
    min_ang = float(np.min(act_ang_deg))
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

    # Bilateral 6
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


FEATURE_NAMES_34 = [
    "rom", "min_elbow_angle", "max_elbow_angle", "duration",
    "peak_velocity", "mean_velocity", "peak_flare", "mean_flare",
    "bi_ang_asym", "bi_flare_asym",
    "flex_duration", "ext_duration", "flex_ext_ratio", "time_to_peak_pct",
    "peak_flex_velocity", "peak_ext_velocity", "mean_flex_velocity", "mean_ext_velocity",
    "ecc_conc_vel_ratio", "peak_flex_acc", "peak_ext_acc", "peak_jerk",
    "flex_smoothness", "ext_smoothness", "recovery_rate",
    "ang_at_25pct", "ang_at_50pct", "ang_at_75pct",
    "bi_ang_flex", "bi_ang_ext", "bi_vel_flex", "bi_vel_ext",
    "bi_flare_flex", "bi_flare_ext"
]


# ---------------------------------------------------------------------------
# Architecture
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
# Ablation Pipeline
# ---------------------------------------------------------------------------

def run_feature_selection_ablation():
    set_seed(RANDOM_SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    df = pd.read_csv(DATA_PATH)
    print(f"Loaded {len(df)} repetitions from {DATA_PATH.name}")

    # Extract all temporal sequences and full 34 scalars
    seq_list = []
    scalar_34_list = []

    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        seq_list.append(extract_subject_normalized_temporal(raw))
        scalar_34_list.append(extract_phase_aware_scalars_34(raw, dur))

    all_seqs = np.array(seq_list, dtype=np.float32)       # (195, 128, 10)
    all_scalars_34 = np.array(scalar_34_list, dtype=np.float32)  # (195, 34)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    feature_subsets = [8, 12, 16, 34]
    results = {}

    for k_feat in feature_subsets:
        set_seed(RANDOM_SEED)
        exp_name = f"subset_top_{k_feat}" if k_feat < 34 else "full_34"
        print(f"\n{'='*75}")
        print(f"RUNNING EXPERIMENT: {exp_name.upper()} SCALAR FEATURES")
        print(f"{'='*75}")

        all_preds = np.zeros(len(df), dtype=int)
        all_probs = np.zeros(len(df), dtype=float)
        fold_metrics = {}
        fold_selected_features = {}

        for test_sub in unique_subjects:
            test_mask = (subjects == test_sub)
            train_mask = ~test_mask

            tr_indices = np.where(train_mask)[0]
            y_train_full = labels[tr_indices]

            # 1. Feature Importance computed strictly on training subjects of this fold
            X_tr_full_scalars = all_scalars_34[tr_indices]
            rf = RandomForestClassifier(n_estimators=100, random_state=42)
            rf.fit(X_tr_full_scalars, y_train_full)
            imp = rf.feature_importances_
            sorted_feat_indices = np.argsort(imp)[::-1]

            if k_feat < 34:
                selected_idx = sorted_feat_indices[:k_feat]
            else:
                selected_idx = np.arange(34)

            selected_names = [FEATURE_NAMES_34[i] for i in selected_idx]
            fold_selected_features[test_sub] = selected_names

            # Filter scalars to selected subset
            fold_scalars = all_scalars_34[:, selected_idx]

            # 2. Inner validation split strictly from training subjects (20% stratified)
            rng = np.random.RandomState(RANDOM_SEED)
            c0_idx = tr_indices[y_train_full == 0]
            c1_idx = tr_indices[y_train_full == 1]
            rng.shuffle(c0_idx)
            rng.shuffle(c1_idx)

            val_n0 = max(1, int(len(c0_idx) * 0.2))
            val_n1 = max(1, int(len(c1_idx) * 0.2))

            val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
            actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])

            # 3. Scaling fitted strictly on actual_tr_idx
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
            scalar_scaler.fit(fold_scalars[actual_tr_idx])

            X_sc_tr = scalar_scaler.transform(fold_scalars[actual_tr_idx])
            X_sc_val = scalar_scaler.transform(fold_scalars[val_idx])
            X_sc_test = scalar_scaler.transform(fold_scalars[test_mask])

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
                temporal_dim=10,
                scalar_dim=k_feat,
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
                "optimal_threshold": float(optimal_threshold),
            }

        agg_acc = accuracy_score(labels, all_preds)
        agg_bal = balanced_accuracy_score(labels, all_preds)
        agg_f1 = f1_score(labels, all_preds, average="macro", zero_division=0)
        agg_c_rec = recall_score(labels, all_preds, pos_label=1, zero_division=0)
        agg_inc_rec = recall_score(labels, all_preds, pos_label=0, zero_division=0)
        cm = confusion_matrix(labels, all_preds).tolist()

        # Mean and std across the 3 folds
        fold_bals = [m["balanced_accuracy"] for m in fold_metrics.values()]
        fold_f1s = [m["macro_f1"] for m in fold_metrics.values()]
        fold_accs = [m["accuracy"] for m in fold_metrics.values()]

        results[exp_name] = {
            "num_features": k_feat,
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
            "selected_features": fold_selected_features,
        }

    # Save to JSON
    out_file = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "feature_selection_ablation_results.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    # Print summary
    print("\n" + "=" * 90)
    print("PHASE 4A: FEATURE SELECTION ABLATION SUMMARY (TRUE LOSO)")
    print("=" * 90)
    header = f"{'Subset':<16} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Mean±Std BalAcc'}"
    print(header)
    print("-" * 90)
    for k, v in results.items():
        agg = v["aggregate"]
        fs = v["fold_summary"]
        m_s = f"{fs['mean_balanced_accuracy']*100:.2f}% ± {fs['std_balanced_accuracy']*100:.2f}%"
        print(f"{k:<16} | {agg['accuracy']*100:6.2f}% | {agg['balanced_accuracy']*100:6.2f}% | {agg['macro_f1']*100:6.2f}% | {agg['correct_recall']*100:6.2f}% | {agg['incorrect_recall']*100:6.2f}% | {m_s}")
        for sub, sm in v["folds"].items():
            print(f"   -> {sub:<12} | {sm['accuracy']*100:6.2f}% | {sm['balanced_accuracy']*100:6.2f}% | {sm['macro_f1']*100:6.2f}% | {sm['correct_recall']*100:6.2f}% | {sm['incorrect_recall']*100:6.2f}% | thresh={sm['optimal_threshold']:.2f}")

    print("\n" + "=" * 90)
    print("SELECTED FEATURES PER FOLD:")
    print("=" * 90)
    for exp_k in ["subset_top_8", "subset_top_12", "subset_top_16"]:
        print(f"\n--- {exp_k} ---")
        for sub, flist in results[exp_k]["selected_features"].items():
            print(f"  Test Subject {sub} (features={len(flist)}):")
            print(f"    {', '.join(flist)}")


if __name__ == "__main__":
    run_feature_selection_ablation()

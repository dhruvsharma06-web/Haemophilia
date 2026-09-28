"""Phase 1 Controlled Experiments for Assisted Elbow Flexion.

Experiments:
1. Baseline:
   - Deterministic Rules
   - Baseline LSTM (8 features, standard CE)
2. Experiment A: Subject-Invariant Feature Representation Ablation
   - A1: Baseline 8 features
   - A2: Subject-normalized features only (delta, progress, norm velocity, asymmetries, relative tilt/rot, flare)
   - A3: Combined (Baseline 8 + Subject-normalized features)
3. Experiment B: LSTM Class Calibration
   - B1: Standard Cross-Entropy
   - B2: Class-weighted Cross-Entropy
   - B3: Balanced batch sampling (WeightedRandomSampler)
   - B4: Validation-derived probability threshold (calibrated strictly on inner validation split)
4. Experiment C: Summary-Feature Classifier Branch
   - Comprehensive repetition-level kinematic summary features
   - Logistic Regression
   - Random Forest
   - Ridge Classifier
5. Experiment D: Lightweight Hybrid Temporal + Summary Model
   - 1-layer small LSTM (hidden=32, dropout=0.4) + summary features -> small fully-connected head

Strict Methodological Rules:
- TRUE 3-fold Leave-One-Subject-Out (LOSO) Cross-Validation.
- Zero Person 3 tuning: Held-out subject evaluated exactly once.
- All scalers, thresholds, and class weights fitted strictly on training subjects in each fold.
- Evaluates on human-verified ground_truth_label (N=150 usable repetitions).
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
from sklearn.linear_model import LogisticRegression, RidgeClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.preprocessing import StandardScaler
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))

DATA_PATH = BASE_DIR / "data" / "clean_elbow_train.csv"
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

def extract_subject_normalized_features(raw_seq: np.ndarray) -> np.ndarray:
    """Transform (128, 8) raw sequence into subject-normalized representation.
    
    Raw sequence columns:
    0: active_elbow_angle (divided by 180)
    1: assisting_elbow_angle (divided by 180)
    2: active_elbow_velocity
    3: assisting_elbow_velocity
    4: torso_tilt
    5: torso_rotation
    6: active_elbow_flare
    7: assisting_elbow_flare
    """
    act_ang = raw_seq[:, 0]
    asst_ang = raw_seq[:, 1]
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    tilt = raw_seq[:, 4]
    rot = raw_seq[:, 5]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    # Per-repetition baseline (maximum extension angle in repetition)
    ext_base = float(np.max(act_ang))
    rom = float(np.max(act_ang) - np.min(act_ang) + 1e-4)

    # 1. Flexion delta from extension baseline (scale-invariant, >= 0)
    flexion_delta = ext_base - act_ang
    # 2. Normalized flexion progress [0.0, 1.0]
    flexion_progress = flexion_delta / rom
    # 3. ROM-normalized angular velocity (clipped to prevent outliers)
    rom_norm_vel = np.clip(act_vel / rom, -3.0, 3.0) * 0.3
    # 4. Raw active velocity
    raw_act_vel = act_vel
    # 5. Bilateral angle asymmetry (active - assisting)
    bi_ang_asym = act_ang - asst_ang
    # 6. Bilateral velocity asymmetry (active - assisting)
    bi_vel_asym = act_vel - asst_vel
    # 7. Relative torso tilt from repetition start
    rel_tilt = tilt - tilt[0]
    # 8. Relative torso rotation from repetition start
    rel_rot = rot - rot[0]
    # 9. Active elbow flare (normalized by W_ref)
    norm_flare = act_flare
    # 10. Bilateral flare asymmetry
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


def extract_combined_features(raw_seq: np.ndarray) -> np.ndarray:
    """Concatenate baseline 8 features with normalized 10 features (total 18 dimensions)."""
    norm_seq = extract_subject_normalized_features(raw_seq)
    return np.concatenate([raw_seq, norm_seq], axis=-1).astype(np.float32)


def extract_comprehensive_summary_features(row: pd.Series, sequence_dir: Path = SEQUENCE_DIR) -> Dict[str, float]:
    """Extract repetition-level summary metrics from raw sequence without test leakage."""
    raw_seq = np.load(sequence_dir / row["sequence_file"])
    act_ang_deg = raw_seq[:, 0] * 180.0
    asst_ang_deg = raw_seq[:, 1] * 180.0
    act_vel = raw_seq[:, 2]
    asst_vel = raw_seq[:, 3]
    tilt = raw_seq[:, 4]
    rot = raw_seq[:, 5]
    act_flare = raw_seq[:, 6]
    asst_flare = raw_seq[:, 7]

    min_ang = float(np.min(act_ang_deg))
    max_ang = float(np.max(act_ang_deg))
    rom = float(max_ang - min_ang)
    dur = float(row["duration_sec"])

    # Smoothness via second difference of angles
    if len(act_ang_deg) >= 3:
        smoothness = float(1.0 / (1.0 + np.mean(np.abs(np.diff(act_ang_deg, n=2)))))
    else:
        smoothness = 0.0

    return {
        "min_elbow_angle": min_ang,
        "max_elbow_angle": max_ang,
        "rom": rom,
        "duration": dur,
        "peak_velocity": float(np.max(np.abs(act_vel))),
        "mean_velocity": float(np.mean(np.abs(act_vel))),
        "mean_flare": float(np.mean(act_flare)),
        "peak_flare": float(np.max(act_flare)),
        "max_tilt": float(np.max(tilt)),
        "mean_tilt": float(np.mean(tilt)),
        "max_rotation": float(np.max(np.abs(rot))),
        "mean_rotation": float(np.mean(np.abs(rot))),
        "smoothness": smoothness,
        "mean_angle_asymmetry": float(np.mean(np.abs(act_ang_deg - asst_ang_deg))),
        "max_angle_asymmetry": float(np.max(np.abs(act_ang_deg - asst_ang_deg))),
        "mean_velocity_asymmetry": float(np.mean(np.abs(act_vel - asst_vel))),
        "label": int(row["numeric_label"]),
    }


def evaluate_biomechanical_rule_row(row: pd.Series) -> int:
    min_ang = float(row["min_elbow_angle"])
    flare = float(row["elbow_flare"])
    rom = float(row["rom"])
    if min_ang > 101.0 or flare > 0.30 or rom < 25.0:
        return 1
    return 0


# ---------------------------------------------------------------------------
# Datasets & Models
# ---------------------------------------------------------------------------

class TransformedSeqDataset(Dataset):
    def __init__(self, records: List[Dict], sequence_dir: Path, feature_mode: str = "baseline"):
        self.records = records
        self.sequence_dir = sequence_dir
        self.feature_mode = feature_mode

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx: int):
        rec = self.records[idx]
        raw_x = np.load(self.sequence_dir / rec["sequence_file"]).astype(np.float32)

        if self.feature_mode == "normalized_only":
            x = extract_subject_normalized_features(raw_x)
        elif self.feature_mode == "combined":
            x = extract_combined_features(raw_x)
        else:  # baseline
            x = raw_x

        y = int(rec["numeric_label"])
        return torch.tensor(x, dtype=torch.float32), torch.tensor(y, dtype=torch.long)


class StandardLSTM(nn.Module):
    def __init__(self, input_size: int, hidden_size: int = 64, num_layers: int = 2, dropout: float = 0.3):
        super().__init__()
        self.lstm = nn.LSTM(input_size=input_size, hidden_size=hidden_size, num_layers=num_layers, batch_first=True, dropout=dropout if num_layers > 1 else 0.0)
        self.classifier = nn.Sequential(
            nn.Linear(hidden_size, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 2),
        )

    def forward(self, x):
        out, _ = self.lstm(x)
        last_step = out[:, -1, :]
        return self.classifier(last_step)


class LightweightHybridModel(nn.Module):
    """Single small LSTM (hidden 32) + summary feature branch -> small FC head."""
    def __init__(self, temporal_input_size: int, summary_feature_dim: int, hidden_size: int = 32, dropout: float = 0.4):
        super().__init__()
        self.lstm = nn.LSTM(input_size=temporal_input_size, hidden_size=hidden_size, num_layers=1, batch_first=True)
        self.temporal_dropout = nn.Dropout(dropout)
        
        combined_dim = hidden_size + summary_feature_dim
        self.fc = nn.Sequential(
            nn.Linear(combined_dim, 24),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(24, 2),
        )

    def forward(self, x_temporal, x_summary):
        out, _ = self.lstm(x_temporal)
        last_step = self.temporal_dropout(out[:, -1, :])
        merged = torch.cat([last_step, x_summary], dim=1)
        return self.fc(merged)


class HybridDataset(Dataset):
    def __init__(self, records: List[Dict], sequence_dir: Path, summary_matrix: np.ndarray, feature_mode: str = "normalized_only"):
        self.records = records
        self.sequence_dir = sequence_dir
        self.summary_matrix = summary_matrix.astype(np.float32)
        self.feature_mode = feature_mode

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx: int):
        rec = self.records[idx]
        raw_x = np.load(self.sequence_dir / rec["sequence_file"]).astype(np.float32)
        if self.feature_mode == "normalized_only":
            x_temp = extract_subject_normalized_features(raw_x)
        elif self.feature_mode == "combined":
            x_temp = extract_combined_features(raw_x)
        else:
            x_temp = raw_x
        x_sum = self.summary_matrix[idx]
        y = int(rec["numeric_label"])
        return torch.tensor(x_temp, dtype=torch.float32), torch.tensor(x_sum, dtype=torch.float32), torch.tensor(y, dtype=torch.long)


# ---------------------------------------------------------------------------
# Training and Evaluation Harnesses
# ---------------------------------------------------------------------------

def evaluate_predictions(y_true: np.ndarray, y_pred: np.ndarray) -> Dict:
    acc = accuracy_score(y_true, y_pred) * 100.0
    bal_acc = balanced_accuracy_score(y_true, y_pred) * 100.0
    macro_f1 = f1_score(y_true, y_pred, average="macro", zero_division=0) * 100.0
    cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
    c_rec = (cm[0, 0] / (cm[0, 0] + cm[0, 1]) * 100.0) if (cm[0, 0] + cm[0, 1]) > 0 else 0.0
    i_rec = (cm[1, 1] / (cm[1, 0] + cm[1, 1]) * 100.0) if (cm[1, 0] + cm[1, 1]) > 0 else 0.0
    return {
        "acc": acc,
        "bal_acc": bal_acc,
        "macro_f1": macro_f1,
        "correct_recall": c_rec,
        "incorrect_recall": i_rec,
        "cm": cm,
    }


def train_eval_lstm_fold(
    train_records: List[Dict],
    val_records: List[Dict],
    test_records: List[Dict],
    device: torch.device,
    feature_mode: str = "baseline",
    use_class_weights: bool = True,
    use_balanced_sampler: bool = False,
    calibrate_threshold: bool = False,
    epochs: int = 40,
) -> Dict:
    input_sizes = {"baseline": 8, "normalized_only": 10, "combined": 18}
    input_dim = input_sizes[feature_mode]

    y_tr = [r["numeric_label"] for r in train_records]
    class_counts = np.bincount(y_tr, minlength=2)

    # Dataset & Loaders
    tr_ds = TransformedSeqDataset(train_records, SEQUENCE_DIR, feature_mode=feature_mode)
    vl_ds = TransformedSeqDataset(val_records, SEQUENCE_DIR, feature_mode=feature_mode)
    ts_ds = TransformedSeqDataset(test_records, SEQUENCE_DIR, feature_mode=feature_mode)

    if use_balanced_sampler:
        class_sample_weights = [1.0 / max(class_counts[label], 1) for label in y_tr]
        sampler = WeightedRandomSampler(class_sample_weights, num_samples=len(class_sample_weights), replacement=True)
        tr_loader = DataLoader(tr_ds, batch_size=8, sampler=sampler)
    else:
        tr_loader = DataLoader(tr_ds, batch_size=8, shuffle=True)

    vl_loader = DataLoader(vl_ds, batch_size=8, shuffle=False)
    ts_loader = DataLoader(ts_ds, batch_size=8, shuffle=False)

    model = StandardLSTM(input_size=input_dim, hidden_size=64, num_layers=2, dropout=0.3).to(device)

    if use_class_weights:
        weights = torch.tensor([len(y_tr) / (2.0 * max(c, 1)) for c in class_counts], dtype=torch.float32).to(device)
        criterion = nn.CrossEntropyLoss(weight=weights)
    else:
        criterion = nn.CrossEntropyLoss()

    optimizer = torch.optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-4)

    best_val_f1 = -1.0
    best_state = None
    best_val_probs = []
    best_val_targets = []

    for ep in range(1, epochs + 1):
        model.train()
        for x, y in tr_loader:
            x, y = x.to(device), y.to(device)
            optimizer.zero_grad()
            out = model(x)
            loss = criterion(out, y)
            loss.backward()
            optimizer.step()

        # Inner validation
        model.eval()
        v_probs, v_targs = [], []
        with torch.no_grad():
            for x, y in vl_loader:
                x, y = x.to(device), y.to(device)
                out = model(x)
                probs = torch.softmax(out, dim=1)[:, 1]
                v_probs.extend(probs.cpu().numpy())
                v_targs.extend(y.cpu().numpy())

        v_preds = (np.array(v_probs) >= 0.5).astype(int)
        v_f1 = f1_score(v_targs, v_preds, average="macro", zero_division=0)

        if ep >= 4 and v_f1 > best_val_f1:
            best_val_f1 = v_f1
            best_state = copy.deepcopy(model.state_dict())
            best_val_probs = v_probs
            best_val_targets = v_targs

    if best_state is not None:
        model.load_state_dict(best_state)

    # Threshold calibration strictly on inner validation set
    optimal_thresh = 0.5
    if calibrate_threshold and len(best_val_probs) > 0:
        v_p = np.array(best_val_probs)
        v_t = np.array(best_val_targets)
        best_th_f1 = -1.0
        for th in np.linspace(0.2, 0.8, 61):
            p_th = (v_p >= th).astype(int)
            score_th = f1_score(v_t, p_th, average="macro", zero_division=0)
            if score_th > best_th_f1:
                best_th_f1 = score_th
                optimal_thresh = th

    # Evaluate once on held-out subject
    model.eval()
    test_probs, test_targets = [], []
    with torch.no_grad():
        for x, y in ts_loader:
            x, y = x.to(device), y.to(device)
            out = model(x)
            probs = torch.softmax(out, dim=1)[:, 1]
            test_probs.extend(probs.cpu().numpy())
            test_targets.extend(y.cpu().numpy())

    preds = (np.array(test_probs) >= optimal_thresh).astype(int)
    targs = np.array(test_targets)

    return {
        "preds": preds.tolist(),
        "targets": targs.tolist(),
        "optimal_threshold": float(optimal_thresh),
    }


def train_eval_hybrid_fold(
    train_records: List[Dict],
    val_records: List[Dict],
    test_records: List[Dict],
    X_tr_sum: np.ndarray,
    X_vl_sum: np.ndarray,
    X_ts_sum: np.ndarray,
    device: torch.device,
    feature_mode: str = "normalized_only",
    epochs: int = 35,
) -> Dict:
    input_sizes = {"baseline": 8, "normalized_only": 10, "combined": 18}
    temp_dim = input_sizes[feature_mode]
    sum_dim = X_tr_sum.shape[1]

    y_tr = [r["numeric_label"] for r in train_records]
    class_counts = np.bincount(y_tr, minlength=2)
    weights = torch.tensor([len(y_tr) / (2.0 * max(c, 1)) for c in class_counts], dtype=torch.float32).to(device)

    tr_ds = HybridDataset(train_records, SEQUENCE_DIR, X_tr_sum, feature_mode=feature_mode)
    vl_ds = HybridDataset(val_records, SEQUENCE_DIR, X_vl_sum, feature_mode=feature_mode)
    ts_ds = HybridDataset(test_records, SEQUENCE_DIR, X_ts_sum, feature_mode=feature_mode)

    tr_loader = DataLoader(tr_ds, batch_size=8, shuffle=True)
    vl_loader = DataLoader(vl_ds, batch_size=8, shuffle=False)
    ts_loader = DataLoader(ts_ds, batch_size=8, shuffle=False)

    model = LightweightHybridModel(temporal_input_size=temp_dim, summary_feature_dim=sum_dim, hidden_size=32, dropout=0.4).to(device)
    criterion = nn.CrossEntropyLoss(weight=weights)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001, weight_decay=1e-4)

    best_val_f1 = -1.0
    best_state = None

    for ep in range(1, epochs + 1):
        model.train()
        for xt, xs, y in tr_loader:
            xt, xs, y = xt.to(device), xs.to(device), y.to(device)
            optimizer.zero_grad()
            out = model(xt, xs)
            loss = criterion(out, y)
            loss.backward()
            optimizer.step()

        # Inner validation
        model.eval()
        v_preds, v_targs = [], []
        with torch.no_grad():
            for xt, xs, y in vl_loader:
                xt, xs, y = xt.to(device), xs.to(device), y.to(device)
                out = model(xt, xs)
                preds = torch.argmax(out, dim=1)
                v_preds.extend(preds.cpu().numpy())
                v_targs.extend(y.cpu().numpy())

        v_f1 = f1_score(v_targs, v_preds, average="macro", zero_division=0)
        if ep >= 4 and v_f1 > best_val_f1:
            best_val_f1 = v_f1
            best_state = copy.deepcopy(model.state_dict())

    if best_state is not None:
        model.load_state_dict(best_state)

    # Evaluate test
    model.eval()
    test_preds, test_targs = [], []
    with torch.no_grad():
        for xt, xs, y in ts_loader:
            xt, xs, y = xt.to(device), xs.to(device), y.to(device)
            out = model(xt, xs)
            preds = torch.argmax(out, dim=1)
            test_preds.extend(preds.cpu().numpy())
            test_targs.extend(y.cpu().numpy())

    return {
        "preds": test_preds,
        "targets": test_targs,
    }


# ---------------------------------------------------------------------------
# Main Orchestration Loop
# ---------------------------------------------------------------------------

def run_all_phase1_experiments():
    set_seed(RANDOM_SEED)

    clean_df = pd.read_csv(DATA_PATH)
    if "video_id" not in clean_df.columns:
        clean_df["video_id"] = clean_df["video_name"].apply(lambda v: Path(v).stem)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("=" * 85)
    print("PHASE 1: CONTROLLED CROSS-SUBJECT LOSO EXPERIMENTS FOR ASSISTED ELBOW FLEXION")
    print(f"Device: {device} | Total repetitions: {len(clean_df)}")
    print("=" * 85)

    subjects = ["person1", "person2", "person3"]
    inner_val_videos = {
        "person3": {"20260825_135701", "20260825_135545"},      # from Person 2
        "person1": {"VID20260825125333", "VID20260825125720"},  # from Person 3
        "person2": {"VID20260825125257", "VID20260825125647"},  # from Person 3
    }

    # Tracking dictionary for aggregate predictions
    experiments = {
        "Deterministic Rules": {"preds": [], "targets": []},
        # Experiment A: Feature Ablations
        "Baseline LSTM (8 features)": {"preds": [], "targets": []},
        "Normalized-Only LSTM (10 features)": {"preds": [], "targets": []},
        "Combined LSTM (18 features)": {"preds": [], "targets": []},
        # Experiment B: Class Calibration
        "LSTM + Standard CE (unweighted)": {"preds": [], "targets": []},
        "LSTM + Balanced Batch Sampler": {"preds": [], "targets": []},
        "LSTM + Val-Calibrated Threshold": {"preds": [], "targets": []},
        "Normalized LSTM + Val-Calibrated Threshold": {"preds": [], "targets": []},
        # Experiment C: Summary Feature Models
        "Summary LR (Logistic Regression)": {"preds": [], "targets": []},
        "Summary Random Forest": {"preds": [], "targets": []},
        "Summary Ridge Classifier": {"preds": [], "targets": []},
        # Experiment D: Hybrid Temporal + Summary Model
        "Hybrid Temporal + Summary Model": {"preds": [], "targets": []},
    }

    # Extract all summary features upfront
    summary_list = [extract_comprehensive_summary_features(row) for _, row in clean_df.iterrows()]
    summary_df = pd.DataFrame(summary_list)
    sum_feature_cols = [c for c in summary_df.columns if c != "label"]

    per_fold_tracking = {name: {} for name in experiments}

    for fold_idx, held_out in enumerate(subjects, start=1):
        print(f"\n>>> Running Fold {fold_idx}/3: Held-out Subject = [{held_out}]")
        test_mask = clean_df["subject_id"] == held_out
        train_pool_mask = clean_df["subject_id"] != held_out

        test_df = clean_df[test_mask].reset_index(drop=True)
        train_pool_df = clean_df[train_pool_mask].reset_index(drop=True)

        val_vids = inner_val_videos[held_out]
        val_df = train_pool_df[train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)
        train_df = train_pool_df[~train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)

        tr_records = train_df.to_dict("records")
        vl_records = val_df.to_dict("records")
        ts_records = test_df.to_dict("records")

        y_test = test_df["numeric_label"].values

        # -------------------------------------------------------------
        # 1. Deterministic Biomechanical Rules
        # -------------------------------------------------------------
        p_rules = [evaluate_biomechanical_rule_row(row) for _, row in test_df.iterrows()]
        experiments["Deterministic Rules"]["preds"].extend(p_rules)
        experiments["Deterministic Rules"]["targets"].extend(y_test)
        per_fold_tracking["Deterministic Rules"][held_out] = evaluate_predictions(y_test, np.array(p_rules))

        # -------------------------------------------------------------
        # 2. Experiment A: Feature Ablation LSTMs (weighted CE, threshold=0.5)
        # -------------------------------------------------------------
        # A1: Baseline (8 features)
        res_a1 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="baseline", use_class_weights=True)
        experiments["Baseline LSTM (8 features)"]["preds"].extend(res_a1["preds"])
        experiments["Baseline LSTM (8 features)"]["targets"].extend(y_test)
        per_fold_tracking["Baseline LSTM (8 features)"][held_out] = evaluate_predictions(y_test, np.array(res_a1["preds"]))

        # A2: Normalized-only (10 features)
        res_a2 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="normalized_only", use_class_weights=True)
        experiments["Normalized-Only LSTM (10 features)"]["preds"].extend(res_a2["preds"])
        experiments["Normalized-Only LSTM (10 features)"]["targets"].extend(y_test)
        per_fold_tracking["Normalized-Only LSTM (10 features)"][held_out] = evaluate_predictions(y_test, np.array(res_a2["preds"]))

        # A3: Combined (18 features)
        res_a3 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="combined", use_class_weights=True)
        experiments["Combined LSTM (18 features)"]["preds"].extend(res_a3["preds"])
        experiments["Combined LSTM (18 features)"]["targets"].extend(y_test)
        per_fold_tracking["Combined LSTM (18 features)"][held_out] = evaluate_predictions(y_test, np.array(res_a3["preds"]))

        # -------------------------------------------------------------
        # 3. Experiment B: LSTM Class Calibration (on Baseline 8 features)
        # -------------------------------------------------------------
        # B1: Standard CE (unweighted)
        res_b1 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="baseline", use_class_weights=False)
        experiments["LSTM + Standard CE (unweighted)"]["preds"].extend(res_b1["preds"])
        experiments["LSTM + Standard CE (unweighted)"]["targets"].extend(y_test)
        per_fold_tracking["LSTM + Standard CE (unweighted)"][held_out] = evaluate_predictions(y_test, np.array(res_b1["preds"]))

        # B2: Balanced batch sampler
        res_b2 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="baseline", use_class_weights=False, use_balanced_sampler=True)
        experiments["LSTM + Balanced Batch Sampler"]["preds"].extend(res_b2["preds"])
        experiments["LSTM + Balanced Batch Sampler"]["targets"].extend(y_test)
        per_fold_tracking["LSTM + Balanced Batch Sampler"][held_out] = evaluate_predictions(y_test, np.array(res_b2["preds"]))

        # B3: Validation-calibrated probability threshold (baseline 8 features)
        res_b3 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="baseline", use_class_weights=True, calibrate_threshold=True)
        experiments["LSTM + Val-Calibrated Threshold"]["preds"].extend(res_b3["preds"])
        experiments["LSTM + Val-Calibrated Threshold"]["targets"].extend(y_test)
        per_fold_tracking["LSTM + Val-Calibrated Threshold"][held_out] = evaluate_predictions(y_test, np.array(res_b3["preds"]))

        # B4: Validation-calibrated probability threshold on Normalized-only features
        res_b4 = train_eval_lstm_fold(tr_records, vl_records, ts_records, device, feature_mode="normalized_only", use_class_weights=True, calibrate_threshold=True)
        experiments["Normalized LSTM + Val-Calibrated Threshold"]["preds"].extend(res_b4["preds"])
        experiments["Normalized LSTM + Val-Calibrated Threshold"]["targets"].extend(y_test)
        per_fold_tracking["Normalized LSTM + Val-Calibrated Threshold"][held_out] = evaluate_predictions(y_test, np.array(res_b4["preds"]))

        # -------------------------------------------------------------
        # 4. Experiment C: Summary Feature Models
        # -------------------------------------------------------------
        tr_sum_df = summary_df[~clean_df["video_id"].isin(val_vids) & train_pool_mask].reset_index(drop=True)
        vl_sum_df = summary_df[clean_df["video_id"].isin(val_vids) & train_pool_mask].reset_index(drop=True)
        ts_sum_df = summary_df[test_mask].reset_index(drop=True)

        X_tr = tr_sum_df[sum_feature_cols].values
        y_tr = tr_sum_df["label"].values
        X_vl = vl_sum_df[sum_feature_cols].values
        y_vl = vl_sum_df["label"].values
        X_ts = ts_sum_df[sum_feature_cols].values

        scaler = StandardScaler()
        X_tr_scaled = scaler.fit_transform(X_tr)
        X_vl_scaled = scaler.transform(X_vl)
        X_ts_scaled = scaler.transform(X_ts)

        # C1: Logistic Regression
        lr = LogisticRegression(class_weight="balanced", random_state=RANDOM_SEED, max_iter=1000)
        lr.fit(X_tr_scaled, y_tr)
        p_lr = lr.predict(X_ts_scaled)
        experiments["Summary LR (Logistic Regression)"]["preds"].extend(p_lr)
        experiments["Summary LR (Logistic Regression)"]["targets"].extend(y_test)
        per_fold_tracking["Summary LR (Logistic Regression)"][held_out] = evaluate_predictions(y_test, p_lr)

        # C2: Random Forest
        rf = RandomForestClassifier(n_estimators=50, max_depth=3, class_weight="balanced", random_state=RANDOM_SEED)
        rf.fit(X_tr, y_tr)
        p_rf = rf.predict(X_ts)
        experiments["Summary Random Forest"]["preds"].extend(p_rf)
        experiments["Summary Random Forest"]["targets"].extend(y_test)
        per_fold_tracking["Summary Random Forest"][held_out] = evaluate_predictions(y_test, p_rf)

        # C3: Ridge Classifier
        ridge = RidgeClassifier(class_weight="balanced", random_state=RANDOM_SEED)
        ridge.fit(X_tr_scaled, y_tr)
        p_ridge = ridge.predict(X_ts_scaled)
        experiments["Summary Ridge Classifier"]["preds"].extend(p_ridge)
        experiments["Summary Ridge Classifier"]["targets"].extend(y_test)
        per_fold_tracking["Summary Ridge Classifier"][held_out] = evaluate_predictions(y_test, p_ridge)

        # -------------------------------------------------------------
        # 5. Experiment D: Lightweight Hybrid Temporal + Summary Model
        # -------------------------------------------------------------
        res_d = train_eval_hybrid_fold(tr_records, vl_records, ts_records, X_tr_scaled, X_vl_scaled, X_ts_scaled, device, feature_mode="normalized_only")
        experiments["Hybrid Temporal + Summary Model"]["preds"].extend(res_d["preds"])
        experiments["Hybrid Temporal + Summary Model"]["targets"].extend(y_test)
        per_fold_tracking["Hybrid Temporal + Summary Model"][held_out] = evaluate_predictions(y_test, np.array(res_d["preds"]))

    # -------------------------------------------------------------
    # Aggregate Table Construction & Display
    # -------------------------------------------------------------
    print("\n" + "=" * 105)
    print(f"{'Experiment':<35} | {'Acc (%)':<8} | {'BalAcc (%)':<10} | {'Macro-F1':<9} | {'Corr Rec':<9} | {'Inc Rec':<9}")
    print("-" * 105)

    results_table = []
    for exp_name, data in experiments.items():
        y_true = np.array(data["targets"])
        y_pred = np.array(data["preds"])
        m = evaluate_predictions(y_true, y_pred)
        results_table.append({
            "Experiment": exp_name,
            "Accuracy": m["acc"],
            "Balanced_Accuracy": m["bal_acc"],
            "Macro_F1": m["macro_f1"],
            "Correct_Recall": m["correct_recall"],
            "Incorrect_Recall": m["incorrect_recall"],
        })
        print(f"{exp_name:<35} | {m['acc']:<8.2f} | {m['bal_acc']:<10.2f} | {m['macro_f1']:<9.2f} | {m['correct_recall']:<9.2f} | {m['incorrect_recall']:<9.2f}")

    print("=" * 105)

    # Save complete experiment results JSON
    save_path = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "phase1_experiment_results.json"
    with open(save_path, "w", encoding="utf-8") as f:
        json.dump({
            "aggregate_results": results_table,
            "per_fold_results": {k: {sub: {met: float(val) if not isinstance(val, list) and not isinstance(val, np.ndarray) else val.tolist() for met, val in mets.items()} for sub, mets in folds.items()} for k, folds in per_fold_tracking.items()},
        }, f, indent=2)

    print(f"\nComplete experiment results saved to: {save_path}")
    return results_table, per_fold_tracking


if __name__ == "__main__":
    run_all_phase1_experiments()

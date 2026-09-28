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
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.dummy import DummyClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    confusion_matrix,
)

sys.path.insert(0, r"c:\dev\Haemophilia")
from src.features.assisted_elbow_features import FEATURE_NAMES
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

class SingleLayerGRU(nn.Module):
    """Lightweight single-layer GRU for comparison against 2-layer LSTM."""
    def __init__(self, input_size=8, hidden_size=32, num_classes=2, dropout=0.3):
        super().__init__()
        self.gru = nn.GRU(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=1,
            batch_first=True,
        )
        self.dropout = nn.Dropout(dropout)
        self.fc = nn.Linear(hidden_size, num_classes)

    def forward(self, x):
        out, _ = self.gru(x)
        last_step = out[:, -1, :]
        return self.fc(self.dropout(last_step))

class SeqDataset(Dataset):
    def __init__(self, records):
        self.records = records

    def __len__(self):
        return len(self.records)

    def __getitem__(self, idx):
        rec = self.records[idx]
        seq = np.load(SEQUENCE_DIR / rec["sequence_file"]).astype(np.float32)
        y = int(rec["numeric_label"])
        return torch.tensor(seq, dtype=torch.float32), torch.tensor(y, dtype=torch.long)

def extract_summary_features(df):
    """Extract repetition-level summary features without cross-frame or cross-video leakage."""
    rows = []
    for _, row in df.iterrows():
        seq = np.load(SEQUENCE_DIR / row["sequence_file"])
        # seq shape is (128, 8):
        # 0: act_ang, 1: asst_ang, 2: act_vel, 3: asst_vel, 4: tilt, 5: rot, 6: act_flare, 7: asst_flare
        act_ang = seq[:, 0]
        act_vel = seq[:, 2]
        tilt = seq[:, 4]
        rot = seq[:, 5]
        act_flare = seq[:, 6]
        
        feats = {
            "ang_min": float(np.min(act_ang)),
            "ang_max": float(np.max(act_ang)),
            "ang_mean": float(np.mean(act_ang)),
            "ang_std": float(np.std(act_ang)),
            "ang_rom": float(np.max(act_ang) - np.min(act_ang)),
            "vel_max": float(np.max(np.abs(act_vel))),
            "vel_mean": float(np.mean(np.abs(act_vel))),
            "vel_std": float(np.std(act_vel)),
            "tilt_mean": float(np.mean(tilt)),
            "tilt_max": float(np.max(tilt)),
            "rot_mean": float(np.mean(rot)),
            "rot_std": float(np.std(rot)),
            "flare_mean": float(np.mean(act_flare)),
            "flare_max": float(np.max(act_flare)),
            "duration": float(row["duration_sec"]),
            "label": int(row["numeric_label"]),
        }
        rows.append(feats)
    return pd.DataFrame(rows)

def evaluate_preds(targets, preds):
    acc = accuracy_score(targets, preds) * 100.0
    bal_acc = balanced_accuracy_score(targets, preds) * 100.0
    macro_f1 = f1_score(targets, preds, average="macro", zero_division=0) * 100.0
    prec = precision_score(targets, preds, zero_division=0) * 100.0
    rec = recall_score(targets, preds, zero_division=0) * 100.0
    cm = confusion_matrix(targets, preds, labels=[0, 1])
    return {
        "acc": acc,
        "bal_acc": bal_acc,
        "macro_f1": macro_f1,
        "prec": prec,
        "rec": rec,
        "cm": cm.tolist()
    }

def train_eval_sequential(model, train_loader, val_loader, device, epochs=40, lr=0.001, class_weights=None):
    criterion = nn.CrossEntropyLoss(weight=class_weights)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)

    history = []
    best_f1 = -1.0
    best_loss = float("inf")
    best_state = None
    best_ep = 0

    for ep in range(1, epochs + 1):
        model.train()
        train_loss = 0.0
        train_preds, train_targets = [], []
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            optimizer.zero_grad()
            out = model(x)
            loss = criterion(out, y)
            loss.backward()
            optimizer.step()
            train_loss += loss.item() * y.size(0)
            train_preds.extend(torch.argmax(out, dim=1).cpu().numpy())
            train_targets.extend(y.cpu().numpy())

        train_loss /= len(train_loader.dataset)
        train_metrics = evaluate_preds(train_targets, train_preds)

        model.eval()
        val_loss = 0.0
        val_preds, val_targets = [], []
        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                out = model(x)
                loss = criterion(out, y)
                val_loss += loss.item() * y.size(0)
                val_preds.extend(torch.argmax(out, dim=1).cpu().numpy())
                val_targets.extend(y.cpu().numpy())

        val_loss /= len(val_loader.dataset)
        val_metrics = evaluate_preds(val_targets, val_preds)

        history.append({
            "epoch": ep,
            "train_loss": round(train_loss, 4),
            "val_loss": round(val_loss, 4),
            "train_acc": round(train_metrics["acc"], 2),
            "val_acc": round(val_metrics["acc"], 2),
            "train_f1": round(train_metrics["macro_f1"], 2),
            "val_f1": round(val_metrics["macro_f1"], 2),
        })

        if ep >= 4 and (val_metrics["macro_f1"] > best_f1 or (val_metrics["macro_f1"] == best_f1 and val_loss < best_loss)):
            best_f1 = val_metrics["macro_f1"]
            best_loss = val_loss
            best_state = copy.deepcopy(model.state_dict())
            best_ep = ep

    return best_state, best_ep, history

def run_all_evaluations():
    set_seed(42)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    manifest = pd.read_csv(MANIFEST_FILE)
    print(f"Total manifest records: {len(manifest)}")

    p1_p2 = manifest[manifest["subject_id"].isin(["person1", "person2"])].copy()
    val_videos = {"20260825_135701", "20260825_135545"}
    train_df = p1_p2[~p1_p2["video_id"].isin(val_videos)].reset_index(drop=True)
    val_df = p1_p2[p1_p2["video_id"].isin(val_videos)].reset_index(drop=True)

    print(f"\nInternal Split (Persons 1 & 2 only):")
    print(f"  Train samples: {len(train_df)} (Correct: {(train_df['label']=='correct').sum()}, Incorrect: {(train_df['label']=='incorrect').sum()})")
    print(f"  Val samples  : {len(val_df)} (Correct: {(val_df['label']=='correct').sum()}, Incorrect: {(val_df['label']=='incorrect').sum()})")

    # Tabular features
    train_tab = extract_summary_features(train_df)
    val_tab = extract_summary_features(val_df)

    y_train = train_tab["label"].values
    y_val = val_tab["label"].values

    counts = np.bincount(y_train)
    weights = torch.tensor([len(y_train) / (2.0 * c) for c in counts], dtype=torch.float32).to(device)

    # 1. Majority
    dummy = DummyClassifier(strategy="most_frequent")
    dummy.fit(train_tab.drop(columns=["label"]).values, y_train)
    res_dummy = evaluate_preds(y_val, dummy.predict(val_tab.drop(columns=["label"]).values))

    # 2. Logistic Regression (elbow angle stats)
    angle_cols = ["ang_min", "ang_max", "ang_mean", "ang_std", "ang_rom"]
    lr = LogisticRegression(class_weight="balanced", random_state=42, max_iter=500)
    lr.fit(train_tab[angle_cols].values, y_train)
    res_lr = evaluate_preds(y_val, lr.predict(val_tab[angle_cols].values))

    # 3. Random Forest (summary features)
    summary_cols = [c for c in train_tab.columns if c != "label"]
    rf = RandomForestClassifier(n_estimators=50, max_depth=4, class_weight="balanced", random_state=42)
    rf.fit(train_tab[summary_cols].values, y_train)
    res_rf = evaluate_preds(y_val, rf.predict(val_tab[summary_cols].values))

    # DataLoaders for sequential models
    train_loader = DataLoader(SeqDataset(train_df.to_dict("records")), batch_size=8, shuffle=True)
    val_loader = DataLoader(SeqDataset(val_df.to_dict("records")), batch_size=8, shuffle=False)

    # 4. 2-layer LSTM
    lstm = ExerciseLSTM(input_size=len(FEATURE_NAMES), hidden_size=64, num_layers=2, num_classes=2, dropout=0.3).to(device)
    best_lstm_state, best_lstm_ep, lstm_history = train_eval_sequential(
        lstm, train_loader, val_loader, device, epochs=40, lr=0.001, class_weights=weights
    )
    lstm.load_state_dict(best_lstm_state)
    lstm.eval()
    val_preds_lstm = []
    with torch.no_grad():
        for x, _ in val_loader:
            out = lstm(x.to(device))
            val_preds_lstm.extend(torch.argmax(out, dim=1).cpu().numpy())
    res_lstm = evaluate_preds(y_val, val_preds_lstm)

    # 5. 1-layer GRU
    gru = SingleLayerGRU(input_size=len(FEATURE_NAMES), hidden_size=32, num_classes=2, dropout=0.3).to(device)
    best_gru_state, best_gru_ep, gru_history = train_eval_sequential(
        gru, train_loader, val_loader, device, epochs=40, lr=0.001, class_weights=weights
    )
    gru.load_state_dict(best_gru_state)
    gru.eval()
    val_preds_gru = []
    with torch.no_grad():
        for x, _ in val_loader:
            out = gru(x.to(device))
            val_preds_gru.extend(torch.argmax(out, dim=1).cpu().numpy())
    res_gru = evaluate_preds(y_val, val_preds_gru)

    print("\n" + "=" * 90)
    print("STEP 6: INTERNAL BASELINE MODEL COMPARISON (POST-PREPROCESSING FIX)")
    print("=" * 90)
    models_comp = [
        {"Model": "Majority Baseline", **res_dummy},
        {"Model": "Angle-Stats + Logistic Regression", **res_lr},
        {"Model": "Random Forest (Repetition Summary)", **res_rf},
        {"Model": f"Current LSTM (8-feat, 2-layer) [Ep {best_lstm_ep}]", **res_lstm},
        {"Model": f"Lightweight GRU (8-feat, 1-layer) [Ep {best_gru_ep}]", **res_gru},
    ]
    df_comp = pd.DataFrame([
        {
            "Model": m["Model"],
            "Accuracy": f"{m['acc']:.2f}%",
            "Balanced Acc": f"{m['bal_acc']:.2f}%",
            "Macro-F1": f"{m['macro_f1']:.2f}%",
            "Precision": f"{m['prec']:.2f}%",
            "Recall": f"{m['rec']:.2f}%",
            "Confusion Matrix [TN,FP; FN,TP]": str(m["cm"]),
        }
        for m in models_comp
    ])
    print(df_comp.to_string(index=False))

    print("\n" + "=" * 90)
    print("STEP 7: LSTM vs GRU LEARNING CURVES & OVERFITTING INSPECTION")
    print("=" * 90)
    print("\nEpoch | LSTM Train Loss | LSTM Val Loss | LSTM Train F1 | LSTM Val F1 | GRU Train Loss | GRU Val Loss | GRU Train F1 | GRU Val F1")
    print("-" * 115)
    for l_h, g_h in zip(lstm_history, gru_history):
        ep = l_h["epoch"]
        if ep % 5 == 0 or ep in [1, 2, best_lstm_ep, best_gru_ep, 40]:
            marker_l = " *" if ep == best_lstm_ep else ""
            marker_g = " #" if ep == best_gru_ep else ""
            print(
                f"{ep:5d} | {l_h['train_loss']:15.4f} | {l_h['val_loss']:13.4f} | {l_h['train_f1']:11.1f}% | {l_h['val_f1']:9.1f}%{marker_l:<2} | "
                f"{g_h['train_loss']:14.4f} | {g_h['val_loss']:12.4f} | {g_h['train_f1']:10.1f}% | {g_h['val_f1']:8.1f}%{marker_g:<2}"
            )

    # Step 8: True LOSO-CV for Random Forest vs LSTM vs GRU
    print("\n" + "=" * 90)
    print("STEP 8: TRUE LEAVE-ONE-SUBJECT-OUT CROSS-VALIDATION (POST-PREPROCESSING FIX)")
    print("=" * 90)

    subjects = ["person1", "person2", "person3"]
    inner_val_videos = {
        "person3": {"20260825_135701", "20260825_135545"},
        "person1": {"VID20260825125333", "VID20260825125720"},
        "person2": {"VID20260825125257", "VID20260825125647"},
    }

    loso_results = {"RF": {"preds": [], "targets": []}, "LSTM": {"preds": [], "targets": []}, "GRU": {"preds": [], "targets": []}}

    for held_out in subjects:
        test_df = manifest[manifest["subject_id"] == held_out].reset_index(drop=True)
        train_pool_df = manifest[manifest["subject_id"] != held_out].reset_index(drop=True)

        val_vids = inner_val_videos[held_out]
        val_df = train_pool_df[train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)
        train_df = train_pool_df[~train_pool_df["video_id"].isin(val_vids)].reset_index(drop=True)

        # Tabular data for RF
        tr_tab = extract_summary_features(train_df)
        vl_tab = extract_summary_features(val_df)
        ts_tab = extract_summary_features(test_df)

        y_tr = tr_tab["label"].values
        y_vl = vl_tab["label"].values
        y_ts = ts_tab["label"].values

        rf_fold = RandomForestClassifier(n_estimators=50, max_depth=4, class_weight="balanced", random_state=42)
        rf_fold.fit(tr_tab[summary_cols].values, y_tr)
        preds_rf = rf_fold.predict(ts_tab[summary_cols].values)

        loso_results["RF"]["preds"].extend(preds_rf)
        loso_results["RF"]["targets"].extend(y_ts)

        # PyTorch loaders
        tr_loader = DataLoader(SeqDataset(train_df.to_dict("records")), batch_size=8, shuffle=True)
        vl_loader = DataLoader(SeqDataset(val_df.to_dict("records")), batch_size=8, shuffle=False)
        ts_loader = DataLoader(SeqDataset(test_df.to_dict("records")), batch_size=8, shuffle=False)

        c_counts = np.bincount(y_tr)
        c_weights = torch.tensor([len(y_tr) / (2.0 * c) for c in c_counts], dtype=torch.float32).to(device)

        # LSTM fold
        m_lstm = ExerciseLSTM(input_size=len(FEATURE_NAMES), hidden_size=64, num_layers=2, num_classes=2, dropout=0.3).to(device)
        best_st_lstm, ep_lstm, _ = train_eval_sequential(m_lstm, tr_loader, vl_loader, device, epochs=40, lr=0.001, class_weights=c_weights)
        m_lstm.load_state_dict(best_st_lstm)
        m_lstm.eval()
        preds_lstm = []
        with torch.no_grad():
            for x, _ in ts_loader:
                preds_lstm.extend(torch.argmax(m_lstm(x.to(device)), dim=1).cpu().numpy())
        loso_results["LSTM"]["preds"].extend(preds_lstm)
        loso_results["LSTM"]["targets"].extend(y_ts)

        # GRU fold
        m_gru = SingleLayerGRU(input_size=len(FEATURE_NAMES), hidden_size=32, num_classes=2, dropout=0.3).to(device)
        best_st_gru, ep_gru, _ = train_eval_sequential(m_gru, tr_loader, vl_loader, device, epochs=40, lr=0.001, class_weights=c_weights)
        m_gru.load_state_dict(best_st_gru)
        m_gru.eval()
        preds_gru = []
        with torch.no_grad():
            for x, _ in ts_loader:
                preds_gru.extend(torch.argmax(m_gru(x.to(device)), dim=1).cpu().numpy())
        loso_results["GRU"]["preds"].extend(preds_gru)
        loso_results["GRU"]["targets"].extend(y_ts)

        print(f"\nFold Held-Out [{held_out}] (N={len(y_ts)}):")
        print(f"  Random Forest : Acc={accuracy_score(y_ts, preds_rf)*100:.2f}%, BalAcc={balanced_accuracy_score(y_ts, preds_rf)*100:.2f}%, F1={f1_score(y_ts, preds_rf, average='macro')*100:.2f}%, CM={confusion_matrix(y_ts, preds_rf).tolist()}")
        print(f"  Current LSTM  : Acc={accuracy_score(y_ts, preds_lstm)*100:.2f}%, BalAcc={balanced_accuracy_score(y_ts, preds_lstm)*100:.2f}%, F1={f1_score(y_ts, preds_lstm, average='macro')*100:.2f}%, CM={confusion_matrix(y_ts, preds_lstm).tolist()}")
        print(f"  Lightweight GRU: Acc={accuracy_score(y_ts, preds_gru)*100:.2f}%, BalAcc={balanced_accuracy_score(y_ts, preds_gru)*100:.2f}%, F1={f1_score(y_ts, preds_gru, average='macro')*100:.2f}%, CM={confusion_matrix(y_ts, preds_gru).tolist()}")

    print("\n" + "=" * 90)
    print("AGGREGATE LOSO-CV MODEL COMPARISON")
    print("=" * 90)
    for model_name in ["RF", "LSTM", "GRU"]:
        targs = loso_results[model_name]["targets"]
        preds = loso_results[model_name]["preds"]
        acc = accuracy_score(targs, preds) * 100.0
        bal = balanced_accuracy_score(targs, preds) * 100.0
        f1 = f1_score(targs, preds, average="macro") * 100.0
        cm = confusion_matrix(targs, preds, labels=[0, 1])
        print(f"Model [{model_name:<4}] -> Aggregate Acc: {acc:.2f}%, Balanced Acc: {bal:.2f}%, Macro-F1: {f1:.2f}%, Confusion Matrix:\n{cm}")

if __name__ == "__main__":
    run_all_evaluations()


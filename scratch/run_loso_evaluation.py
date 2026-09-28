"""Comprehensive LOSO-CV benchmark comparing:
1. Deterministic Rule-Based Baseline
2. Logistic Regression
3. Random Forest
4. Current LSTM (8-channel sequence)
"""

import os
import random
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    precision_score,
    recall_score,
    confusion_matrix,
)

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))

# Seed everything for strict reproducibility
def seed_all(seed=42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)

seed_all(42)

# Load dataset audit
audit_file = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "repetition_ground_truth_audit.csv"
seq_dir = BASE_DIR / "processed_data" / "assisted_elbow_flexion" / "sequences"
df = pd.read_csv(audit_file)

# Prepare summary features for tabular models
feature_cols = [
    'rom', 'min_elbow_angle', 'max_elbow_angle', 'duration',
    'peak_angular_velocity', 'smoothness', 'elbow_flare',
    'mean_elbow_flare', 'torso_tilt', 'mean_torso_tilt',
    'torso_rotation', 'mean_torso_rotation'
]

# Binary target: 0 = correct, 1 = incorrect
df['target'] = (df['folder_label'] == 'incorrect').astype(int)

# LSTM Architecture (2 layers, 64 hidden, exactly as existing pipeline)
class AssistedElbowLSTM(nn.Module):
    def __init__(self, input_size=8, hidden_size=64, num_layers=2, dropout=0.3):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=num_layers,
            batch_first=True,
            dropout=dropout if num_layers > 1 else 0.0,
        )
        self.classifier = nn.Sequential(
            nn.Linear(hidden_size, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 2),
        )

    def forward(self, x):
        out, _ = self.lstm(x)
        last_step = out[:, -1, :]
        logits = self.classifier(last_step)
        return logits

def train_lstm(train_seqs, train_labels, val_seqs, val_labels, epochs=50, lr=1e-3):
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    model = AssistedElbowLSTM(input_size=8, hidden_size=64, num_layers=2, dropout=0.3).to(device)
    
    # Calculate class weights
    n_c0 = np.sum(train_labels == 0)
    n_c1 = np.sum(train_labels == 1)
    weights = torch.tensor([1.0, float(n_c0) / max(float(n_c1), 1.0)], device=device)
    criterion = nn.CrossEntropyLoss(weight=weights)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)

    X_train_t = torch.tensor(train_seqs, dtype=torch.float32).to(device)
    y_train_t = torch.tensor(train_labels, dtype=torch.long).to(device)
    X_val_t = torch.tensor(val_seqs, dtype=torch.float32).to(device)
    y_val_t = torch.tensor(val_labels, dtype=torch.long).to(device)

    best_val_f1 = -1.0
    best_state = None

    for epoch in range(1, epochs + 1):
        model.train()
        optimizer.zero_grad()
        out = model(X_train_t)
        loss = criterion(out, y_train_t)
        loss.backward()
        optimizer.step()

        model.eval()
        with torch.no_grad():
            val_out = model(X_val_t)
            preds = torch.argmax(val_out, dim=1).cpu().numpy()
            val_f1 = f1_score(val_labels, preds, average='macro', zero_division=0)
            if val_f1 > best_val_f1:
                best_val_f1 = val_f1
                best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}

    if best_state is not None:
        model.load_state_dict({k: v.to(device) for k, v in best_state.items()})
    return model, device

# Rule-Based Deterministic Classifier
class DeterministicRuleClassifier:
    """Selects simple, interpretable biomechanical rules using ONLY training subjects."""
    def __init__(self):
        self.tree = DecisionTreeClassifier(max_depth=2, min_samples_leaf=5, random_state=42)
        self.rules_text = ""

    def fit(self, X_df, y):
        # We fit a depth-2 decision tree on the primary biomechanical features
        # to extract the optimal conjunction of 2 rules
        feats = ['rom', 'min_elbow_angle', 'elbow_flare', 'torso_rotation']
        self.tree.fit(X_df[feats], y)
        self.rules_text = export_text(self.tree, feature_names=feats)

    def predict(self, X_df):
        feats = ['rom', 'min_elbow_angle', 'elbow_flare', 'torso_rotation']
        return self.tree.predict(X_df[feats])

# Execute LOSO Cross-Validation
subjects = ['person1', 'person2', 'person3']
results = {
    'Rule-Based Baseline': {'preds': [], 'true': [], 'per_fold': {}},
    'Logistic Regression': {'preds': [], 'true': [], 'per_fold': {}},
    'Random Forest': {'preds': [], 'true': [], 'per_fold': {}},
    'LSTM': {'preds': [], 'true': [], 'per_fold': {}},
}

rule_summaries = {}

for held_out in subjects:
    train_mask = df['subject'] != held_out
    test_mask = df['subject'] == held_out

    train_df = df[train_mask].copy()
    test_df = df[test_mask].copy()

    X_train_tab = train_df[feature_cols]
    y_train = train_df['target'].values
    X_test_tab = test_df[feature_cols]
    y_test = test_df['target'].values

    # Internal validation split within training subjects for model selection (80/20 stratified)
    # Stratified split using only training subjects
    from sklearn.model_selection import train_test_split
    idx_tr, idx_val = train_test_split(
        np.arange(len(train_df)),
        test_size=0.25,
        random_state=42,
        stratify=y_train,
    )

    # 1. Deterministic Rule-Based Baseline
    rule_clf = DeterministicRuleClassifier()
    rule_clf.fit(X_train_tab, y_train)
    rule_preds = rule_clf.predict(X_test_tab)
    rule_summaries[held_out] = rule_clf.rules_text

    # 2. Logistic Regression
    scaler = StandardScaler()
    X_tr_sc = scaler.fit_transform(X_train_tab)
    X_te_sc = scaler.transform(X_test_tab)
    lr = LogisticRegression(class_weight='balanced', max_iter=1000, random_state=42)
    lr.fit(X_tr_sc, y_train)
    lr_preds = lr.predict(X_te_sc)

    # 3. Random Forest
    rf = RandomForestClassifier(n_estimators=100, max_depth=4, class_weight='balanced', random_state=42)
    rf.fit(X_train_tab, y_train)
    rf_preds = rf.predict(X_test_tab)

    # 4. LSTM
    # Load 3D sequences
    def load_seqs(sub_df):
        arrs = []
        for fn in sub_df['sequence_file']:
            arrs.append(np.load(seq_dir / fn))
        return np.array(arrs, dtype=np.float32)

    train_seqs_all = load_seqs(train_df)
    test_seqs = load_seqs(test_df)

    X_tr_seq, y_tr_seq = train_seqs_all[idx_tr], y_train[idx_tr]
    X_val_seq, y_val_seq = train_seqs_all[idx_val], y_train[idx_val]

    lstm_model, dev = train_lstm(X_tr_seq, y_tr_seq, X_val_seq, y_val_seq, epochs=50)
    lstm_model.eval()
    with torch.no_grad():
        t_seq = torch.tensor(test_seqs, dtype=torch.float32).to(dev)
        logits = lstm_model(t_seq)
        lstm_preds = torch.argmax(logits, dim=1).cpu().numpy()

    # Collect predictions
    preds_dict = {
        'Rule-Based Baseline': rule_preds,
        'Logistic Regression': lr_preds,
        'Random Forest': rf_preds,
        'LSTM': lstm_preds,
    }

    for m_name, p in preds_dict.items():
        results[m_name]['preds'].extend(p)
        results[m_name]['true'].extend(y_test)
        results[m_name]['per_fold'][held_out] = {
            'y_true': y_test,
            'y_pred': p,
        }

print('=== LOSO EVALUATION COMPLETE ===')

# Generate detailed analysis and tables
def compute_metrics(y_true, y_pred):
    cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
    tn, fp, fn, tp = cm.ravel()
    rec_c0 = tn / (tn + fp) if (tn + fp) > 0 else 0.0 # Correct recall
    rec_c1 = tp / (tp + fn) if (tp + fn) > 0 else 0.0 # Incorrect recall
    pred_c0_pct = (len(y_pred) - np.sum(y_pred)) / len(y_pred) * 100.0
    pred_c1_pct = np.sum(y_pred) / len(y_pred) * 100.0
    acc = accuracy_score(y_true, y_pred) * 100.0
    bal_acc = balanced_accuracy_score(y_true, y_pred) * 100.0
    macro_f1 = f1_score(y_true, y_pred, average='macro', zero_division=0) * 100.0
    prec_c1 = precision_score(y_true, y_pred, pos_label=1, zero_division=0) * 100.0
    
    return {
        'accuracy': acc,
        'balanced_accuracy': bal_acc,
        'macro_f1': macro_f1,
        'correct_recall': rec_c0 * 100.0,
        'incorrect_recall': rec_c1 * 100.0,
        'cm': cm.tolist(),
        'pred_c0_pct': pred_c0_pct,
        'pred_c1_pct': pred_c1_pct,
    }

print('\n--- PER-FOLD RESULTS ---')
for m_name, data in results.items():
    print(f'\nModel: {m_name}')
    for sub in subjects:
        fold_data = data['per_fold'][sub]
        m = compute_metrics(fold_data['y_true'], fold_data['y_pred'])
        print(f"  Fold [{sub}] (N={len(fold_data['y_true'])}): Acc={m['accuracy']:.2f}%, BalAcc={m['balanced_accuracy']:.2f}%, F1={m['macro_f1']:.2f}%, CorrRec={m['correct_recall']:.1f}%, IncRec={m['incorrect_recall']:.1f}%, CM={m['cm']}, PredDist=[Corr: {m['pred_c0_pct']:.1f}%, Inc: {m['pred_c1_pct']:.1f}%]")

print('\n--- AGGREGATE LOSO-CV RESULTS ---')
agg_rows = []
for m_name, data in results.items():
    m = compute_metrics(np.array(data['true']), np.array(data['preds']))
    agg_rows.append({
        'Model': m_name,
        'Accuracy': f"{m['accuracy']:.2f}%",
        'Balanced Accuracy': f"{m['balanced_accuracy']:.2f}%",
        'Macro-F1': f"{m['macro_f1']:.2f}%",
        'Correct Recall': f"{m['correct_recall']:.2f}%",
        'Incorrect Recall': f"{m['incorrect_recall']:.2f}%",
        'Pred Correct %': f"{m['pred_c0_pct']:.1f}%",
        'Pred Incorrect %': f"{m['pred_c1_pct']:.1f}%",
        'Confusion Matrix': str(m['cm']),
    })

print(pd.DataFrame(agg_rows).to_string(index=False))

print('\n--- DERIVED DETERMINISTIC RULES PER FOLD ---')
for sub, r_text in rule_summaries.items():
    print(f'Training subjects without {sub}:\n{r_text}')

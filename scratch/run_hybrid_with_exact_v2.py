import sys
import copy
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from pathlib import Path
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix
from sklearn.preprocessing import StandardScaler
from torch.utils.data import DataLoader

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))
sys.path.append(str(BASE_DIR / "scratch"))

from run_phase_aware_ablation import (
    DATA_PATH, SEQUENCE_DIR,
    extract_subject_normalized_temporal,
    extract_phase_aware_scalars,
    HybridTemporalScalarModel,
    GenericDataset,
    RANDOM_SEED, set_seed
)

def compute_rule_metrics(row: pd.Series):
    min_a = float(row["min_elbow_angle"])
    flare = float(row["elbow_flare"])
    rom = float(row["rom"])
    tilt = float(row["torso_tilt"])

    m_ang = (101.0 - min_a) / 10.0
    m_flare = (0.30 - flare) / 0.10
    m_rom = (rom - 25.0) / 10.0
    m_tilt = (5.0 - tilt) / 2.0

    margin = min(m_ang, m_flare, m_rom, m_tilt)
    pred = 1 if margin >= 0 else 0
    rule_score = float(1.0 / (1.0 + np.exp(-2.0 * margin)))
    return pred, margin, rule_score

def run_authoritative_hybrid():
    set_seed(RANDOM_SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    df = pd.read_csv(DATA_PATH)
    labels = (df["ground_truth_label"] == "Correct").astype(int).values
    subjects = df["subject_id"].values
    unique_subjects = sorted(list(set(subjects)))

    # Compute rule metrics
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

    # Extract sequences and scalars
    seq_list = []
    scalar_list = []
    for _, r in df.iterrows():
        raw = np.load(SEQUENCE_DIR / r["sequence_file"])
        dur = float(r["duration_sec"])
        seq_list.append(extract_subject_normalized_temporal(raw))
        scalar_list.append(extract_phase_aware_scalars(raw, dur, include_bilateral=True))

    all_seqs = np.array(seq_list, dtype=np.float32)
    all_scalars = np.array(scalar_list, dtype=np.float32)

    preds = {
        "A_rule_only": np.copy(rule_preds),
        "B_ml_v2": np.zeros(len(df), dtype=int),
        "C_simple_logical_hybrid": np.zeros(len(df), dtype=int),
        "D_prob_blending": np.zeros(len(df), dtype=int),
        "E_confidence_gating": np.zeros(len(df), dtype=int),
        "F_error_correction": np.zeros(len(df), dtype=int),
    }

    # CRITICAL: set_seed(RANDOM_SEED) called ONCE before subject loop (exactly like evaluate_loso_experiment)
    set_seed(RANDOM_SEED)

    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        train_mask = ~test_mask
        test_idx = np.where(test_mask)[0]

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

        counts = np.bincount(y_tr, minlength=2)
        w = len(y_tr) / (2.0 * np.maximum(counts, 1))
        criterion = nn.CrossEntropyLoss(weight=torch.tensor(w, dtype=torch.float32).to(device))

        model = HybridTemporalScalarModel(temporal_dim=10, scalar_dim=34, lstm_hidden=32, mlp_hidden=16, dropout=0.4).to(device)
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

        # Validation probabilities
        model.eval()
        val_ml_probs = []
        with torch.no_grad():
            for b_seq, b_sc, _ in val_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                val_ml_probs.extend(probs)
        val_ml_probs = np.array(val_ml_probs)

        # Test probabilities
        test_ml_probs = []
        with torch.no_grad():
            for b_seq, b_sc, _ in test_loader:
                b_seq, b_sc = b_seq.to(device), b_sc.to(device)
                logits = model(b_seq, b_sc)
                probs = torch.softmax(logits, dim=1)[:, 1].cpu().numpy()
                test_ml_probs.extend(probs)
        test_ml_probs = np.array(test_ml_probs)

        # Validation rule metrics
        val_r_preds = rule_preds[val_idx]
        val_r_margins = rule_margins[val_idx]
        val_r_scores = rule_scores[val_idx]

        test_r_preds = rule_preds[test_idx]
        test_r_margins = rule_margins[test_idx]
        test_r_scores = rule_scores[test_idx]

        # Condition B: ML-only (v2 threshold tuning)
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

        # Condition C: Simple Logical Hybrid
        best_c_f1 = -1.0
        opt_c_theta = 0.0
        for theta in np.linspace(0.0, 1.5, 76):
            is_ambig = (np.abs(val_r_margins) <= theta)
            val_c_pred = np.where(is_ambig, (val_ml_probs >= opt_b_thresh).astype(int), val_r_preds)
            c_f1 = f1_score(y_val, val_c_pred, average="macro", zero_division=0)
            if c_f1 > best_c_f1:
                best_c_f1 = c_f1
                opt_c_theta = theta

        test_is_ambig = (np.abs(test_r_margins) <= opt_c_theta)
        preds["C_simple_logical_hybrid"][test_idx] = np.where(test_is_ambig, test_b_preds, test_r_preds)

        # Condition D: Probability Blending
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
        preds["D_prob_blending"][test_idx] = (blend_test >= opt_d_tau).astype(int)

        # Condition E: Rule-Confidence Gating
        preds["E_confidence_gating"][test_idx] = preds["C_simple_logical_hybrid"][test_idx]

        # Condition F: ML Error Correction
        best_f_f1 = -1.0
        opt_f_fp = 0.0
        opt_f_fn = 1.0
        for tau_fp in np.linspace(0.0, 0.45, 19):
            for tau_fn in np.linspace(0.55, 1.0, 19):
                val_f_pred = np.copy(val_r_preds)
                val_f_pred[(val_r_preds == 1) & (val_ml_probs <= tau_fp)] = 0
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

    # Summary
    print("\n" + "=" * 105)
    print("AUTHORITATIVE HYBRID EVALUATION (WITH EXACT V2)")
    print("=" * 105)
    header = f"{'Condition':<26} | {'Acc':<7} | {'BalAcc':<7} | {'MacroF1':<7} | {'CorRec':<7} | {'IncRec':<7} | {'Fold BalAcc Mean±Std':<22} | {'Overrides (Succ/Harm)'}"
    print(header)
    print("-" * 125)

    r_preds = preds["A_rule_only"]
    ml_preds = preds["B_ml_v2"]
    disagree_mask = (r_preds != ml_preds)
    num_disagree = int(np.sum(disagree_mask))

    for cond_k, cond_p in preds.items():
        acc = accuracy_score(labels, cond_p)
        bal = balanced_accuracy_score(labels, cond_p)
        f1 = f1_score(labels, cond_p, average="macro", zero_division=0)
        c_rec = recall_score(labels, cond_p, pos_label=1, zero_division=0)
        inc_rec = recall_score(labels, cond_p, pos_label=0, zero_division=0)

        sub_bals = []
        for sub in unique_subjects:
            sub_m = (subjects == sub)
            sub_bals.append(balanced_accuracy_score(labels[sub_m], cond_p[sub_m]))

        m_s = f"{np.mean(sub_bals)*100:.2f}% ± {np.std(sub_bals)*100:.2f}%"

        override_mask = (cond_p != r_preds)
        num_ov = int(np.sum(override_mask))
        succ_ov = int(np.sum(override_mask & (cond_p == labels)))
        harm_ov = int(np.sum(override_mask & (cond_p != labels)))
        ov_str = f"{num_ov} ({succ_ov}/{harm_ov})"

        print(f"{cond_k:<26} | {acc*100:6.2f}% | {bal*100:6.2f}% | {f1*100:6.2f}% | {c_rec*100:6.2f}% | {inc_rec*100:6.2f}% | {m_s:<22} | {ov_str}")

    print("\nPER-SUBJECT FOR B_ml_v2:")
    for sub in unique_subjects:
        m = (subjects == sub)
        print(f"  {sub}: Acc={accuracy_score(labels[m], ml_preds[m])*100:.2f}%, BalAcc={balanced_accuracy_score(labels[m], ml_preds[m])*100:.2f}%, F1={f1_score(labels[m], ml_preds[m], average='macro')*100:.2f}%")

    print(f"\nDisagreement Cases: {num_disagree}")
    print(f"Rule on disagreements: Acc={accuracy_score(labels[disagree_mask], r_preds[disagree_mask])*100:.2f}%, BalAcc={balanced_accuracy_score(labels[disagree_mask], r_preds[disagree_mask])*100:.2f}%")
    print(f"ML   on disagreements: Acc={accuracy_score(labels[disagree_mask], ml_preds[disagree_mask])*100:.2f}%, BalAcc={balanced_accuracy_score(labels[disagree_mask], ml_preds[disagree_mask])*100:.2f}%")

if __name__ == "__main__":
    run_authoritative_hybrid()

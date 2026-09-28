import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix
import itertools

df = pd.read_csv("data/clean_elbow_train_expanded.csv")
labels = (df["ground_truth_label"] == "Correct").astype(int).values
subjects = df["subject_id"].values
unique_subjects = sorted(list(set(subjects)))
RANDOM_SEED = 42

grid_min_angle = np.array([97, 98, 99, 100, 101, 102, 103, 104], dtype=np.float32)
grid_flare = np.array([0.26, 0.27, 0.28, 0.29, 0.30, 0.31, 0.32, 0.33, 0.34], dtype=np.float32)
grid_rom = np.array([20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 35.0], dtype=np.float32)
grid_tilt = np.array([4.0, 5.0, 6.0, 7.0], dtype=np.float32)

all_combos = list(itertools.product(grid_min_angle, grid_flare, grid_rom, grid_tilt))
combos_arr = np.array(all_combos, dtype=np.float32) # (2016, 4)

min_a = df["min_elbow_angle"].values.astype(np.float32)
flare = df["elbow_flare"].values.astype(np.float32)
rom = df["rom"].values.astype(np.float32)
tilt = df["torso_tilt"].values.astype(np.float32)

BASE_THRESH = np.array([101.0, 0.30, 25.0, 5.0], dtype=np.float32)

def evaluate_predictions_vectorized(combos, indices, y_true):
    sub_min_a = min_a[indices]
    sub_flare = flare[indices]
    sub_rom = rom[indices]
    sub_tilt = tilt[indices]
    y = y_true[indices]
    
    cond1 = sub_min_a[None, :] <= combos[:, 0:1]
    cond2 = sub_flare[None, :] <= combos[:, 1:2]
    cond3 = sub_rom[None, :] >= combos[:, 2:3]
    cond4 = sub_tilt[None, :] <= combos[:, 3:4]
    
    preds = cond1 & cond2 & cond3 & cond4 # (K, N) bool
    
    y_pos = (y == 1)[None, :]
    y_neg = (y == 0)[None, :]
    
    tp = np.sum(preds & y_pos, axis=1)
    fn = np.sum((~preds) & y_pos, axis=1)
    tn = np.sum((~preds) & y_neg, axis=1)
    fp = np.sum(preds & y_neg, axis=1)
    
    acc = (tp + tn) / len(y)
    
    rec_pos = np.where(tp + fn > 0, tp / np.maximum(tp + fn, 1), 0.0)
    rec_neg = np.where(tn + fp > 0, tn / np.maximum(tn + fp, 1), 0.0)
    bal_acc = 0.5 * (rec_pos + rec_neg)
    
    prec_pos = np.where(tp + fp > 0, tp / np.maximum(tp + fp, 1), 0.0)
    prec_neg = np.where(tn + fn > 0, tn / np.maximum(tn + fn, 1), 0.0)
    
    f1_pos = np.where(prec_pos + rec_pos > 0, 2 * prec_pos * rec_pos / np.maximum(prec_pos + rec_pos, 1e-9), 0.0)
    f1_neg = np.where(prec_neg + rec_neg > 0, 2 * prec_neg * rec_neg / np.maximum(prec_neg + rec_neg, 1e-9), 0.0)
    macro_f1 = 0.5 * (f1_pos + f1_neg)
    
    return bal_acc, macro_f1, acc, rec_pos, rec_neg, preds

# Let's test multiple tie-breaking methods:
# Method 1: Nearest to baseline (minimum Euclidean distance in normalized feature space)
# Method 2: Best on actual_tr, then nearest to baseline
# Method 3: Best on full training fold (tr_indices = actual_tr + val)
# Method 4: Inner 5-fold CV on tr_indices

scale = np.array([10.0, 0.1, 10.0, 2.0], dtype=np.float32)
dist_to_base = np.sum(((combos_arr - BASE_THRESH) / scale)**2, axis=1)

print("\n--- COMPARISON OF TIE BREAKING & SELECTION METHODS ---")
for method in ["val_nearest_base", "val_then_tr_then_nearest", "full_training_fold"]:
    preds_b = np.zeros(len(df), dtype=int)
    preds_f = np.zeros(len(df), dtype=int)
    chosen_b_list = []
    chosen_f_list = []
    
    for test_sub in unique_subjects:
        test_mask = (subjects == test_sub)
        tr_indices = np.where(~test_mask)[0]
        test_idx = np.where(test_mask)[0]
        y_tr = labels[tr_indices]
        
        rng = np.random.RandomState(RANDOM_SEED)
        c0_idx = tr_indices[y_tr == 0]
        c1_idx = tr_indices[y_tr == 1]
        rng.shuffle(c0_idx)
        rng.shuffle(c1_idx)
        
        val_n0 = max(1, int(len(c0_idx) * 0.2))
        val_n1 = max(1, int(len(c1_idx) * 0.2))
        val_idx = np.concatenate([c0_idx[:val_n0], c1_idx[:val_n1]])
        actual_tr_idx = np.concatenate([c0_idx[val_n0:], c1_idx[val_n1:]])
        
        val_bal, val_f1, _, _, _, _ = evaluate_predictions_vectorized(combos_arr, val_idx, labels)
        tr_bal, tr_f1, _, _, _, _ = evaluate_predictions_vectorized(combos_arr, actual_tr_idx, labels)
        full_bal, full_f1, _, _, _, _ = evaluate_predictions_vectorized(combos_arr, tr_indices, labels)
        
        if method == "val_nearest_base":
            max_bal = np.max(val_bal)
            cands_b = np.where(np.isclose(val_bal, max_bal))[0]
            # sort by dist to base
            best_b = sorted(cands_b, key=lambda i: dist_to_base[i])[0]
            
            max_f = np.max(val_f1)
            cands_f = np.where(np.isclose(val_f1, max_f))[0]
            best_f = sorted(cands_f, key=lambda i: dist_to_base[i])[0]
            
        elif method == "val_then_tr_then_nearest":
            max_bal = np.max(val_bal)
            cands_b = np.where(np.isclose(val_bal, max_bal))[0]
            best_b = sorted(cands_b, key=lambda i: (-val_f1[i], -tr_bal[i], dist_to_base[i]))[0]
            
            max_f = np.max(val_f1)
            cands_f = np.where(np.isclose(val_f1, max_f))[0]
            best_f = sorted(cands_f, key=lambda i: (-val_bal[i], -tr_f1[i], dist_to_base[i]))[0]
            
        elif method == "full_training_fold":
            max_bal = np.max(full_bal)
            cands_b = np.where(np.isclose(full_bal, max_bal))[0]
            best_b = sorted(cands_b, key=lambda i: (-full_f1[i], dist_to_base[i]))[0]
            
            max_f = np.max(full_f1)
            cands_f = np.where(np.isclose(full_f1, max_f))[0]
            best_f = sorted(cands_f, key=lambda i: (-full_bal[i], dist_to_base[i]))[0]
            
        chosen_b_list.append(combos_arr[best_b])
        chosen_f_list.append(combos_arr[best_f])
        
        _, _, _, _, _, p_b = evaluate_predictions_vectorized(combos_arr[best_b:best_b+1], test_idx, labels)
        _, _, _, _, _, p_f = evaluate_predictions_vectorized(combos_arr[best_f:best_f+1], test_idx, labels)
        preds_b[test_idx] = p_b[0].astype(int)
        preds_f[test_idx] = p_f[0].astype(int)
        
    print(f"\nMethod: {method}")
    acc_b = accuracy_score(labels, preds_b)
    bal_b = balanced_accuracy_score(labels, preds_b)
    f1_b = f1_score(labels, preds_b, average="macro")
    print(f"  Selection by BalAcc: Acc={acc_b*100:.2f}%, BalAcc={bal_b*100:.2f}%, MacroF1={f1_b*100:.2f}%")
    print(f"    Chosen thresholds: {[list(x) for x in chosen_b_list]}")
    
    acc_f = accuracy_score(labels, preds_f)
    bal_f = balanced_accuracy_score(labels, preds_f)
    f1_f = f1_score(labels, preds_f, average="macro")
    print(f"  Selection by MacroF1: Acc={acc_f*100:.2f}%, BalAcc={bal_f*100:.2f}%, MacroF1={f1_f*100:.2f}%")
    print(f"    Chosen thresholds: {[list(x) for x in chosen_f_list]}")

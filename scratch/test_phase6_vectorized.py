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

print("="*80)
print("PHASE 6: NESTED LOSO RULE OPTIMIZATION EXPLORATION")
print("="*80)

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
    
    # 1. Base threshold on val and test
    b_bal_val, b_f1_val, b_acc_val, _, _, _ = evaluate_predictions_vectorized(BASE_THRESH[None, :], val_idx, labels)
    b_bal_te, b_f1_te, b_acc_te, b_cp_te, b_cn_te, _ = evaluate_predictions_vectorized(BASE_THRESH[None, :], test_idx, labels)
    
    print(f"\n--- FOLD HELD OUT: {test_sub} (N={len(test_idx)}) ---")
    print(f"Base thresh on val: BalAcc={b_bal_val[0]*100:.2f}%, F1={b_f1_val[0]*100:.2f}% | on test: BalAcc={b_bal_te[0]*100:.2f}%, F1={b_f1_te[0]*100:.2f}%")
    
    # Evaluate all combos on val_idx
    val_bal, val_f1, val_acc, _, _, _ = evaluate_predictions_vectorized(combos_arr, val_idx, labels)
    # Also evaluate all combos on actual_tr_idx
    tr_bal, tr_f1, tr_acc, _, _, _ = evaluate_predictions_vectorized(combos_arr, actual_tr_idx, labels)
    
    # Check max val bal_acc
    max_val_bal = np.max(val_bal)
    cand_bal_indices = np.where(np.isclose(val_bal, max_val_bal))[0]
    print(f"Val BalAcc Max: {max_val_bal*100:.2f}%, count={len(cand_bal_indices)}")
    
    # Distance to base thresh for tie breaking
    # Normalized Euclidean distance
    scale = np.array([10.0, 0.1, 10.0, 2.0], dtype=np.float32)
    dist = np.sum(((combos_arr - BASE_THRESH) / scale)**2, axis=1)
    
    # Selection by BalAcc on val:
    # Tie-break 1: highest Macro-F1 on val, then highest BalAcc on actual_tr, then closest to BASE_THRESH
    sorted_cand_bal = sorted(cand_bal_indices, key=lambda i: (-val_f1[i], -tr_bal[i], dist[i]))
    chosen_bal_idx = sorted_cand_bal[0]
    chosen_bal_th = combos_arr[chosen_bal_idx]
    
    # Evaluate chosen on test
    te_bal_b, te_f1_b, te_acc_b, te_cr_b, te_ir_b, _ = evaluate_predictions_vectorized(chosen_bal_th[None, :], test_idx, labels)
    print(f"  Chosen by BalAcc: {chosen_bal_th} (Val Bal={val_bal[chosen_bal_idx]*100:.2f}%, Tr Bal={tr_bal[chosen_bal_idx]*100:.2f}%)")
    print(f"    Test: Acc={te_acc_b[0]*100:.2f}%, BalAcc={te_bal_b[0]*100:.2f}%, F1={te_f1_b[0]*100:.2f}%, CorRec={te_cr_b[0]*100:.2f}%, IncRec={te_ir_b[0]*100:.2f}%")

    # Selection by Macro-F1 on val:
    max_val_f1 = np.max(val_f1)
    cand_f1_indices = np.where(np.isclose(val_f1, max_val_f1))[0]
    sorted_cand_f1 = sorted(cand_f1_indices, key=lambda i: (-val_bal[i], -tr_f1[i], dist[i]))
    chosen_f1_idx = sorted_cand_f1[0]
    chosen_f1_th = combos_arr[chosen_f1_idx]
    
    te_bal_f, te_f1_f, te_acc_f, te_cr_f, te_ir_f, _ = evaluate_predictions_vectorized(chosen_f1_th[None, :], test_idx, labels)
    print(f"  Chosen by MacroF1: {chosen_f1_th} (Val F1={val_f1[chosen_f1_idx]*100:.2f}%, Tr F1={tr_f1[chosen_f1_idx]*100:.2f}%)")
    print(f"    Test: Acc={te_acc_f[0]*100:.2f}%, BalAcc={te_bal_f[0]*100:.2f}%, F1={te_f1_f[0]*100:.2f}%, CorRec={te_cr_f[0]*100:.2f}%, IncRec={te_ir_f[0]*100:.2f}%")

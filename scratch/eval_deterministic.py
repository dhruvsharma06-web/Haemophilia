import pandas as pd
from sklearn.metrics import accuracy_score, balanced_accuracy_score, f1_score, recall_score, confusion_matrix

def eval_baseline(csv_path):
    df = pd.read_csv(csv_path)
    y_true = (df['ground_truth_label'] == 'Correct').astype(int).values
    preds = []
    for _, r in df.iterrows():
        min_a = float(r['min_elbow_angle'])
        flare = float(r['elbow_flare'])
        rom = float(r['rom'])
        tilt = float(r['torso_tilt'])
        is_correct = (min_a <= 101.0) and (flare <= 0.30) and (rom >= 25.0) and (tilt <= 5.0)
        preds.append(1 if is_correct else 0)
    
    acc = accuracy_score(y_true, preds)
    bal_acc = balanced_accuracy_score(y_true, preds)
    macro_f1 = f1_score(y_true, preds, average='macro')
    c_rec = recall_score(y_true, preds, pos_label=1)
    inc_rec = recall_score(y_true, preds, pos_label=0)
    cm = confusion_matrix(y_true, preds).tolist()
    print(f"=== {csv_path} ===")
    print(f"Total={len(df)}, Correct={sum(y_true)}, Incorrect={len(y_true)-sum(y_true)}")
    print(f"Accuracy: {acc*100:.2f}%")
    print(f"Balanced Accuracy: {bal_acc*100:.2f}%")
    print(f"Macro-F1: {macro_f1*100:.2f}%")
    print(f"Correct Recall: {c_rec*100:.2f}%")
    print(f"Incorrect Recall: {inc_rec*100:.2f}%")
    print(f"Confusion Matrix [[TN, FP], [FN, TP]]: {cm}")
    for s in sorted(df['subject_id'].unique()):
        m = (df['subject_id'] == s).values
        ys = y_true[m]
        ps = [preds[i] for i, b in enumerate(m) if b]
        s_acc = accuracy_score(ys, ps)
        s_bal = balanced_accuracy_score(ys, ps)
        s_f1 = f1_score(ys, ps, average='macro')
        print(f"  {s}: Acc={s_acc*100:.2f}%, BalAcc={s_bal*100:.2f}%, F1={s_f1*100:.2f}%")

eval_baseline('data/clean_elbow_train.csv')
print()
eval_baseline('data/clean_elbow_train_expanded.csv')

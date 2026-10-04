"""Phase 3 utilities and canonical inputs loader."""
from pathlib import Path
import sys, json, hashlib
import numpy as np
import pandas as pd

P3 = Path(__file__).resolve().parent
P2 = P3.parent / 'phase2'
P1 = P3.parent
REPO = P1.parents[1]
DATA = REPO / 'processed_data/assisted_elbow_flexion_v2'
RELEASE = DATA / 'releases/human280_20261004'

sys.path.insert(0, str(P1))
from common import canonical, verify_config, sha, dump, write_csv

METRICS = ['accuracy', 'balanced_accuracy', 'macro_f1', 'correct_recall', 'incorrect_recall']

def inputs():
    verify_config()
    rows, check = canonical()
    df = pd.DataFrame(rows)
    folds = pd.read_csv(P1 / 'splits/fold_assignments.csv')
    assert folds.repetition_id.tolist() == df.repetition_id.tolist()
    check(rows, dict(zip(folds.repetition_id, folds.fold.astype(str))))
    df['fold'] = folds.fold
    d = dict(np.load(P1 / 'features/model_ready.npz'))
    assert d['repetition_ids'].tolist() == df.repetition_id.tolist()
    preds = pd.read_csv(P1 / 'baselines/SVM/out_of_fold_predictions.csv')
    assert preds.repetition_id.tolist() == df.repetition_id.tolist()
    assert preds.fold.tolist() == df.fold.tolist()
    assert preds.y_true.tolist() == (df.label == 'Incorrect').astype(int).tolist()
    assert int((~preds.is_correct).sum()) == 36
    return df, d, preds

def metrics(y, p):
    from sklearn.metrics import confusion_matrix, accuracy_score, f1_score
    cm = confusion_matrix(y, p, labels=[0, 1])
    ns = cm.sum(axis=1)
    recalls = [float(cm[i, i] / ns[i]) if ns[i] else None for i in [0, 1]]
    return {
        'n': len(y),
        'accuracy': float(accuracy_score(y, p)),
        'balanced_accuracy': float(np.mean(recalls)) if all(x is not None for x in recalls) else None,
        'macro_f1': float(f1_score(y, p, labels=[0, 1], average='macro', zero_division=0)),
        'correct_recall': recalls[0],
        'incorrect_recall': recalls[1],
        'confusion_matrix': cm.tolist()
    }

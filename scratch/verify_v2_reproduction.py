import sys
import numpy as np
import pandas as pd
import torch
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.append(str(BASE_DIR))
sys.path.append(str(BASE_DIR / "scratch"))

from run_phase_aware_ablation import (
    DATA_PATH, SEQUENCE_DIR,
    extract_subject_normalized_temporal,
    extract_phase_aware_scalars,
    evaluate_loso_experiment,
    HybridTemporalScalarModel,
    RANDOM_SEED,
)

df = pd.read_csv(DATA_PATH)
seq_list = []
scalar_list = []
for _, r in df.iterrows():
    raw = np.load(SEQUENCE_DIR / r["sequence_file"])
    dur = float(r["duration_sec"])
    seq_list.append(extract_subject_normalized_temporal(raw))
    scalar_list.append(extract_phase_aware_scalars(raw, dur, include_bilateral=True))

seq_arr = np.array(seq_list, dtype=np.float32)
scalar_arr = np.array(scalar_list, dtype=np.float32)

print("Running exact evaluate_loso_experiment with tune_threshold=True:")
res = evaluate_loso_experiment(
    df,
    seq_arr,
    scalar_arr,
    model_factory=lambda: HybridTemporalScalarModel(temporal_dim=10, scalar_dim=34, lstm_hidden=32, mlp_hidden=16, dropout=0.4),
    tune_threshold=True,
    seed=RANDOM_SEED,
)

agg = res["aggregate"]
print(f"Accuracy: {agg['accuracy']*100:.2f}%")
print(f"Balanced Accuracy: {agg['balanced_accuracy']*100:.2f}%")
print(f"Macro-F1: {agg['macro_f1']*100:.2f}%")
print(f"Correct Recall: {agg['correct_recall']*100:.2f}%")
print(f"Incorrect Recall: {agg['incorrect_recall']*100:.2f}%")
print(f"Confusion Matrix: {agg['confusion_matrix']}")
for sub, sm in res["folds"].items():
    print(f"  {sub}: Acc={sm['accuracy']*100:.2f}%, BalAcc={sm['balanced_accuracy']*100:.2f}%, F1={sm['macro_f1']*100:.2f}%, Thresh={sm['optimal_threshold']:.2f}")

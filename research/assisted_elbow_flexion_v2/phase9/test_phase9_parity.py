"""Offline Numerical Parity Verification for Phase 9 Optimized Model Adapter.

Verifies:
1. Exact preprocessing equivalence with scikit-learn reference pipeline
2. Exact decision score agreement (floating point tolerance < 1e-10)
3. 280 / 280 identical class predictions on all canonical repetitions
"""

import sys
import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

from phase9_model_adapter import Phase9ModelAdapter

PHASE9_DIR = Path(__file__).resolve().parent
RESEARCH_DIR = PHASE9_DIR.parent
CANONICAL_DIR = RESEARCH_DIR.parents[1] / 'processed_data' / 'assisted_elbow_flexion_v2' / 'releases' / 'human280_20261004'

def main():
    print("=== Phase 9: Running Offline Parity Verification ===")

    # 1. Load canonical data
    features_npz = np.load(RESEARCH_DIR / 'features' / 'model_ready.npz')
    X_raw = features_npz['scalar']
    rep_ids = [str(r) for r in features_npz['repetition_ids']]
    splits_df = pd.read_csv(RESEARCH_DIR / 'splits' / 'fold_assignments.csv')
    y_true = (splits_df.label == 'Incorrect').astype(int).to_numpy()

    # 2. Build scikit-learn reference model
    checkpoint_file = PHASE9_DIR / 'checkpoints' / 'final_model_v2_optimized_parameters.json'
    with open(checkpoint_file, 'r', encoding='utf-8') as f:
        params = json.load(f)

    # Scikit-learn reference pipeline
    imp_ref = SimpleImputer(strategy='median', keep_empty_features=True)
    X_imp_ref = imp_ref.fit_transform(X_raw)

    scaler_ref = StandardScaler()
    X_scale_ref = scaler_ref.fit_transform(X_imp_ref)

    clf_ref = SVC(C=1.0, kernel='rbf', gamma=0.04, class_weight='balanced', probability=False)
    clf_ref.fit(X_scale_ref, y_true)

    ref_scores = clf_ref.decision_function(X_scale_ref)
    ref_preds = clf_ref.predict(X_scale_ref)

    # 3. Evaluate through Phase 9 Adapter
    adapter = Phase9ModelAdapter(checkpoint_file)

    adapter_imp, adapter_scale = adapter.preprocess(X_raw)
    adapter_preds, adapter_scores = adapter.predict(X_raw)

    # 4. Numerical comparison
    imp_diff = np.max(np.abs(X_imp_ref - adapter_imp))
    scale_diff = np.max(np.abs(X_scale_ref - adapter_scale))
    score_diff = np.max(np.abs(ref_scores - adapter_scores))
    pred_agreement = np.sum(ref_preds == adapter_preds)

    print(f"Max Imputer Difference:      {imp_diff:.2e}")
    print(f"Max Scaler Difference:       {scale_diff:.2e}")
    print(f"Max Decision Score Diff:     {score_diff:.2e}")
    print(f"Prediction Agreement:        {pred_agreement} / 280 ({pred_agreement/280*100:.2f}%)")

    assert imp_diff < 1e-10, f"Imputer difference too large: {imp_diff}"
    assert scale_diff < 1e-10, f"Scaler difference too large: {scale_diff}"
    assert score_diff < 1e-10, f"Decision score difference too large: {score_diff}"
    assert pred_agreement == 280, f"Prediction mismatch: {pred_agreement} != 280"

    # Save parity results table
    parity_rows = []
    for i in range(280):
        parity_rows.append({
            'repetition_id': rep_ids[i],
            'true_label': splits_df.label.iloc[i],
            'y_true': int(y_true[i]),
            'sklearn_score': float(ref_scores[i]),
            'adapter_score': float(adapter_scores[i]),
            'abs_score_diff': float(abs(ref_scores[i] - adapter_scores[i])),
            'sklearn_pred': int(ref_preds[i]),
            'adapter_pred': int(adapter_preds[i]),
            'match': bool(ref_preds[i] == adapter_preds[i])
        })

    parity_df = pd.DataFrame(parity_rows)
    parity_csv = PHASE9_DIR / 'offline_parity_results.csv'
    parity_df.to_csv(parity_csv, index=False)
    print(f"Wrote parity results to {parity_csv.name}")
    print("=== Parity Verification: PASSED (Exact Numerical Parity Confirmed) ===")

if __name__ == '__main__':
    main()

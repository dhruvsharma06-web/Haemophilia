"""Verify membership, isolation, preprocessing fits, evaluation and preservation."""
from pathlib import Path
import sys, json
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, canonical, verify_config, sha, dump
import pandas as pd
import numpy as np

def main():
    lock = verify_config()
    rows, check = canonical()
    folds = pd.read_csv(ROOT / 'splits/fold_assignments.csv')
    check(rows, dict(zip(folds.repetition_id, folds.fold.astype(str))))
    expected = {r['repetition_id'] for r in rows}
    models = ['LogisticRegression', 'RandomForest', 'HistGradientBoosting', 'SVM', 'UniLSTM']
    fit_checks = []
    for name in models:
        summary = json.loads((ROOT / 'baselines' / name / 'summary.json').read_text())
        pred = pd.read_csv(ROOT / 'baselines' / name / 'out_of_fold_predictions.csv')
        assert len(pred) == 280 and set(pred.repetition_id) == expected
        assert pred.repetition_id.tolist() == folds.repetition_id.tolist()
        assert pred.fold.tolist() == folds.fold.tolist()
        assert (pred.y_true == (pred.label == 'Incorrect').astype(int)).all()
        assert set(pred.y_pred) <= {0, 1}
        assert summary['manifest_sha256'] == lock['manifest_sha256']
        assert summary['model_ready_sha256'] == sha(ROOT / 'features/model_ready.npz')
        for fit in summary['training']:
            f = fit['fold']
            tr = folds[folds.fold != f]
            va = folds[folds.fold == f]
            assert set(fit['train_repetition_ids']) == set(tr.repetition_id)
            assert set(fit['validation_repetition_ids']) == set(va.repetition_id)
            assert not set(tr.source_sha256) & set(va.source_sha256)
            d = dict(np.load(ROOT / 'features/model_ready.npz'))
            train = d['sequence'][folds.fold != f].reshape(-1, 11) if name == 'UniLSTM' else d['scalar'][folds.fold != f]
            train = train.astype(np.float64)
            assert fit['imputer']['fit_rows'] == len(train)
            means=np.nanmean(train,axis=0)
            # Temporal inputs are float32; masked summation may differ slightly
            # from this independent float64 recomputation.
            assert np.allclose(fit['imputer']['statistics'],means,rtol=2e-5,atol=1e-6)
            train=np.where(np.isnan(train),fit['imputer']['statistics'],train)
            assert np.isfinite(train).all()
            if 'scaler' in fit:
                assert fit['scaler']['n_samples_seen'] == len(train)
                assert np.allclose(fit['scaler']['mean'], train.mean(axis=0), atol=1e-8)
                scale = train.std(axis=0)
                scale[scale == 0] = 1
                assert np.allclose(fit['scaler']['scale'], scale, rtol=1e-5, atol=1e-7)
            fit_checks.append({'model': name, 'fold': f, 'source_intersection': [], 'membership_and_scaler_fit_verified': True})
    protected = json.loads((ROOT / 'provenance/protected_files_before.json').read_text())
    changes = []
    for p, before in protected.items():
        path = Path(p)
        if not path.exists() or sha(path) != before:
            changes.append(p)
    dump(ROOT / 'reports/preservation_audit.json', {'protected_files_checked': len(protected), 'modified_or_missing': changes, 'all_unchanged': not changes})
    assert not changes, 'Protected file preservation failed'
    dump(ROOT / 'reports/verification.json', {'canonical_examples': 280, 'models': models, 'fold_fit_checks': fit_checks, 'protected_files_unchanged': len(protected), 'all_passed': True, 'script_sha256': sha(__file__)})
    print(json.dumps({'all_passed': True, 'canonical_n': 280, 'model_fold_checks': len(fit_checks), 'protected_files_unchanged': len(protected)}))

if __name__ == '__main__':
    main()

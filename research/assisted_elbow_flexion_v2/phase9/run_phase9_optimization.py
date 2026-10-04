"""Phase 9 Model Optimization Execution Script.

Strictly adhering to Phase 9 Hard Rules and Invariants:
- Uses ONLY canonical 280-repetition dataset (human280_20261004)
- 5 source-grouped folds (StratifiedGroupKFold, random_state=42)
- All preprocessing and feature selection strictly inside training folds
- Nested inner-CV for threshold optimization and nested model confirmation
- Primary metric: Balanced Accuracy
"""

import os
os.environ['OMP_NUM_THREADS'] = '1'
import sys
import time
import json
import hashlib
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler, RobustScaler
from sklearn.feature_selection import SelectKBest, f_classif
from sklearn.svm import SVC
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import ExtraTreesClassifier, HistGradientBoostingClassifier
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import confusion_matrix, accuracy_score, f1_score

# Paths
PHASE9_DIR = Path(__file__).resolve().parent
RESEARCH_DIR = PHASE9_DIR.parent
REPO_ROOT = RESEARCH_DIR.parents[1]
CANONICAL_DIR = REPO_ROOT / 'processed_data' / 'assisted_elbow_flexion_v2' / 'releases' / 'human280_20261004'

for subdir in ['checkpoints', 'plots', 'provenance']:
    (PHASE9_DIR / subdir).mkdir(parents=True, exist_ok=True)

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def compute_metrics(y_true, y_pred):
    cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
    n0 = cm[0].sum()
    n1 = cm[1].sum()
    rec0 = float(cm[0, 0] / n0) if n0 > 0 else 0.0
    rec1 = float(cm[1, 1] / n1) if n1 > 0 else 0.0
    ba = float((rec0 + rec1) / 2.0)
    acc = float(accuracy_score(y_true, y_pred))
    f1 = float(f1_score(y_true, y_pred, labels=[0, 1], average='macro', zero_division=0))
    return {
        'n': len(y_true),
        'accuracy': acc,
        'balanced_accuracy': ba,
        'macro_f1': f1,
        'correct_recall': rec0,
        'incorrect_recall': rec1,
        'confusion_matrix': cm.tolist()
    }

def get_preprocessor(pipe_name):
    if pipe_name == 'Pipeline A':
        return SimpleImputer(strategy='mean', keep_empty_features=True), StandardScaler()
    elif pipe_name == 'Pipeline B':
        return SimpleImputer(strategy='median', keep_empty_features=True), StandardScaler()
    elif pipe_name == 'Pipeline C':
        return SimpleImputer(strategy='mean', keep_empty_features=True), RobustScaler()
    else:
        raise ValueError(f"Unknown pipeline: {pipe_name}")

def evaluate_model_on_folds(clf_builder, X_all, y_all, fold_assignments, pipe_name='Pipeline A', feature_k=34, threshold=0.0):
    t_start = time.time()
    preds = np.full(280, -1, dtype=int)
    scores = np.full(280, np.nan, dtype=float)
    fold_ba = []
    
    for f in range(5):
        val_idx = np.where(fold_assignments == f)[0]
        train_idx = np.where(fold_assignments != f)[0]
        
        imp, scaler = get_preprocessor(pipe_name)
        X_tr = imp.fit_transform(X_all[train_idx])
        X_va = imp.transform(X_all[val_idx])
        
        if scaler is not None:
            X_tr = scaler.fit_transform(X_tr)
            X_va = scaler.transform(X_va)
            
        if feature_k < 34:
            selector = SelectKBest(score_func=f_classif, k=feature_k)
            X_tr = selector.fit_transform(X_tr, y_all[train_idx])
            X_va = selector.transform(X_va)
            
        clf = clf_builder()
        clf.fit(X_tr, y_all[train_idx])
        
        if hasattr(clf, 'decision_function'):
            s = clf.decision_function(X_va)
            p = (s > threshold).astype(int)
        elif hasattr(clf, 'predict_proba'):
            prob = clf.predict_proba(X_va)[:, 1]
            prob_clipped = np.clip(prob, 1e-7, 1 - 1e-7)
            s = np.log(prob_clipped / (1.0 - prob_clipped))
            p = (s > threshold).astype(int)
        else:
            p = clf.predict(X_va)
            s = p.astype(float)
            
        preds[val_idx] = p
        scores[val_idx] = s
        
        f_m = compute_metrics(y_all[val_idx], p)
        fold_ba.append(f_m['balanced_accuracy'])
        
    runtime = time.time() - t_start
    ov_m = compute_metrics(y_all, preds)
    ov_m['fold_mean_balanced_accuracy'] = float(np.mean(fold_ba))
    ov_m['fold_std_balanced_accuracy'] = float(np.std(fold_ba, ddof=1))
    ov_m['runtime_sec'] = float(runtime)
    ov_m['predictions'] = preds
    ov_m['scores'] = scores
    return ov_m

def main():
    print("=== Phase 9: Loading Canonical Data ===", flush=True)
    manifest_path = CANONICAL_DIR / 'canonical_manifest.csv'
    manifest_sha = sha256_file(manifest_path)
    print(f"Canonical manifest SHA-256: {manifest_sha}", flush=True)
    assert manifest_sha == 'bb4669ec492ac26cbf5b064c89390e43cac207f9785c3a5cd0003cea3c587262'

    features_path = RESEARCH_DIR / 'features' / 'model_ready.npz'
    data_npz = np.load(features_path)
    X_all = data_npz['scalar']  # (280, 34)
    feature_names = [str(s) for s in data_npz['scalar_names']]
    assert len(feature_names) == 34
    assert X_all.shape == (280, 34)

    splits_path = RESEARCH_DIR / 'splits' / 'fold_assignments.csv'
    folds_df = pd.read_csv(splits_path)
    assert len(folds_df) == 280
    y_all = (folds_df.label == 'Incorrect').astype(int).to_numpy()
    sources_all = folds_df.source_sha256.to_numpy()
    fold_assignments = folds_df.fold.to_numpy()

    print(f"Data verified: 280 examples, {int((y_all==0).sum())} Correct, {int((y_all==1).sum())} Incorrect", flush=True)
    print(f"5 Source-grouped folds loaded from {splits_path.name}", flush=True)

    # 1. Baseline Phase 3 BalancedSVM
    print("\n--- 1. Evaluating Phase 3 BalancedSVM Baseline ---", flush=True)
    baseline_res = evaluate_model_on_folds(
        lambda: SVC(C=1.0, kernel='rbf', gamma='scale', class_weight='balanced'),
        X_all, y_all, fold_assignments,
        pipe_name='Pipeline A', feature_k=34, threshold=0.0
    )
    print(f"Phase 3 BalancedSVM Baseline:")
    print(f"  Accuracy:          {baseline_res['accuracy']*100:.2f}%")
    print(f"  Balanced Accuracy: {baseline_res['balanced_accuracy']*100:.2f}%")
    print(f"  Macro F1:          {baseline_res['macro_f1']*100:.2f}%")
    print(f"  Correct Recall:    {baseline_res['correct_recall']*100:.2f}%")
    print(f"  Incorrect Recall:  {baseline_res['incorrect_recall']*100:.2f}%")
    print(f"  Fold Mean BA:      {baseline_res['fold_mean_balanced_accuracy']*100:.2f}% (+/- {baseline_res['fold_std_balanced_accuracy']*100:.2f}%)")
    print(f"  Confusion Matrix:  {baseline_res['confusion_matrix']}", flush=True)

    all_results = []
    all_results.append({
        'model': 'Baseline_Phase3_BalancedSVM',
        'hyperparameters': 'C=1.0, gamma=scale, class_weight=balanced, kernel=rbf',
        'preprocessing': 'Pipeline A (mean + StandardScaler)',
        'feature_count': 34,
        'threshold': 0.0,
        'accuracy': baseline_res['accuracy'],
        'balanced_accuracy': baseline_res['balanced_accuracy'],
        'macro_f1': baseline_res['macro_f1'],
        'correct_recall': baseline_res['correct_recall'],
        'incorrect_recall': baseline_res['incorrect_recall'],
        'fold_mean_balanced_accuracy': baseline_res['fold_mean_balanced_accuracy'],
        'fold_std_balanced_accuracy': baseline_res['fold_std_balanced_accuracy'],
        'runtime_sec': baseline_res['runtime_sec']
    })

    # 2. Sweeps
    print("\n--- 2. Sweeping Model Candidates & Preprocessing Pipelines ---", flush=True)

    # Candidate A — RBF SVM
    print("Sweeping Candidate A: RBF SVM...", flush=True)
    t0 = time.time()
    for pipe in ['Pipeline A', 'Pipeline B', 'Pipeline C']:
        for C in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]:
            for gamma in ['scale', 0.005, 0.01, 0.02, 0.04, 0.08]:
                for cw in ['balanced', None]:
                    res = evaluate_model_on_folds(
                        lambda c=C, g=gamma, w=cw: SVC(C=c, kernel='rbf', gamma=g, class_weight=w),
                        X_all, y_all, fold_assignments,
                        pipe_name=pipe, feature_k=34, threshold=0.0
                    )
                    all_results.append({
                        'model': 'RBF_SVM',
                        'hyperparameters': f"C={C}, gamma={gamma}, class_weight={cw}, kernel=rbf",
                        'preprocessing': pipe,
                        'feature_count': 34,
                        'threshold': 0.0,
                        'accuracy': res['accuracy'],
                        'balanced_accuracy': res['balanced_accuracy'],
                        'macro_f1': res['macro_f1'],
                        'correct_recall': res['correct_recall'],
                        'incorrect_recall': res['incorrect_recall'],
                        'fold_mean_balanced_accuracy': res['fold_mean_balanced_accuracy'],
                        'fold_std_balanced_accuracy': res['fold_std_balanced_accuracy'],
                        'runtime_sec': res['runtime_sec']
                    })
    print(f"RBF SVM sweep finished in {time.time()-t0:.1f}s", flush=True)

    # Candidate B — Polynomial SVM
    print("Sweeping Candidate B: Polynomial SVM...", flush=True)
    t0 = time.time()
    for pipe in ['Pipeline A', 'Pipeline B', 'Pipeline C']:
        for deg in [2, 3]:
            for C in [0.5, 1.0, 2.0, 4.0]:
                for cw in ['balanced', None]:
                    res = evaluate_model_on_folds(
                        lambda d=deg, c=C, w=cw: SVC(C=c, kernel='poly', degree=d, gamma='scale', class_weight=w),
                        X_all, y_all, fold_assignments,
                        pipe_name=pipe, feature_k=34, threshold=0.0
                    )
                    all_results.append({
                        'model': 'Poly_SVM',
                        'hyperparameters': f"degree={deg}, C={C}, gamma=scale, class_weight={cw}, kernel=poly",
                        'preprocessing': pipe,
                        'feature_count': 34,
                        'threshold': 0.0,
                        'accuracy': res['accuracy'],
                        'balanced_accuracy': res['balanced_accuracy'],
                        'macro_f1': res['macro_f1'],
                        'correct_recall': res['correct_recall'],
                        'incorrect_recall': res['incorrect_recall'],
                        'fold_mean_balanced_accuracy': res['fold_mean_balanced_accuracy'],
                        'fold_std_balanced_accuracy': res['fold_std_balanced_accuracy'],
                        'runtime_sec': res['runtime_sec']
                    })
    print(f"Poly SVM sweep finished in {time.time()-t0:.1f}s", flush=True)

    # Candidate C — Logistic Regression
    print("Sweeping Candidate C: Logistic Regression...", flush=True)
    t0 = time.time()
    for pipe in ['Pipeline A', 'Pipeline B', 'Pipeline C']:
        for C in [0.01, 0.1, 1.0, 10.0, 100.0]:
            for cw in ['balanced', None]:
                res = evaluate_model_on_folds(
                    lambda c=C, w=cw: LogisticRegression(C=c, penalty='l2', solver='lbfgs', class_weight=w, max_iter=2000, random_state=42),
                    X_all, y_all, fold_assignments,
                    pipe_name=pipe, feature_k=34, threshold=0.0
                )
                all_results.append({
                    'model': 'LogisticRegression',
                    'hyperparameters': f"C={C}, penalty=l2, class_weight={cw}, solver=lbfgs",
                    'preprocessing': pipe,
                    'feature_count': 34,
                    'threshold': 0.0,
                    'accuracy': res['accuracy'],
                    'balanced_accuracy': res['balanced_accuracy'],
                    'macro_f1': res['macro_f1'],
                    'correct_recall': res['correct_recall'],
                    'incorrect_recall': res['incorrect_recall'],
                    'fold_mean_balanced_accuracy': res['fold_mean_balanced_accuracy'],
                    'fold_std_balanced_accuracy': res['fold_std_balanced_accuracy'],
                    'runtime_sec': res['runtime_sec']
                })
    print(f"Logistic Regression sweep finished in {time.time()-t0:.1f}s", flush=True)

    # Candidate D — ExtraTrees (compact grid with n_jobs=1)
    print("Sweeping Candidate D: ExtraTrees...", flush=True)
    t0 = time.time()
    for pipe in ['Pipeline A', 'Pipeline B']:
        for n_est in [300, 500]:
            for md in [None, 6, 10, 16]:
                for msl in [1, 2, 4]:
                    for cw in ['balanced', None]:
                        res = evaluate_model_on_folds(
                            lambda n=n_est, d=md, m=msl, w=cw: ExtraTreesClassifier(
                                n_estimators=n, max_depth=d, min_samples_leaf=m, class_weight=w, random_state=42, n_jobs=1
                            ),
                            X_all, y_all, fold_assignments,
                            pipe_name=pipe, feature_k=34, threshold=0.0
                        )
                        all_results.append({
                            'model': 'ExtraTrees',
                            'hyperparameters': f"n_estimators={n_est}, max_depth={md}, min_samples_leaf={msl}, class_weight={cw}",
                            'preprocessing': pipe,
                            'feature_count': 34,
                            'threshold': 0.0,
                            'accuracy': res['accuracy'],
                            'balanced_accuracy': res['balanced_accuracy'],
                            'macro_f1': res['macro_f1'],
                            'correct_recall': res['correct_recall'],
                            'incorrect_recall': res['incorrect_recall'],
                            'fold_mean_balanced_accuracy': res['fold_mean_balanced_accuracy'],
                            'fold_std_balanced_accuracy': res['fold_std_balanced_accuracy'],
                            'runtime_sec': res['runtime_sec']
                        })
    print(f"ExtraTrees sweep finished in {time.time()-t0:.1f}s", flush=True)

    # Candidate E — HistGradientBoosting
    print("Sweeping Candidate E: HistGradientBoosting...", flush=True)
    t0 = time.time()
    for pipe in ['Pipeline A', 'Pipeline B']:
        for lr in [0.03, 0.05, 0.1]:
            for mi in [100, 200, 300]:
                for mln in [7, 15, 31]:
                    for l2 in [0.0, 1.0]:
                        res = evaluate_model_on_folds(
                            lambda r=lr, i=mi, ln=mln, reg=l2: HistGradientBoostingClassifier(
                                learning_rate=r, max_iter=i, max_leaf_nodes=ln, l2_regularization=reg, random_state=42
                            ),
                            X_all, y_all, fold_assignments,
                            pipe_name=pipe, feature_k=34, threshold=0.0
                        )
                        all_results.append({
                            'model': 'HistGradientBoosting',
                            'hyperparameters': f"learning_rate={lr}, max_iter={mi}, max_leaf_nodes={mln}, l2_regularization={l2}",
                            'preprocessing': pipe,
                            'feature_count': 34,
                            'threshold': 0.0,
                            'accuracy': res['accuracy'],
                            'balanced_accuracy': res['balanced_accuracy'],
                            'macro_f1': res['macro_f1'],
                            'correct_recall': res['correct_recall'],
                            'incorrect_recall': res['incorrect_recall'],
                            'fold_mean_balanced_accuracy': res['fold_mean_balanced_accuracy'],
                            'fold_std_balanced_accuracy': res['fold_std_balanced_accuracy'],
                            'runtime_sec': res['runtime_sec']
                        })
    print(f"HistGradientBoosting sweep finished in {time.time()-t0:.1f}s", flush=True)

    df_results = pd.DataFrame(all_results).sort_values(by='balanced_accuracy', ascending=False).reset_index(drop=True)
    print(f"\nCompleted sweep of {len(df_results)} models. Top 5 models:")
    print(df_results[['model', 'hyperparameters', 'preprocessing', 'balanced_accuracy', 'accuracy', 'macro_f1', 'incorrect_recall']].head(5).to_string(), flush=True)

    # 3. Feature Selection Experiment
    print("\n--- 3. Testing Fold-Internal Feature Selection (Top 24, 28, 30 vs Full 34) ---", flush=True)
    top_models = []
    seen_types = set()
    for _, r in df_results.iterrows():
        if r['model'] not in seen_types and r['model'] != 'Baseline_Phase3_BalancedSVM':
            top_models.append(r)
            seen_types.add(r['model'])
        if len(seen_types) >= 3:
            break

    for tm in top_models:
        m_name = tm['model']
        pipe = tm['preprocessing']
        hparams = tm['hyperparameters']
        parts = dict(p.strip().split('=') for p in hparams.split(','))
        
        if m_name == 'RBF_SVM':
            c_val = float(parts['C'])
            g_val = parts['gamma'] if parts['gamma'] == 'scale' else float(parts['gamma'])
            w_val = None if parts['class_weight'] == 'None' else parts['class_weight']
            builder = lambda c=c_val, g=g_val, w=w_val: SVC(C=c, kernel='rbf', gamma=g, class_weight=w)
        elif m_name == 'LogisticRegression':
            c_val = float(parts['C'])
            w_val = None if parts['class_weight'] == 'None' else parts['class_weight']
            builder = lambda c=c_val, w=w_val: LogisticRegression(C=c, penalty='l2', solver='lbfgs', class_weight=w, max_iter=2000, random_state=42)
        elif m_name == 'HistGradientBoosting':
            lr = float(parts['learning_rate'])
            mi = int(parts['max_iter'])
            mln = int(parts['max_leaf_nodes'])
            l2 = float(parts['l2_regularization'])
            builder = lambda r=lr, i=mi, ln=mln, reg=l2: HistGradientBoostingClassifier(learning_rate=r, max_iter=i, max_leaf_nodes=ln, l2_regularization=reg, random_state=42)
        elif m_name == 'ExtraTrees':
            n_est = int(parts['n_estimators'])
            md = None if parts['max_depth'] == 'None' else int(parts['max_depth'])
            msl = int(parts['min_samples_leaf'])
            w_val = None if parts['class_weight'] == 'None' else parts['class_weight']
            builder = lambda n=n_est, d=md, m=msl, w=w_val: ExtraTreesClassifier(n_estimators=n, max_depth=d, min_samples_leaf=m, class_weight=w, random_state=42, n_jobs=1)
        else:
            continue

        for k in [24, 28, 30]:
            res_k = evaluate_model_on_folds(builder, X_all, y_all, fold_assignments, pipe_name=pipe, feature_k=k, threshold=0.0)
            all_results.append({
                'model': f"{m_name}_SelectK{k}",
                'hyperparameters': hparams,
                'preprocessing': pipe,
                'feature_count': k,
                'threshold': 0.0,
                'accuracy': res_k['accuracy'],
                'balanced_accuracy': res_k['balanced_accuracy'],
                'macro_f1': res_k['macro_f1'],
                'correct_recall': res_k['correct_recall'],
                'incorrect_recall': res_k['incorrect_recall'],
                'fold_mean_balanced_accuracy': res_k['fold_mean_balanced_accuracy'],
                'fold_std_balanced_accuracy': res_k['fold_std_balanced_accuracy'],
                'runtime_sec': res_k['runtime_sec']
            })

    # 4. Nested Threshold Optimization
    print("\n--- 4. Running Nested Decision Threshold Optimization ---", flush=True)
    def evaluate_nested_threshold(clf_builder, pipe_name='Pipeline A', feature_k=34):
        t_start = time.time()
        outer_preds = np.full(280, -1, dtype=int)
        outer_scores = np.full(280, np.nan, dtype=float)
        chosen_thresholds = []
        threshold_grid = [-0.50, -0.25, -0.10, 0.0, 0.10, 0.25, 0.50]
        fold_ba = []
        
        for f in range(5):
            val_idx = np.where(fold_assignments == f)[0]
            train_idx = np.where(fold_assignments != f)[0]
            
            X_outer_tr = X_all[train_idx]
            y_outer_tr = y_all[train_idx]
            src_outer_tr = sources_all[train_idx]
            
            inner_sgkf = StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=42)
            inner_scores = np.full(len(train_idx), np.nan, dtype=float)
            
            for inner_tr_idx, inner_va_idx in inner_sgkf.split(X_outer_tr, y_outer_tr, src_outer_tr):
                imp, scaler = get_preprocessor(pipe_name)
                X_in_tr = imp.fit_transform(X_outer_tr[inner_tr_idx])
                X_in_va = imp.transform(X_outer_tr[inner_va_idx])
                if scaler is not None:
                    X_in_tr = scaler.fit_transform(X_in_tr)
                    X_in_va = scaler.transform(X_in_va)
                if feature_k < 34:
                    sel = SelectKBest(score_func=f_classif, k=feature_k)
                    X_in_tr = sel.fit_transform(X_in_tr, y_outer_tr[inner_tr_idx])
                    X_in_va = sel.transform(X_in_va)
                    
                clf_in = clf_builder()
                clf_in.fit(X_in_tr, y_outer_tr[inner_tr_idx])
                if hasattr(clf_in, 'decision_function'):
                    inner_scores[inner_va_idx] = clf_in.decision_function(X_in_va)
                else:
                    prob = clf_in.predict_proba(X_in_va)[:, 1]
                    prob_clipped = np.clip(prob, 1e-7, 1 - 1e-7)
                    inner_scores[inner_va_idx] = np.log(prob_clipped / (1.0 - prob_clipped))
                    
            best_t = 0.0
            best_inner_ba = -1.0
            for t in threshold_grid:
                p_in = (inner_scores > t).astype(int)
                m_in = compute_metrics(y_outer_tr, p_in)
                if m_in['balanced_accuracy'] > best_inner_ba:
                    best_inner_ba = m_in['balanced_accuracy']
                    best_t = t
                    
            chosen_thresholds.append(best_t)
            
            imp_out, scaler_out = get_preprocessor(pipe_name)
            X_out_tr = imp_out.fit_transform(X_outer_tr)
            X_out_va = imp_out.transform(X_all[val_idx])
            if scaler_out is not None:
                X_out_tr = scaler_out.fit_transform(X_out_tr)
                X_out_va = scaler_out.transform(X_out_va)
            if feature_k < 34:
                sel_out = SelectKBest(score_func=f_classif, k=feature_k)
                X_out_tr = sel_out.fit_transform(X_out_tr, y_outer_tr)
                X_out_va = sel_out.transform(X_out_va)
                
            clf_out = clf_builder()
            clf_out.fit(X_out_tr, y_outer_tr)
            if hasattr(clf_out, 'decision_function'):
                s_out = clf_out.decision_function(X_out_va)
            else:
                prob = clf_out.predict_proba(X_out_va)[:, 1]
                prob_clipped = np.clip(prob, 1e-7, 1 - 1e-7)
                s_out = np.log(prob_clipped / (1.0 - prob_clipped))
                
            p_out = (s_out > best_t).astype(int)
            outer_preds[val_idx] = p_out
            outer_scores[val_idx] = s_out
            f_m = compute_metrics(y_all[val_idx], p_out)
            fold_ba.append(f_m['balanced_accuracy'])
            
        runtime = time.time() - t_start
        ov_m = compute_metrics(y_all, outer_preds)
        ov_m['fold_mean_balanced_accuracy'] = float(np.mean(fold_ba))
        ov_m['fold_std_balanced_accuracy'] = float(np.std(fold_ba, ddof=1))
        ov_m['runtime_sec'] = float(runtime)
        ov_m['chosen_thresholds'] = chosen_thresholds
        return ov_m

    base_thresh_res = evaluate_nested_threshold(
        lambda: SVC(C=1.0, kernel='rbf', gamma='scale', class_weight='balanced'),
        pipe_name='Pipeline A', feature_k=34
    )
    print(f"Baseline Nested Thresholds: {base_thresh_res['chosen_thresholds']}, BA: {base_thresh_res['balanced_accuracy']*100:.2f}%", flush=True)
    all_results.append({
        'model': 'Baseline_Phase3_NestedThresh',
        'hyperparameters': 'C=1.0, gamma=scale, class_weight=balanced, kernel=rbf',
        'preprocessing': 'Pipeline A',
        'feature_count': 34,
        'threshold': f"nested: {base_thresh_res['chosen_thresholds']}",
        'accuracy': base_thresh_res['accuracy'],
        'balanced_accuracy': base_thresh_res['balanced_accuracy'],
        'macro_f1': base_thresh_res['macro_f1'],
        'correct_recall': base_thresh_res['correct_recall'],
        'incorrect_recall': base_thresh_res['incorrect_recall'],
        'fold_mean_balanced_accuracy': base_thresh_res['fold_mean_balanced_accuracy'],
        'fold_std_balanced_accuracy': base_thresh_res['fold_std_balanced_accuracy'],
        'runtime_sec': base_thresh_res['runtime_sec']
    })

    # Save model_optimization_results.csv
    df_all_results = pd.DataFrame(all_results).sort_values(by='balanced_accuracy', ascending=False).reset_index(drop=True)
    results_csv_path = PHASE9_DIR / 'model_optimization_results.csv'
    df_all_results.to_csv(results_csv_path, index=False)
    print(f"\nWrote full optimization results to {results_csv_path.name} ({len(df_all_results)} entries).", flush=True)

    # 5. Nested CV Confirmation for Top Finalists
    print("\n--- 5. Nested Grouped CV Confirmation (Top 2 Finalists vs Baseline) ---", flush=True)
    non_base = df_all_results[~df_all_results['model'].str.contains('Baseline')].reset_index(drop=True)
    best_candidate_row = non_base.iloc[0]
    second_candidate_row = non_base.iloc[1]

    print("Top Candidate 1:", best_candidate_row['model'], best_candidate_row['hyperparameters'], f"BA: {best_candidate_row['balanced_accuracy']*100:.2f}%")
    print("Top Candidate 2:", second_candidate_row['model'], second_candidate_row['hyperparameters'], f"BA: {second_candidate_row['balanced_accuracy']*100:.2f}%")

    def run_strict_nested_cv(model_name, candidate_grid, pipe_name='Pipeline A'):
        t_start = time.time()
        outer_preds = np.full(280, -1, dtype=int)
        outer_scores = np.full(280, np.nan, dtype=float)
        fold_details = []
        
        for f in range(5):
            val_idx = np.where(fold_assignments == f)[0]
            train_idx = np.where(fold_assignments != f)[0]
            
            X_out_tr = X_all[train_idx]
            y_out_tr = y_all[train_idx]
            src_out_tr = sources_all[train_idx]
            
            inner_sgkf = StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=42)
            best_cfg = None
            best_cfg_ba = -1.0
            
            for cfg in candidate_grid:
                inner_preds = np.full(len(train_idx), -1, dtype=int)
                for in_tr, in_va in inner_sgkf.split(X_out_tr, y_out_tr, src_out_tr):
                    imp, sc = get_preprocessor(pipe_name)
                    X_tr_in = imp.fit_transform(X_out_tr[in_tr])
                    X_va_in = imp.transform(X_out_tr[in_va])
                    if sc is not None:
                        X_tr_in = sc.fit_transform(X_tr_in)
                        X_va_in = sc.transform(X_va_in)
                    clf = cfg['builder']()
                    clf.fit(X_tr_in, y_out_tr[in_tr])
                    inner_preds[in_va] = clf.predict(X_va_in)
                m_in = compute_metrics(y_out_tr, inner_preds)
                if m_in['balanced_accuracy'] > best_cfg_ba:
                    best_cfg_ba = m_in['balanced_accuracy']
                    best_cfg = cfg
                    
            imp_out, sc_out = get_preprocessor(pipe_name)
            X_tr_out = imp_out.fit_transform(X_out_tr)
            X_va_out = imp_out.transform(X_all[val_idx])
            if sc_out is not None:
                X_tr_out = sc_out.fit_transform(X_tr_out)
                X_va_out = sc_out.transform(X_va_out)
                
            clf_final = best_cfg['builder']()
            clf_final.fit(X_tr_out, y_out_tr)
            
            p_fold = clf_final.predict(X_va_out)
            if hasattr(clf_final, 'decision_function'):
                s_fold = clf_final.decision_function(X_va_out)
            else:
                s_fold = p_fold.astype(float)
                
            outer_preds[val_idx] = p_fold
            outer_scores[val_idx] = s_fold
            
            f_m = compute_metrics(y_all[val_idx], p_fold)
            fold_details.append({
                'fold': f,
                'selected_config': best_cfg['name'],
                'inner_ba': best_cfg_ba,
                'outer_ba': f_m['balanced_accuracy'],
                'outer_acc': f_m['accuracy']
            })
            
        tot_m = compute_metrics(y_all, outer_preds)
        outer_bas = [d['outer_ba'] for d in fold_details]
        tot_m['fold_mean_ba'] = float(np.mean(outer_bas))
        tot_m['fold_std_ba'] = float(np.std(outer_bas, ddof=1))
        tot_m['runtime'] = time.time() - t_start
        tot_m['fold_details'] = fold_details
        return tot_m

    rbf_grid = []
    for c in [0.5, 1.0, 2.0, 4.0]:
        for g in ['scale', 0.02, 0.04]:
            for w in ['balanced', None]:
                rbf_grid.append({
                    'name': f"RBF_SVM(C={c},g={g},w={w})",
                    'builder': lambda c=c, g=g, w=w: SVC(C=c, kernel='rbf', gamma=g, class_weight=w)
                })

    hgb_grid = []
    for lr in [0.03, 0.05, 0.1]:
        for mln in [7, 15]:
            for l2 in [0.0, 1.0]:
                hgb_grid.append({
                    'name': f"HGB(lr={lr},mln={mln},l2={l2})",
                    'builder': lambda r=lr, ln=mln, reg=l2: HistGradientBoostingClassifier(learning_rate=r, max_iter=200, max_leaf_nodes=ln, l2_regularization=reg, random_state=42)
                })

    baseline_grid = [{
        'name': 'BalancedSVM(C=1.0,gamma=scale,class_weight=balanced)',
        'builder': lambda: SVC(C=1.0, kernel='rbf', gamma='scale', class_weight='balanced')
    }]

    print("Running nested CV for Baseline...", flush=True)
    nested_base = run_strict_nested_cv('Baseline_Phase3_BalancedSVM', baseline_grid, pipe_name='Pipeline A')

    print("Running nested CV for Candidate 1 (RBF SVM space)...", flush=True)
    nested_cand1 = run_strict_nested_cv('Optimized_RBF_SVM_Nested', rbf_grid, pipe_name='Pipeline A')

    print("Running nested CV for Candidate 2 (HGB space)...", flush=True)
    nested_cand2 = run_strict_nested_cv('Optimized_HGB_Nested', hgb_grid, pipe_name='Pipeline A')

    nested_comparison_rows = [
        {
            'model': 'Baseline_Phase3_BalancedSVM',
            'nested_balanced_accuracy': nested_base['balanced_accuracy'],
            'nested_accuracy': nested_base['accuracy'],
            'nested_macro_f1': nested_base['macro_f1'],
            'nested_correct_recall': nested_base['correct_recall'],
            'nested_incorrect_recall': nested_base['incorrect_recall'],
            'fold_mean_ba': nested_base['fold_mean_ba'],
            'fold_std_ba': nested_base['fold_std_ba'],
            'selection_notes': 'Frozen baseline configuration'
        },
        {
            'model': 'Candidate1_RBF_SVM_Nested',
            'nested_balanced_accuracy': nested_cand1['balanced_accuracy'],
            'nested_accuracy': nested_cand1['accuracy'],
            'nested_macro_f1': nested_cand1['macro_f1'],
            'nested_correct_recall': nested_cand1['correct_recall'],
            'nested_incorrect_recall': nested_cand1['incorrect_recall'],
            'fold_mean_ba': nested_cand1['fold_mean_ba'],
            'fold_std_ba': nested_cand1['fold_std_ba'],
            'selection_notes': f"Inner selections: {[d['selected_config'] for d in nested_cand1['fold_details']]}"
        },
        {
            'model': 'Candidate2_HGB_Nested',
            'nested_balanced_accuracy': nested_cand2['balanced_accuracy'],
            'nested_accuracy': nested_cand2['accuracy'],
            'nested_macro_f1': nested_cand2['macro_f1'],
            'nested_correct_recall': nested_cand2['correct_recall'],
            'nested_incorrect_recall': nested_cand2['incorrect_recall'],
            'fold_mean_ba': nested_cand2['fold_mean_ba'],
            'fold_std_ba': nested_cand2['fold_std_ba'],
            'selection_notes': f"Inner selections: {[d['selected_config'] for d in nested_cand2['fold_details']]}"
        }
    ]

    df_nested = pd.DataFrame(nested_comparison_rows)
    nested_csv_path = PHASE9_DIR / 'nested_model_comparison.csv'
    df_nested.to_csv(nested_csv_path, index=False)
    print(f"\nWrote nested model comparison to {nested_csv_path.name}:")
    print(df_nested.to_string(), flush=True)

    # 6. Final Decision & Model Fit
    print("\n--- 6. Applying Final Decision Rule ---", flush=True)
    base_ba = baseline_res['balanced_accuracy']
    best_sweep_ba = df_all_results.iloc[0]['balanced_accuracy']
    nested_cand1_ba = nested_cand1['balanced_accuracy']
    ba_gain = best_sweep_ba - base_ba
    nested_gain = nested_cand1_ba - base_ba

    print(f"Baseline Balanced Accuracy:       {base_ba*100:.2f}%")
    print(f"Best Sweep Balanced Accuracy:      {best_sweep_ba*100:.2f}% (Gain: {ba_gain*100:+.2f} pp)")
    print(f"Nested Candidate Balanced Accuracy:{nested_cand1_ba*100:.2f}% (Gain: {nested_gain*100:+.2f} pp)")

    if ba_gain >= 0.0100 and nested_gain >= 0.0100:
        FINAL_DECISION = "A — Meaningful Improvement"
        print(f"DECISION: {FINAL_DECISION} (>= 1.0 pp gain in both standard CV and nested CV)")
    elif ba_gain >= 0.0100 and nested_gain < 0.0100:
        FINAL_DECISION = "B — No Meaningful Improvement"
        print(f"DECISION: {FINAL_DECISION} (Gain in standard CV ({ba_gain*100:+.2f} pp) failed to survive nested validation ({nested_gain*100:+.2f} pp))")
    else:
        FINAL_DECISION = "B — No Meaningful Improvement"
        print(f"DECISION: {FINAL_DECISION} (Maximum gain of {ba_gain*100:+.2f} pp did not achieve the required >= 1.0 pp threshold)")

    # Fit final optimized candidate model on ALL 280 repetitions
    print("\n--- 7. Fitting Final Optimized Candidate Model on All 280 Repetitions ---", flush=True)
    best_row = df_all_results[df_all_results['model'] != 'Baseline_Phase3_BalancedSVM'].iloc[0]
    print(f"Best Candidate Model: {best_row['model']}")
    print(f"Hyperparameters:      {best_row['hyperparameters']}")
    print(f"Preprocessing:        {best_row['preprocessing']}")
    print(f"Feature Count:        {best_row['feature_count']}")

    imp_final, scaler_final = get_preprocessor(best_row['preprocessing'])
    X_imp_all = imp_final.fit_transform(X_all)
    X_scale_all = scaler_final.fit_transform(X_imp_all)

    if 'RBF_SVM' in best_row['model']:
        parts = dict(p.strip().split('=') for p in best_row['hyperparameters'].split(','))
        c_val = float(parts['C'])
        g_val = parts['gamma'] if parts['gamma'] == 'scale' else float(parts['gamma'])
        w_val = None if parts['class_weight'] == 'None' else parts['class_weight']
        final_clf = SVC(C=c_val, kernel='rbf', gamma=g_val, class_weight=w_val, probability=False)
    elif 'HistGradientBoosting' in best_row['model']:
        parts = dict(p.strip().split('=') for p in best_row['hyperparameters'].split(','))
        final_clf = HistGradientBoostingClassifier(
            learning_rate=float(parts['learning_rate']),
            max_iter=int(parts['max_iter']),
            max_leaf_nodes=int(parts['max_leaf_nodes']),
            l2_regularization=float(parts['l2_regularization']),
            random_state=42
        )
    elif 'ExtraTrees' in best_row['model']:
        parts = dict(p.strip().split('=') for p in best_row['hyperparameters'].split(','))
        final_clf = ExtraTreesClassifier(
            n_estimators=int(parts['n_estimators']),
            max_depth=None if parts['max_depth'] == 'None' else int(parts['max_depth']),
            min_samples_leaf=int(parts['min_samples_leaf']),
            class_weight=None if parts['class_weight'] == 'None' else parts['class_weight'],
            random_state=42
        )
    else:
        parts = dict(p.strip().split('=') for p in best_row['hyperparameters'].split(','))
        final_clf = LogisticRegression(C=float(parts['C']), penalty='l2', solver='lbfgs', class_weight=None if parts['class_weight'] == 'None' else parts['class_weight'], max_iter=2000, random_state=42)

    final_clf.fit(X_scale_all, y_all)
    preds_train = final_clf.predict(X_scale_all)
    train_metrics = compute_metrics(y_all, preds_train)
    print(f"Apparent training metrics on all 280 repetitions: BA={train_metrics['balanced_accuracy']*100:.2f}%, Acc={train_metrics['accuracy']*100:.2f}%")

    optimized_params = {
        'model_name': f"Phase9_{best_row['model']}",
        'algorithm': best_row['model'],
        'hyperparameters': best_row['hyperparameters'],
        'preprocessing': best_row['preprocessing'],
        'feature_count': int(best_row['feature_count']),
        'feature_names': feature_names,
        'decision_threshold': float(best_row['threshold']) if isinstance(best_row['threshold'], (int, float)) else 0.0,
        'classes': [0, 1],
        'class_labels': ['Correct', 'Incorrect'],
        'imputer_statistics': imp_final.statistics_.tolist(),
        'scaler_mean': scaler_final.mean_.tolist(),
        'scaler_scale': scaler_final.scale_.tolist(),
    }

    if hasattr(final_clf, 'intercept_'):
        optimized_params['intercept'] = float(final_clf.intercept_[0])
    if hasattr(final_clf, 'support_vectors_'):
        optimized_params['support_vectors'] = final_clf.support_vectors_.tolist()
        optimized_params['dual_coefficients'] = final_clf.dual_coef_.tolist()
        optimized_params['n_support_vectors'] = [int(ns) for ns in final_clf.n_support_]
        optimized_params['total_support_vectors'] = int(sum(final_clf.n_support_))
    if hasattr(final_clf, '_gamma'):
        optimized_params['effective_gamma'] = float(final_clf._gamma)
    if hasattr(final_clf, 'class_weight_'):
        optimized_params['effective_class_weights'] = [float(w) for w in final_clf.class_weight_]

    checkpoint_path = PHASE9_DIR / 'checkpoints' / 'final_model_v2_optimized_parameters.json'
    with open(checkpoint_path, 'w', encoding='utf-8') as f:
        json.dump(optimized_params, f, indent=2)
    print(f"Wrote optimized model parameters to {checkpoint_path.name}")

    metadata = {
        'model_identity': f"Assisted_Elbow_Flexion_V2_Phase9_{best_row['model']}",
        'version': '2.0.0-phase9',
        'created_at': '2026-10-05T00:15:00Z',
        'dataset_release': 'human280_20261004',
        'canonical_manifest_sha256': manifest_sha,
        'canonical_examples_count': 280,
        'source_group_count': int(folds_df.source_sha256.nunique()),
        'training_class_distribution': {'Correct': int((y_all == 0).sum()), 'Incorrect': int((y_all == 1).sum())},
        'apparent_training_metrics': train_metrics,
        'cross_validation_performance': {
            '5fold_source_grouped_balanced_accuracy': float(best_row['balanced_accuracy']),
            '5fold_source_grouped_accuracy': float(best_row['accuracy']),
            '5fold_source_grouped_macro_f1': float(best_row['macro_f1']),
            '5fold_source_grouped_correct_recall': float(best_row['correct_recall']),
            '5fold_source_grouped_incorrect_recall': float(best_row['incorrect_recall']),
            'fold_mean_balanced_accuracy': float(best_row['fold_mean_balanced_accuracy']),
            'fold_std_balanced_accuracy': float(best_row['fold_std_balanced_accuracy']),
            'baseline_balanced_accuracy': float(baseline_res['balanced_accuracy']),
            'apparent_gain_over_baseline': float(ba_gain),
            'nested_cv_balanced_accuracy': float(nested_cand1['balanced_accuracy']),
            'nested_gain_over_baseline': float(nested_gain)
        },
        'feature_dimension': int(best_row['feature_count']),
        'feature_list': feature_names,
        'preprocessing': best_row['preprocessing'],
        'decision_rule': f"decision_score > {best_row['threshold']} => Incorrect; decision_score <= {best_row['threshold']} => Correct",
        'final_decision': FINAL_DECISION,
        'sklearn_version': '1.7.2',
        'python_version': sys.version.split()[0],
        'status': 'research_model_optimization_completed',
        'deployment_warning': 'Model optimization performed on 280-repetition canonical development set. Grouped internal validation only; NOT external validation.'
    }

    metadata_path = PHASE9_DIR / 'checkpoints' / 'final_model_v2_optimized_metadata.json'
    with open(metadata_path, 'w', encoding='utf-8') as f:
        json.dump(metadata, f, indent=2)
    print(f"Wrote optimized model metadata to {metadata_path.name}")

    # 8. Plots
    print("\n--- 8. Generating Visual Plots ---", flush=True)
    fig, ax = plt.subplots(figsize=(10, 6))
    family_summary = []
    for fam in ['Baseline_Phase3_BalancedSVM', 'RBF_SVM', 'Poly_SVM', 'LogisticRegression', 'ExtraTrees', 'HistGradientBoosting']:
        sub = df_all_results[df_all_results['model'].str.startswith(fam)]
        if len(sub) > 0:
            best_fam = sub.iloc[0]
            family_summary.append((fam.replace('_', ' '), best_fam['balanced_accuracy'] * 100, best_fam['macro_f1'] * 100, best_fam['incorrect_recall'] * 100))

    labels = [x[0] for x in family_summary]
    ba_vals = [x[1] for x in family_summary]
    f1_vals = [x[2] for x in family_summary]
    inc_rec = [x[3] for x in family_summary]

    x = np.arange(len(labels))
    width = 0.25

    rects1 = ax.bar(x - width, ba_vals, width, label='Balanced Accuracy (%)', color='#1f77b4')
    rects2 = ax.bar(x, f1_vals, width, label='Macro F1 (%)', color='#2ca02c')
    rects3 = ax.bar(x + width, inc_rec, width, label='Incorrect Recall (%)', color='#d62728')

    ax.set_ylabel('Score (%)', fontsize=12)
    ax.set_title('Phase 9: Model Family Optimization Comparison (5-Fold Source-Grouped)', fontsize=13, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=15, ha='right', fontsize=10)
    ax.set_ylim(60, 100)
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    ax.legend(loc='lower left', fontsize=10)

    for rects in [rects1, rects2, rects3]:
        for r in rects:
            h = r.get_height()
            ax.annotate(f'{h:.1f}',
                        xy=(r.get_x() + r.get_width() / 2, h),
                        xytext=(0, 3), textcoords="offset points",
                        ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    plt.savefig(PHASE9_DIR / 'plots' / 'model_sweep_comparison.png', dpi=200)
    plt.close()

    fig, ax = plt.subplots(figsize=(8, 5))
    nested_labels = ['Phase 3 Baseline\n(Frozen 5-Fold)', 'Top Candidate\n(Standard 5-Fold)', 'Top Candidate\n(Nested 5x3-Fold)', 'Candidate 2 (HGB)\n(Nested 5x3-Fold)']
    nested_scores = [base_ba * 100, best_sweep_ba * 100, nested_cand1_ba * 100, nested_cand2['balanced_accuracy'] * 100]
    colors = ['#7f7f7f', '#1f77b4', '#aec7e8', '#ff7f0e']

    bars = ax.bar(nested_labels, nested_scores, color=colors, width=0.55)
    ax.set_ylabel('Balanced Accuracy (%)', fontsize=12)
    ax.set_title('Generalization & Nested Grouped Validation Audit', fontsize=13, fontweight='bold')
    ax.set_ylim(75, 95)
    ax.grid(axis='y', linestyle='--', alpha=0.7)

    for bar in bars:
        h = bar.get_height()
        ax.annotate(f'{h:.2f}%',
                    xy=(bar.get_x() + bar.get_width() / 2, h),
                    xytext=(0, 4), textcoords="offset points",
                    ha='center', va='bottom', fontweight='bold', fontsize=10)

    plt.tight_layout()
    plt.savefig(PHASE9_DIR / 'plots' / 'nested_cv_results.png', dpi=200)
    plt.close()
    print("Generated visual plots.", flush=True)
    print("\n=== Phase 9 Optimization Sweep Complete ===", flush=True)

if __name__ == '__main__':
    main()

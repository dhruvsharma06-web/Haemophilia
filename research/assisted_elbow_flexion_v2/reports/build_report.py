"""Descriptive Phase 1 reporting only; never select/refit models from OOF outcomes."""
from pathlib import Path
import sys, json
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import ROOT, REPO, canonical, verify_config, sha, dump
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

MODELS = ['LogisticRegression', 'RandomForest', 'HistGradientBoosting', 'SVM', 'UniLSTM']
METRICS = ['accuracy', 'balanced_accuracy', 'macro_f1', 'correct_recall', 'incorrect_recall']

def table(df):
    header = '| ' + ' | '.join(map(str, df.columns)) + ' |'
    rule = '| ' + ' | '.join(['---'] * len(df.columns)) + ' |'
    body = ['| ' + ' | '.join(str(x).replace('|', '/') for x in row) + ' |' for row in df.itertuples(index=False, name=None)]
    return '\n'.join([header, rule] + body)

def main():
    lock = verify_config()
    rows, _ = canonical()
    df = pd.DataFrame(rows)
    assert json.loads((ROOT / 'reports/verification.json').read_text())['all_passed']
    sums = {n: json.loads((ROOT / 'baselines' / n / 'summary.json').read_text()) for n in MODELS}
    raw = json.loads((ROOT / 'preprocessing/raw_validation.json').read_text())
    features = json.loads((ROOT / 'features/feature_validation.json').read_text())
    extraction = pd.read_csv(ROOT / 'preprocessing/repetition_extraction_audit.csv')
    qc = pd.read_csv(ROOT / 'features/feature_quality_audit.csv')
    repairs = pd.read_csv(ROOT / 'features/repair_operations.csv')
    dist = pd.read_csv(ROOT / 'features/feature_distributions.csv')
    dataset = dict(np.load(ROOT / 'features/model_ready.npz'))
    composition = pd.read_csv(ROOT / 'splits/fold_composition.csv')
    result_rows = []
    for n, s in sums.items():
        row = {'Model': n}
        for m in METRICS:
            row[m] = f'{s["pooled_oof"][m]*100:.2f}'
        result_rows.append(row)
    result = pd.DataFrame(result_rows)
    result.to_csv(ROOT / 'reports/model_comparison_pooled.csv', index=False)
    mean_rows = [{'Model': n, **{m: f'{s["fold_mean"][m]*100:.2f} ± {s["fold_sample_std"][m]*100:.2f}' for m in METRICS}} for n, s in sums.items()]
    mean_table = pd.DataFrame(mean_rows)
    mean_table.to_csv(ROOT / 'reports/model_comparison_fold_mean_std.csv', index=False)
    fold_tables=[]
    for n in MODELS:
        ft=pd.read_csv(ROOT/'baselines'/n/'fold_metrics.csv')
        ft.insert(0,'Model',n)
        for m in METRICS:ft[m]=ft[m].map(lambda x:f'{x*100:.2f}')
        fold_tables.append(ft)
    every_fold=pd.concat(fold_tables,ignore_index=True)
    every_fold.to_csv(ROOT/'reports/all_fold_metrics.csv',index=False)
    best = max(MODELS, key=lambda n: sums[n]['pooled_oof']['balanced_accuracy'])
    best_classical = max(MODELS[:-1], key=lambda n: sums[n]['pooled_oof']['balanced_accuracy'])
    source = {n: pd.read_csv(ROOT / 'baselines' / n / 'per_source_metrics.csv') for n in MODELS}
    pred = {n: pd.read_csv(ROOT / 'baselines' / n / 'out_of_fold_predictions.csv') for n in MODELS}
    majority_purity = sum(max((g.label == 'Correct').sum(), (g.label == 'Incorrect').sum()) for _, g in df.groupby('source_sha256')) / len(df)
    single_class_sources = sum(g.label.nunique() == 1 for _, g in df.groupby('source_sha256'))
    # Source-majority purity is descriptive association, never a predictive benchmark.
    worst = source[best].sort_values('accuracy').head(8).copy()
    worst['accuracy'] = worst.accuracy.map(lambda x: f'{x*100:.2f}')
    failures = pred[best][~pred[best].is_correct].copy()
    failures = failures.merge(qc[['repetition_id', 'raw_missing_fraction', 'repaired_values', 'phase_minimum_at_endpoint']], on='repetition_id')
    failures.to_csv(ROOT / 'reports/descriptive_best_model_errors.csv', index=False)
    scalar = pd.read_csv(ROOT / 'features/scalar_features.csv')
    error_features = scalar.merge(pred[best][['repetition_id', 'label', 'is_correct']], on='repetition_id')
    medians = error_features.groupby(['label', 'is_correct'])[dataset['scalar_names'].tolist()].median().reset_index()
    medians.to_csv(ROOT / 'reports/error_feature_medians_descriptive.csv', index=False)
    hand_rows = []
    for n, s in sums.items():
        for hand, m in s['per_hand'].items():
            hand_rows.append({'Model': n, 'Hand': hand, 'N': m['n'], **{k: f'{m[k]*100:.2f}' for k in METRICS}})
    hand_table = pd.DataFrame(hand_rows)
    cm_rows = [{'Model': n, 'True Correct: predicted Correct / Incorrect': str(s['pooled_oof']['confusion_matrix'][0]), 'True Incorrect: predicted Correct / Incorrect': str(s['pooled_oof']['confusion_matrix'][1])} for n, s in sums.items()]
    train_rows = [{'Model': n, 'Mean training accuracy (%)': f'{np.mean([x["resubstitution_train_metrics"]["accuracy"] for x in s["training"]])*100:.2f}', 'Held-out source mean accuracy (%)': f'{s["source_accuracy_mean"]*100:.2f}', 'Source accuracy sample std (%)': f'{s["source_accuracy_sample_std"]*100:.2f}', 'Min / max source accuracy (%)': f'{source[n].accuracy.min()*100:.2f} / {source[n].accuracy.max()*100:.2f}'} for n, s in sums.items()]
    fig, axes = plt.subplots(1, 5, figsize=(16, 3.6), constrained_layout=True)
    for ax, n in zip(axes, MODELS):
        cm = np.array(sums[n]['pooled_oof']['confusion_matrix'])
        ax.imshow(cm, cmap='Blues', vmin=0, vmax=183)
        for i in range(2):
            for j in range(2):
                ax.text(j, i, str(cm[i, j]), ha='center', va='center', color='white' if cm[i,j] > 100 else 'black')
        ax.set_xticks([0,1], ['Correct','Incorrect'], rotation=30)
        ax.set_yticks([0,1], ['Correct','Incorrect'])
        ax.set_title(n); ax.set_xlabel('Predicted')
    axes[0].set_ylabel('Human label')
    fig.savefig(ROOT / 'reports/confusion_matrices.png', dpi=180); plt.close(fig)
    matrix = pd.DataFrame({n: source[n].set_index('video_id').accuracy for n in MODELS}).sort_index()
    fig, ax = plt.subplots(figsize=(8, 10), constrained_layout=True)
    im = ax.imshow(matrix.to_numpy()*100, vmin=0, vmax=100, cmap='RdYlGn', aspect='auto')
    ax.set_xticks(range(5), MODELS, rotation=25, ha='right')
    ax.set_yticks(range(len(matrix)), matrix.index)
    ax.set_title('Held-out accuracy by original source (%)')
    fig.colorbar(im, ax=ax)
    fig.savefig(ROOT / 'reports/per_source_accuracy.png', dpi=160); plt.close(fig)
    historical = json.loads((REPO / 'models/assisted_elbow_v2_clean_baseline_metrics.json').read_text())
    h = historical['loso_overall_metrics']
    endpoint_count = features['endpoint_phase_minimum_count']
    peak = qc[['active_peak_abs_velocity', 'opposing_peak_abs_velocity']].max()
    best_s = sums[best]
    temporal_delta = (sums['UniLSTM']['pooled_oof']['balanced_accuracy'] - sums[best_classical]['pooled_oof']['balanced_accuracy'])*100
    lines = [
      '# Assisted Elbow Flexion V2 — Phase 1 research report',
      '',
      f'Completed fresh processing and the five predeclared baselines on the approved **human280_20261004** release. The highest observed pooled balanced accuracy is **{best_s["pooled_oof"]["balanced_accuracy"]*100:.2f}% ({best})**. This is a descriptive ranking of this one experiment, not a selected production model or an unbiased estimate for a subsequently selected winner.',
      '',
      '## Dataset and extraction',
      '',
      f'Exactly 280 approved repetitions: 183 Correct / 97 Incorrect, 143 Left / 137 Right, 29 original source videos. Extraction: {int((extraction.status=="success").sum())} successful / {int((extraction.status!="success").sum())} failed repetitions. Feature construction retained all 280: 278 fully supported / 2 partial requiring fold-only imputation / 0 dropped. All 22 excluded candidates remain excluded; no historical arrays or additional examples entered this experiment.',
      '',
      f'Every source was freshly decoded and SHA-256 checked. Canonical ranges are zero-based inclusive. Raw pose inference covered {raw["unique_frames"]:,} unique original frames; overlapping approved ranges share only their source’s freshly inferred frames. Per-repetition frames total {int(extraction.extracted_frames.sum()):,}, range {int(extraction.extracted_frames.min())}–{int(extraction.extracted_frames.max())}. Original presentation timestamps determine duration and derivatives; no FPS conversion or frame stride. Images were resized to width 640 with aspect ratio preserved before inference; this resolution can limit localization precision.',
      '',
      f'Both raw image and world landmarks are saved and explicitly audited. {raw["explicit_absent_world_frames"]} unique frames have absent world poses, represented by NaNs. Core-joint mean visibility across repetitions: {extraction.core_joint_visibility_mean.mean():.4f}; lowest observed core-joint visibility: {extraction.core_joint_visibility_min.min():.4f}. Below-0.5 core-joint fraction is recorded for every repetition. The 32-frame independent-graph repeatability checks passed for every source (maximum absolute difference ≤1e-6, identical missing masks). CPU/environment replay is reproducible; cross-platform bitwise equality is not asserted.',
      '',
      'See `preprocessing/source_extraction_audit.json`, `repetition_extraction_audit.csv`, `raw_coordinate_audit.csv`, `raw_validation.json`, source decoder logs and saved `raw_landmarks/*.npz`. Sources with absence/visibility problems can be located directly in those tables; no failures are hidden.',
      '',
      '## Code audit and feature representation',
      '',
      'The audit is in `CODE_AUDIT.md`. Safely reused: anatomical landmark indices, vector-angle concept, immutable release validator and original frame timing evidence. Stale: all historical normalized arrays (including 104 revised ranges), old degree-per-frame velocity scaling, folder/old label loaders and old split/model paths. Newly implemented: fresh raw image/world pose retention, PTS derivatives, bounded recorded repairs, physical-unit features, frozen source folds and isolated baseline training.',
      '',
      '**34 scalar features** from original-frame kinematics; **128 × 11 temporal channels** derived from exactly the same fresh base signals. Exact names and order:',
      '',
      'Scalar: `' + '`, `'.join(dataset['scalar_names'].tolist()) + '`.',
      '',
      'Temporal: `' + '`, `'.join(dataset['temporal_names'].tolist()) + '`.',
      '',
      'Definitions, formulas, units and phase handling are in `../features/FEATURE_DEFINITIONS.md`. Angles are world-coordinate dot-product degrees; velocity uses actual PTS in degrees/second; flare is shoulder-axis elbow displacement divided by 3D shoulder width; bilateral asymmetry is the absolute arm difference. Torso lean and shoulder-depth ratio are view-sensitive monocular proxies, not calibrated clinical compensation/rotation measurements. Hand only selects the exercised arm; it is not a predictor or target. Phase boundary is first global active-angle minimum, an operational approximation.',
      '',
      f'Missing policy was frozen before evaluation: joint visibility ≥0.5, ≥80% valid per channel, internal bracketing gap ≤0.50s, endpoint hold ≤0.10s. {features["repetitions_repaired"]} repetitions required {features["values_repaired"]} repaired channel-values in {len(repairs)} recorded operations. Missing values before repair: {int(qc.raw_missing_values.sum())}; pre-fold NaN={features["nan"]} (33 scalar, 202 temporal), Inf={features["inf"]}; all transformed fold model inputs were explicitly checked finite. Raw and repaired channels are retained. Temporal interpolation to 128 equally spaced actual times is recorded separately from missing-gap repair. No smoothing, winsorization, outlier removal or old divisors.',
      '',
      f'Per-feature distributions and descriptive 1.5-IQR outlier counts are in `../features/feature_distributions.csv`. There are {int(dist.outside_1_5_iqr.sum())} outlying entries summed across scalar and resampled temporal tables (entries, not distinct repetitions). Largest active/opposing frame-level angular speeds: {peak.iloc[0]:.2f}/{peak.iloc[1]:.2f} deg/s. Unsmooth monocular pose jitter can inflate peak velocity and range features. {endpoint_count} repetitions have their minimum at an endpoint; their zero-duration phase speed is explicitly defined as zero and QC-flagged; a further {features["phase_unavailable_count"]} partial repetitions have unavailable phase dynamics. Phase estimates must be interpreted cautiously.',
      '',
      'All five models use mean imputation fitted solely on each outer training fold (scalar features for classical models; channel/timesteps for UniLSTM), without missingness indicators. LR/SVM: StandardScaler fit on imputed training repetitions only. Trees: imputed physical-unit scalars, no scaler. UniLSTM: StandardScaler fit on imputed training repetitions × timesteps only. Fold scalers and exact training IDs are saved and independently verified. No hand/source/subject/folder/quality flags are input features.',
      '',
      'The initial internal repair cap was 0.25s. Unsupervised extraction QC found a 0.466467-second low-visibility wrist gap in `rep_3138501c806e115527`; before any learned-model fits, the uniformly applied cap was revised to 0.50s. The original config/lock and failure evidence remain under `../provenance/protocol_before_qc_revision` and `qc_before_policy_amendment.json`, with the explicit decision in `pretraining_quality_amendment.json`. This tolerance is an engineering accommodation; interpolation can conceal true dynamics. No labels, held-out predictions or model scores informed the revision. Other gates, source folds and model settings were unchanged.',
      '',
      'Two further repetitions did not pass the unchanged validity/endpoint gates (`rep_acba12d05fb8cb1071`, `rep_d4f184058e742c55a8`). A second explicit amendment before any model fit retained their unsupported intervals as NaN, with dependent full-range summaries and phase dynamics unavailable. Training-fold mean imputation retains all 280 samples without asserting unmeasured motion or extending repair tolerances. The decision, initial residual failures and preceding protocol are saved in `pretraining_fold_imputation_amendment.json`, `qc_before_fold_imputation.json`, and `protocol_before_fold_imputation`. Mean-imputed values are statistical substitutes, not validated movement measurements.',
      '',
      '## Frozen validation and training',
      '',
      'Five-fold StratifiedGroupKFold, shuffle=True, random_state=42. Group is immutable `source_sha256`; every original source stays wholly in one held-out fold. All five models use identical fold assignments. Train/validation source intersections are explicitly empty in every fold and independently rechecked. Inherited subject metadata is preserved but identity evidence remains unverified; this is source-grouped, not verified subject-held-out validation. The same person may appear in training and validation videos.',
      '',
      table(composition),
      '',
      'Fixed predeclared parameters are in `../config.json`; the folds were frozen before inference, and the final config was frozen before any training in `../protocol_lock.json`. No held-out feature selection, threshold/calibration tuning, early stopping or checkpoint selection. No parameter search or inner validation was needed for fixed fits. Actual 183/97 imbalance retained with unweighted losses and no resampling. LR C=1; RF 500 trees/min leaf 2; HistGradientBoosting 100 iterations/7 leaves/min leaf 10; RBF SVM C=1. Scikit-learn HistGradientBoosting was available; xgboost was not required. Classical fits finished before the single UniLSTM began.',
      '',
      'UniLSTM: one unidirectional layer, hidden size 32, linear 2-class head, no fusion/dropout, 5,826 parameters, batch 32, Adam 0.001, unweighted cross-entropy, gradient clip 1, fixed 60 epochs, seeds 42+fold. CPU deterministic algorithms; final epoch only. Each held-out fold was evaluated after training. Only fold research checkpoints were saved; no full-dataset deployment fit.',
      '',
      '## Pooled out-of-fold results',
      '',
      'All values below are percentages, computed from one held-out prediction for each of the 280 repetitions. Confusion matrices use human rows / predicted columns in [Correct, Incorrect] order.',
      '',
      table(result),
      '',
      'For class-distribution context, always predicting Correct would produce 65.36% accuracy and 50.00% balanced accuracy. Every training fold has a Correct majority. UniLSTM exceeds that balanced-accuracy reference but falls below its pooled accuracy; this baseline has not demonstrated an advantage over scalar classical models.',
      '',
      table(pd.DataFrame(cm_rows)),
      '',
      f'![Confusion matrices]({(ROOT / "reports/confusion_matrices.png").as_posix()})',
      '',
      '## Fold mean ± sample standard deviation',
      '',
      'Unweighted mean over five folds, sample std (ddof=1). Folds have different sizes and class proportions, so these differ from pooled results. Each model’s `fold_metrics.csv` gives every fold, both recalls and its confusion matrix.',
      '',
      table(mean_table),
      '',
      'Every individual held-out fold (percentages; confusion matrix order [Correct, Incorrect]):',
      '',
      table(every_fold),
      '',
      '## Source stability and descriptive hand results',
      '',
      table(pd.DataFrame(train_rows)),
      '',
      'Training accuracy is resubstitution, not validation. Source accuracy weights each video equally; pooled metrics weight each repetition. Per-source balanced accuracy is undefined/null when a source contains one class; absent-class recall is null. Per-source macro-F1 uses the fixed two-class vocabulary with zero F1 for an absent class, so even a perfect single-class source has macro-F1 0.5; accuracy and the present-class recall are clearer there. Every source and its confusion matrix are retained in each model’s `per_source_metrics.csv`.',
      '',
      f'![Source accuracies]({(ROOT / "reports/per_source_accuracy.png").as_posix()})',
      '',
      table(hand_table),
      '',
      'Hand comparisons are descriptive, not a separately validated hand classifier or proof of hand equivalence. Source makeup and repeated participants confound hand differences.',
      '',
      '## Interpretation and failures',
      '',
      f'The observed leading model is {best}; the leading classical baseline is {best_classical}. UniLSTM’s pooled balanced accuracy differs from that classical result by {temporal_delta:+.2f} percentage points. This comparison tests scalar summaries against a compact temporal encoding of the same measured signals; it does not isolate architecture from representation. A higher OOF rank is reported for understanding, without selecting/refitting a winner from held-out data.',
      '',
      f'{single_class_sources}/29 sources contain a single quality class. The within-source majority label accounts for {majority_purity*100:.2f}% of examples; this is a descriptive label/source association, not a usable classifier or cross-validation score. Source grouping prevents direct repetition/frame leakage, but video setup, participant, instructed movement and monocular pose style can still correlate with labels across videos. These results cannot prove whether source effects dominate causal quality signals. Large per-source spread and the training/held-out gap indicate the remaining generalization risk.',
      '',
      'Lowest-accuracy sources for the descriptively leading model:',
      '',
      table(worst[['video_id','fold','n','Correct','Incorrect','accuracy']]),
      '',
      f'For {best}, {int((~pred[best].is_correct).sum())} repetitions are misclassified. Incorrect predicted Correct: {best_s["pooled_oof"]["confusion_matrix"][1][0]}; Correct predicted Incorrect: {best_s["pooled_oof"]["confusion_matrix"][0][1]}. `descriptive_best_model_errors.csv` links each error to its source, hand, human label and repair/phase QC; `error_feature_medians_descriptive.csv` shows summaries by label and error status. These are post-evaluation diagnostics and were not used to change features or train another model. They identify prediction failures, not their clinical cause.',
      '',
      'Further temporal architecture experiments are not yet supported as the next automatic step. Prioritize understanding source failures, monocular pose jitter/occlusion and operational phase definitions, and obtain verified participant grouping or an independent reviewed cohort before Phase 2. This experiment cannot distinguish a representation bottleneck from sample diversity/measurement limitations. No BiLSTM, attention, transformer or additional optimization was attempted.',
      '',
      '## Historical comparison and practical limits',
      '',
      f'The historical 296-repetition clean hybrid report records accuracy {h["accuracy"]:.2f}%, balanced accuracy {h["balanced_accuracy"]:.2f}%, macro-F1 {h["macro_f1"]:.2f}% under inherited-subject LOSO. The older guide’s 153-repetition LSTM records 55.56% accuracy, 51.07% balanced accuracy and 50.00% macro-F1. Those are different memberships, labels, ranges, preprocessing, model/loss and validation units. Many source/range lineages overlap historically; old scores are context, not an independent control. Fresh processing’s causal improvement cannot be established from these unmatched comparisons. Historical data were never used as inputs to new training.',
      '',
      'This is engineering research, not clinical validation. Only 29 source groups and inherited participant metadata are available. Fold variability is descriptive, not a confidence interval based on 280 independent observations. No source/subject causal conclusions or calibrated deployment confidence are claimed.',
      '',
      '## Reproduction, integrity and stop',
      '',
      f'Manifest SHA-256: `{lock["manifest_sha256"]}`. Config SHA-256: `{lock["config_sha256"]}`. Fold SHA-256: `{lock["fold_assignments_sha256"]}`. Feature data SHA-256: `{features["model_ready_sha256"]}`. Version: world_kinematics_v1_2. See `../provenance/environment.json` and `pip_freeze.txt`, decoder commands/logs, model asset hashes, feature/build/benchmark script hashes, saved scalers and checkpoint metadata. Original initialization is one-time; resume never regenerates config/folds.',
      '',
      'Commands and stage guards are in `../README.md`. `verification.json` verifies all 25 model/fold membership and scaler fits; `preservation_audit.json` verifies protected old files, raw videos and immutable release files unchanged. All outputs are confined to this research workspace.',
      '',
      '**Phase 1 ends here. No production/live/backend/Flutter integration, old checkpoint replacement, full-data production training or Phase 2 work was performed.**',
    ]
    (ROOT / 'reports/PHASE1_REPORT.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    dump(ROOT / 'reports/report_build.json', {'descriptive_best_balanced_accuracy_model': best, 'all_models': MODELS, 'phase1_complete': True, 'script_sha256': sha(__file__)})
    print(result.to_string(index=False))

if __name__ == '__main__':
    main()

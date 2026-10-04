# Assisted Elbow Flexion V2 — Phase 1 research report

Completed fresh processing and the five predeclared baselines on the approved **human280_20261004** release. The highest observed pooled balanced accuracy is **83.87% (SVM)**. This is a descriptive ranking of this one experiment, not a selected production model or an unbiased estimate for a subsequently selected winner.

## Dataset and extraction

Exactly 280 approved repetitions: 183 Correct / 97 Incorrect, 143 Left / 137 Right, 29 original source videos. Extraction: 280 successful / 0 failed repetitions. Feature construction retained all 280: 278 fully supported / 2 partial requiring fold-only imputation / 0 dropped. All 22 excluded candidates remain excluded; no historical arrays or additional examples entered this experiment.

Every source was freshly decoded and SHA-256 checked. Canonical ranges are zero-based inclusive. Raw pose inference covered 44,256 unique original frames; overlapping approved ranges share only their source’s freshly inferred frames. Per-repetition frames total 44,533, range 58–347. Original presentation timestamps determine duration and derivatives; no FPS conversion or frame stride. Images were resized to width 640 with aspect ratio preserved before inference; this resolution can limit localization precision.

Both raw image and world landmarks are saved and explicitly audited. 4 unique frames have absent world poses, represented by NaNs. Core-joint mean visibility across repetitions: 0.9824; lowest observed core-joint visibility: 0.0680. Below-0.5 core-joint fraction is recorded for every repetition. The 32-frame independent-graph repeatability checks passed for every source (maximum absolute difference ≤1e-6, identical missing masks). CPU/environment replay is reproducible; cross-platform bitwise equality is not asserted.

See `preprocessing/source_extraction_audit.json`, `repetition_extraction_audit.csv`, `raw_coordinate_audit.csv`, `raw_validation.json`, source decoder logs and saved `raw_landmarks/*.npz`. Sources with absence/visibility problems can be located directly in those tables; no failures are hidden.

## Code audit and feature representation

The audit is in `CODE_AUDIT.md`. Safely reused: anatomical landmark indices, vector-angle concept, immutable release validator and original frame timing evidence. Stale: all historical normalized arrays (including 104 revised ranges), old degree-per-frame velocity scaling, folder/old label loaders and old split/model paths. Newly implemented: fresh raw image/world pose retention, PTS derivatives, bounded recorded repairs, physical-unit features, frozen source folds and isolated baseline training.

**34 scalar features** from original-frame kinematics; **128 × 11 temporal channels** derived from exactly the same fresh base signals. Exact names and order:

Scalar: `active_min_angle`, `active_max_angle`, `active_rom`, `opposing_min_angle`, `opposing_max_angle`, `opposing_rom`, `duration`, `active_peak_abs_velocity`, `active_mean_abs_velocity`, `opposing_peak_abs_velocity`, `opposing_mean_abs_velocity`, `active_mean_flare`, `active_max_flare`, `opposing_mean_flare`, `opposing_max_flare`, `mean_angle_asymmetry`, `max_angle_asymmetry`, `mean_flare_asymmetry`, `max_flare_asymmetry`, `mean_torso_lean`, `max_torso_lean`, `range_torso_lean`, `mean_shoulder_depth_ratio`, `max_shoulder_depth_ratio`, `range_shoulder_depth_ratio`, `flexion_duration`, `extension_duration`, `flexion_fraction`, `active_start_angle`, `active_end_angle`, `flexion_excursion`, `extension_excursion`, `flexion_net_speed`, `extension_net_speed`.

Temporal: `active_angle`, `opposing_angle`, `active_flare`, `opposing_flare`, `torso_lean`, `shoulder_depth_ratio`, `active_velocity`, `opposing_velocity`, `angle_asymmetry`, `flare_asymmetry`, `elapsed_seconds`.

Definitions, formulas, units and phase handling are in `../features/FEATURE_DEFINITIONS.md`. Angles are world-coordinate dot-product degrees; velocity uses actual PTS in degrees/second; flare is shoulder-axis elbow displacement divided by 3D shoulder width; bilateral asymmetry is the absolute arm difference. Torso lean and shoulder-depth ratio are view-sensitive monocular proxies, not calibrated clinical compensation/rotation measurements. Hand only selects the exercised arm; it is not a predictor or target. Phase boundary is first global active-angle minimum, an operational approximation.

Missing policy was frozen before evaluation: joint visibility ≥0.5, ≥80% valid per channel, internal bracketing gap ≤0.50s, endpoint hold ≤0.10s. 43 repetitions required 285 repaired channel-values in 128 recorded operations. Missing values before repair: 356; pre-fold NaN=235 (33 scalar, 202 temporal), Inf=0; all transformed fold model inputs were explicitly checked finite. Raw and repaired channels are retained. Temporal interpolation to 128 equally spaced actual times is recorded separately from missing-gap repair. No smoothing, winsorization, outlier removal or old divisors.

Per-feature distributions and descriptive 1.5-IQR outlier counts are in `../features/feature_distributions.csv`. There are 10168 outlying entries summed across scalar and resampled temporal tables (entries, not distinct repetitions). Largest active/opposing frame-level angular speeds: 2623.25/1162.40 deg/s. Unsmooth monocular pose jitter can inflate peak velocity and range features. 2 repetitions have their minimum at an endpoint; their zero-duration phase speed is explicitly defined as zero and QC-flagged; a further 2 partial repetitions have unavailable phase dynamics. Phase estimates must be interpreted cautiously.

All five models use mean imputation fitted solely on each outer training fold (scalar features for classical models; channel/timesteps for UniLSTM), without missingness indicators. LR/SVM: StandardScaler fit on imputed training repetitions only. Trees: imputed physical-unit scalars, no scaler. UniLSTM: StandardScaler fit on imputed training repetitions × timesteps only. Fold scalers and exact training IDs are saved and independently verified. No hand/source/subject/folder/quality flags are input features.

The initial internal repair cap was 0.25s. Unsupervised extraction QC found a 0.466467-second low-visibility wrist gap in `rep_3138501c806e115527`; before any learned-model fits, the uniformly applied cap was revised to 0.50s. The original config/lock and failure evidence remain under `../provenance/protocol_before_qc_revision` and `qc_before_policy_amendment.json`, with the explicit decision in `pretraining_quality_amendment.json`. This tolerance is an engineering accommodation; interpolation can conceal true dynamics. No labels, held-out predictions or model scores informed the revision. Other gates, source folds and model settings were unchanged.

Two further repetitions did not pass the unchanged validity/endpoint gates (`rep_acba12d05fb8cb1071`, `rep_d4f184058e742c55a8`). A second explicit amendment before any model fit retained their unsupported intervals as NaN, with dependent full-range summaries and phase dynamics unavailable. Training-fold mean imputation retains all 280 samples without asserting unmeasured motion or extending repair tolerances. The decision, initial residual failures and preceding protocol are saved in `pretraining_fold_imputation_amendment.json`, `qc_before_fold_imputation.json`, and `protocol_before_fold_imputation`. Mean-imputed values are statistical substitutes, not validated movement measurements.

## Frozen validation and training

Five-fold StratifiedGroupKFold, shuffle=True, random_state=42. Group is immutable `source_sha256`; every original source stays wholly in one held-out fold. All five models use identical fold assignments. Train/validation source intersections are explicitly empty in every fold and independently rechecked. Inherited subject metadata is preserved but identity evidence remains unverified; this is source-grouped, not verified subject-held-out validation. The same person may appear in training and validation videos.

| fold | train_n | validation_n | train_sources | validation_sources | Correct | Incorrect | Left | Right |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 242 | 38 | 24 | 5 | 15 | 23 | 20 | 18 |
| 1 | 213 | 67 | 23 | 6 | 42 | 25 | 31 | 36 |
| 2 | 219 | 61 | 23 | 6 | 44 | 17 | 34 | 27 |
| 3 | 227 | 53 | 23 | 6 | 43 | 10 | 38 | 15 |
| 4 | 219 | 61 | 23 | 6 | 39 | 22 | 20 | 41 |

Fixed predeclared parameters are in `../config.json`; the folds were frozen before inference, and the final config was frozen before any training in `../protocol_lock.json`. No held-out feature selection, threshold/calibration tuning, early stopping or checkpoint selection. No parameter search or inner validation was needed for fixed fits. Actual 183/97 imbalance retained with unweighted losses and no resampling. LR C=1; RF 500 trees/min leaf 2; HistGradientBoosting 100 iterations/7 leaves/min leaf 10; RBF SVM C=1. Scikit-learn HistGradientBoosting was available; xgboost was not required. Classical fits finished before the single UniLSTM began.

UniLSTM: one unidirectional layer, hidden size 32, linear 2-class head, no fusion/dropout, 5,826 parameters, batch 32, Adam 0.001, unweighted cross-entropy, gradient clip 1, fixed 60 epochs, seeds 42+fold. CPU deterministic algorithms; final epoch only. Each held-out fold was evaluated after training. Only fold research checkpoints were saved; no full-dataset deployment fit.

## Pooled out-of-fold results

All values below are percentages, computed from one held-out prediction for each of the 280 repetitions. Confusion matrices use human rows / predicted columns in [Correct, Incorrect] order.

| Model | accuracy | balanced_accuracy | macro_f1 | correct_recall | incorrect_recall |
| --- | --- | --- | --- | --- | --- |
| LogisticRegression | 85.36 | 81.05 | 82.74 | 95.08 | 67.01 |
| RandomForest | 84.64 | 80.74 | 82.13 | 93.44 | 68.04 |
| HistGradientBoosting | 83.57 | 79.68 | 80.94 | 92.35 | 67.01 |
| SVM | 87.14 | 83.87 | 85.18 | 94.54 | 73.20 |
| UniLSTM | 64.29 | 59.84 | 59.96 | 74.32 | 45.36 |

For class-distribution context, always predicting Correct would produce 65.36% accuracy and 50.00% balanced accuracy. Every training fold has a Correct majority. UniLSTM exceeds that balanced-accuracy reference but falls below its pooled accuracy; this baseline has not demonstrated an advantage over scalar classical models.

| Model | True Correct: predicted Correct / Incorrect | True Incorrect: predicted Correct / Incorrect |
| --- | --- | --- |
| LogisticRegression | [174, 9] | [32, 65] |
| RandomForest | [171, 12] | [31, 66] |
| HistGradientBoosting | [169, 14] | [32, 65] |
| SVM | [173, 10] | [26, 71] |
| UniLSTM | [136, 47] | [53, 44] |

![Confusion matrices](C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/reports/confusion_matrices.png)

## Fold mean ± sample standard deviation

Unweighted mean over five folds, sample std (ddof=1). Folds have different sizes and class proportions, so these differ from pooled results. Each model’s `fold_metrics.csv` gives every fold, both recalls and its confusion matrix.

| Model | accuracy | balanced_accuracy | macro_f1 | correct_recall | incorrect_recall |
| --- | --- | --- | --- | --- | --- |
| LogisticRegression | 84.41 ± 9.92 | 79.90 ± 11.61 | 80.13 ± 11.53 | 95.60 ± 6.45 | 64.20 ± 24.20 |
| RandomForest | 84.71 ± 7.14 | 80.30 ± 6.39 | 81.33 ± 6.55 | 94.26 ± 10.18 | 66.33 ± 10.24 |
| HistGradientBoosting | 83.32 ± 4.41 | 78.53 ± 9.46 | 78.46 ± 7.50 | 93.36 ± 6.55 | 63.71 ± 21.87 |
| SVM | 86.22 ± 6.39 | 81.63 ± 10.69 | 81.84 ± 10.04 | 95.14 ± 6.13 | 68.12 ± 24.68 |
| UniLSTM | 65.07 ± 9.85 | 61.98 ± 10.99 | 60.14 ± 9.63 | 76.90 ± 13.51 | 47.05 ± 13.11 |

Every individual held-out fold (percentages; confusion matrix order [Correct, Incorrect]):

| Model | fold | n | accuracy | balanced_accuracy | macro_f1 | correct_recall | incorrect_recall | confusion_matrix |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LogisticRegression | 0 | 38 | 71.05 | 76.09 | 70.87 | 100.00 | 52.17 | [[15, 0], [11, 12]] |
| LogisticRegression | 1 | 67 | 80.60 | 78.86 | 79.09 | 85.71 | 72.00 | [[36, 6], [7, 18]] |
| LogisticRegression | 2 | 61 | 98.36 | 97.06 | 97.92 | 100.00 | 94.12 | [[44, 0], [1, 16]] |
| LogisticRegression | 3 | 53 | 86.79 | 65.00 | 69.31 | 100.00 | 30.00 | [[43, 0], [7, 3]] |
| LogisticRegression | 4 | 61 | 85.25 | 82.52 | 83.47 | 92.31 | 72.73 | [[36, 3], [6, 16]] |
| RandomForest | 0 | 38 | 81.58 | 84.78 | 81.57 | 100.00 | 69.57 | [[15, 0], [7, 16]] |
| RandomForest | 1 | 67 | 74.63 | 74.10 | 73.47 | 76.19 | 72.00 | [[32, 10], [7, 18]] |
| RandomForest | 2 | 61 | 93.44 | 88.24 | 91.16 | 100.00 | 76.47 | [[44, 0], [4, 13]] |
| RandomForest | 3 | 53 | 88.68 | 73.84 | 77.92 | 97.67 | 50.00 | [[42, 1], [5, 5]] |
| RandomForest | 4 | 61 | 85.25 | 80.54 | 82.54 | 97.44 | 63.64 | [[38, 1], [8, 14]] |
| HistGradientBoosting | 0 | 38 | 78.95 | 82.61 | 78.95 | 100.00 | 65.22 | [[15, 0], [8, 15]] |
| HistGradientBoosting | 1 | 67 | 80.60 | 79.67 | 79.42 | 83.33 | 76.00 | [[35, 7], [6, 19]] |
| HistGradientBoosting | 2 | 61 | 90.16 | 89.57 | 88.18 | 90.91 | 88.24 | [[40, 4], [2, 15]] |
| HistGradientBoosting | 3 | 53 | 84.91 | 63.84 | 67.08 | 97.67 | 30.00 | [[42, 1], [7, 3]] |
| HistGradientBoosting | 4 | 61 | 81.97 | 76.98 | 78.66 | 94.87 | 59.09 | [[37, 2], [9, 13]] |
| SVM | 0 | 38 | 76.32 | 80.43 | 76.30 | 100.00 | 60.87 | [[15, 0], [9, 14]] |
| SVM | 1 | 67 | 89.55 | 90.86 | 89.21 | 85.71 | 96.00 | [[36, 6], [1, 24]] |
| SVM | 2 | 61 | 93.44 | 88.24 | 91.16 | 100.00 | 76.47 | [[44, 0], [4, 13]] |
| SVM | 3 | 53 | 84.91 | 63.84 | 67.08 | 97.67 | 30.00 | [[42, 1], [7, 3]] |
| SVM | 4 | 61 | 86.89 | 84.79 | 85.48 | 92.31 | 77.27 | [[36, 3], [5, 17]] |
| UniLSTM | 0 | 38 | 68.42 | 72.75 | 68.33 | 93.33 | 52.17 | [[14, 1], [11, 12]] |
| UniLSTM | 1 | 67 | 47.76 | 44.57 | 44.60 | 57.14 | 32.00 | [[24, 18], [17, 8]] |
| UniLSTM | 2 | 61 | 72.13 | 69.85 | 67.96 | 75.00 | 64.71 | [[33, 11], [6, 11]] |
| UniLSTM | 3 | 53 | 69.81 | 62.21 | 59.23 | 74.42 | 50.00 | [[32, 11], [5, 5]] |
| UniLSTM | 4 | 61 | 67.21 | 60.49 | 60.59 | 84.62 | 36.36 | [[33, 6], [14, 8]] |

## Source stability and descriptive hand results

| Model | Mean training accuracy (%) | Held-out source mean accuracy (%) | Source accuracy sample std (%) | Min / max source accuracy (%) |
| --- | --- | --- | --- | --- |
| LogisticRegression | 95.35 | 84.79 | 20.83 | 30.00 / 100.00 |
| RandomForest | 99.91 | 84.84 | 19.65 | 37.50 / 100.00 |
| HistGradientBoosting | 100.00 | 83.41 | 22.25 | 28.57 / 100.00 |
| SVM | 97.75 | 86.90 | 19.27 | 30.00 / 100.00 |
| UniLSTM | 98.67 | 63.76 | 31.47 | 0.00 / 100.00 |

Training accuracy is resubstitution, not validation. Source accuracy weights each video equally; pooled metrics weight each repetition. Per-source balanced accuracy is undefined/null when a source contains one class; absent-class recall is null. Per-source macro-F1 uses the fixed two-class vocabulary with zero F1 for an absent class, so even a perfect single-class source has macro-F1 0.5; accuracy and the present-class recall are clearer there. Every source and its confusion matrix are retained in each model’s `per_source_metrics.csv`.

![Source accuracies](C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/reports/per_source_accuracy.png)

| Model | Hand | N | accuracy | balanced_accuracy | macro_f1 | correct_recall | incorrect_recall |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LogisticRegression | Left | 143 | 87.41 | 82.28 | 84.61 | 97.89 | 66.67 |
| LogisticRegression | Right | 137 | 83.21 | 79.70 | 80.86 | 92.05 | 67.35 |
| RandomForest | Left | 143 | 90.91 | 86.97 | 89.12 | 98.95 | 75.00 |
| RandomForest | Right | 137 | 78.10 | 74.36 | 75.18 | 87.50 | 61.22 |
| HistGradientBoosting | Left | 143 | 86.71 | 83.30 | 84.50 | 93.68 | 72.92 |
| HistGradientBoosting | Right | 137 | 80.29 | 76.07 | 77.26 | 90.91 | 61.22 |
| SVM | Left | 143 | 88.81 | 83.85 | 86.32 | 98.95 | 68.75 |
| SVM | Right | 137 | 85.40 | 83.66 | 83.97 | 89.77 | 77.55 |
| UniLSTM | Left | 143 | 68.53 | 62.92 | 63.30 | 80.00 | 45.83 |
| UniLSTM | Right | 137 | 59.85 | 56.54 | 56.51 | 68.18 | 44.90 |

Hand comparisons are descriptive, not a separately validated hand classifier or proof of hand equivalence. Source makeup and repeated participants confound hand differences.

## Interpretation and failures

The observed leading model is SVM; the leading classical baseline is SVM. UniLSTM’s pooled balanced accuracy differs from that classical result by -24.03 percentage points. This comparison tests scalar summaries against a compact temporal encoding of the same measured signals; it does not isolate architecture from representation. A higher OOF rank is reported for understanding, without selecting/refitting a winner from held-out data.

24/29 sources contain a single quality class. The within-source majority label accounts for 92.50% of examples; this is a descriptive label/source association, not a usable classifier or cross-validation score. Source grouping prevents direct repetition/frame leakage, but video setup, participant, instructed movement and monocular pose style can still correlate with labels across videos. These results cannot prove whether source effects dominate causal quality signals. Large per-source spread and the training/held-out gap indicate the remaining generalization risk.

Lowest-accuracy sources for the descriptively leading model:

| video_id | fold | n | Correct | Incorrect | accuracy |
| --- | --- | --- | --- | --- | --- |
| vid_03222b4845d8ef2c | 3 | 10 | 0 | 10 | 30.00 |
| vid_aa01d8740a74fd7d | 0 | 8 | 0 | 8 | 37.50 |
| vid_e61ec8fb945f06ad | 0 | 6 | 0 | 6 | 50.00 |
| vid_2f993d44fd54187e | 4 | 7 | 0 | 7 | 71.43 |
| vid_769bc27d1c4abfab | 4 | 14 | 7 | 7 | 71.43 |
| vid_1334a563691c2170 | 1 | 12 | 12 | 0 | 75.00 |
| vid_33cbe5f84565bf3d | 2 | 13 | 2 | 11 | 76.92 |
| vid_fd3e2ae78827f629 | 3 | 6 | 6 | 0 | 83.33 |

For SVM, 36 repetitions are misclassified. Incorrect predicted Correct: 26; Correct predicted Incorrect: 10. `descriptive_best_model_errors.csv` links each error to its source, hand, human label and repair/phase QC; `error_feature_medians_descriptive.csv` shows summaries by label and error status. These are post-evaluation diagnostics and were not used to change features or train another model. They identify prediction failures, not their clinical cause.

Further temporal architecture experiments are not yet supported as the next automatic step. Prioritize understanding source failures, monocular pose jitter/occlusion and operational phase definitions, and obtain verified participant grouping or an independent reviewed cohort before Phase 2. This experiment cannot distinguish a representation bottleneck from sample diversity/measurement limitations. No BiLSTM, attention, transformer or additional optimization was attempted.

## Historical comparison and practical limits

The historical 296-repetition clean hybrid report records accuracy 76.35%, balanced accuracy 75.82%, macro-F1 75.60% under inherited-subject LOSO. The older guide’s 153-repetition LSTM records 55.56% accuracy, 51.07% balanced accuracy and 50.00% macro-F1. Those are different memberships, labels, ranges, preprocessing, model/loss and validation units. Many source/range lineages overlap historically; old scores are context, not an independent control. Fresh processing’s causal improvement cannot be established from these unmatched comparisons. Historical data were never used as inputs to new training.

This is engineering research, not clinical validation. Only 29 source groups and inherited participant metadata are available. Fold variability is descriptive, not a confidence interval based on 280 independent observations. No source/subject causal conclusions or calibrated deployment confidence are claimed.

## Reproduction, integrity and stop

Manifest SHA-256: `bb4669ec492ac26cbf5b064c89390e43cac207f9785c3a5cd0003cea3c587262`. Config SHA-256: `c3634559d2761fed585d18532160f376dd606fa11603c04cbcb6cd8c3fc13c19`. Fold SHA-256: `931f660046c3684da4988b1bf8f0f3709b27d2b8bc8f6b45a70fc24b6d513e6b`. Feature data SHA-256: `c7fb405a58c2edcc9d89df7bca21be5bbe8205935c220859e3c241002993be74`. Version: world_kinematics_v1_2. See `../provenance/environment.json` and `pip_freeze.txt`, decoder commands/logs, model asset hashes, feature/build/benchmark script hashes, saved scalers and checkpoint metadata. Original initialization is one-time; resume never regenerates config/folds.

Commands and stage guards are in `../README.md`. `verification.json` verifies all 25 model/fold membership and scaler fits; `preservation_audit.json` verifies protected old files, raw videos and immutable release files unchanged. All outputs are confined to this research workspace.

**Phase 1 ends here. No production/live/backend/Flutter integration, old checkpoint replacement, full-data production training or Phase 2 work was performed.**

# Assisted Elbow Flexion V2 — Phase 2 Comprehensive Research Report

**Workspace:** [`C:\dev\Haemophilia\research\assisted_elbow_flexion_v2\phase2`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2)  
**Dataset:** [`human280_20261004`](file:///C:/dev/Haemophilia/processed_data/assisted_elbow_flexion_v2/releases/human280_20261004) (280 human-reviewed repetitions; 183 Correct, 97 Incorrect; 143 Left, 137 Right)  
**Task:** Supervised Binary Classification (`Correct` vs `Incorrect`); Hand (`Left`/`Right`) is metadata only.  
**Verification Status:** Verified via [`verify_phase2.py`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/verify_phase2.py) (129 fits checked; 2,514 protected files unchanged).

---

## 1. Executive Summary

Phase 2 investigated the generalization behavior, feature stability, error anatomy, and model sensitivity of the Assisted Elbow Flexion V2 pipeline following the frozen Phase 1 benchmark. All investigations adhered strictly to the canonical 280-repetition dataset across 29 source videos without altering raw data, canonical manifests, or production checkpoints.

### Key Discoveries of Phase 2
1. **Class-Weighted SVM is the Strongest Current Research Candidate:**
   Addressing the Phase 1 false-negative skew (26 Incorrect repetitions misclassified as Correct) via inverse class-frequency weighting (`BalancedSVM`) increased **Balanced Accuracy from 83.87% to 86.62% (+2.76%)** and **Incorrect Recall from 73.20% to 81.44% (+8.25%)**, while cutting false negatives by 30.8% (from 26 down to 18). Furthermore, it reduced cross-source accuracy dispersion (sample std decreased from 0.1927 to 0.1692) and raised the worst-source accuracy from 30.0% to 50.0%.
2. **Grouped Inner-Selection Confirms Weighting Viability (86.11% Balanced Accuracy):**
   When candidate selection was evaluated strictly inside nested outer training folds (using 3-fold `StratifiedGroupKFold` on `source_sha256` without observing outer test sources), the automated rule selected `BalancedSVM` in 4 out of 5 outer folds (and `VelocityP95` in Fold 1 under a strict source-stability penalty). This realistic selection procedure achieved **86.11% Balanced Accuracy**, **86.46% Macro-F1**, and **80.41% Incorrect Recall** on unseen outer source groups.
3. **Controlled Feature Ablations Did Not Improve Performance:**
   - **`VelocityP95`** (replacing peak angular velocities with empirical 95th-percentile velocities to mitigate differentiation noise): Balanced Accuracy dropped slightly from 83.87% to 83.32% (-0.55%), showing that peak velocity contains discriminative signal despite numerical sensitivity.
   - **`WithoutViewProxies`** (removing the 6 camera-axis torso lean and shoulder depth ratio features, which exhibited extreme source association $\eta^2 > 0.93$): Balanced Accuracy degraded sharply from 83.87% to 78.41% (-5.46%) and Incorrect Recall plummeted from 73.20% to 63.92% (-9.28%). This demonstrates that high source association alone does not mean a feature is spurious noise; removing view-proxies removes genuine posture/compensation information.
4. **Alternative Scaling (`RobustScalerSVM`) Was Ineffective:**
   Replacing `StandardScaler` with median/IQR scaling reduced Balanced Accuracy to 79.23% (-4.64%) and Incorrect Recall to 63.92% (-9.28%), showing that RBF kernel distances on these standardized features are well-calibrated under standard mean-variance scaling.
5. **Source Heterogeneity Dominates Generalization Risk:**
   A 29-partition leave-one-source-out (LOSO) diagnostic yielded a pooled Balanced Accuracy of 80.98% (down 2.88% from the 5-fold CV) and an Incorrect Recall of 69.07% (down 4.12%), despite having 28 training sources per fold. Furthermore, 24 of the 29 source videos contain only a single class (16 all-Correct, 8 all-Incorrect), creating severe source-label entanglement.
6. **No Evidence for Complex Architecture Escalation:**
   Neither temporal transformer nor BiLSTM architectures are warranted given the current dataset scale (29 videos, 280 repetitions) and strong source confounding. Data diversity and multi-angle recordings remain the primary bottleneck.

---

## 2. Frozen Phase 1 Reference

The Phase 1 SVM baseline was frozen and evaluated out-of-fold across 5 source-grouped folds (`StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)` grouped by `source_sha256`).

| Metric | Frozen Phase 1 SVM Value |
| :--- | :--- |
| **Total Evaluated Repetitions ($N$)** | 280 |
| **Accuracy** | 87.14% (0.871429, 244/280) |
| **Balanced Accuracy** | 83.87% (0.838657) |
| **Macro-F1** | 85.18% (0.851756) |
| **Correct Recall (Specificity)** | 94.54% (173/183) |
| **Incorrect Recall (Sensitivity)** | 73.20% (71/97) |
| **Confusion Matrix** | `[[173, 10], [26, 71]]` (TN=173, FP=10, FN=26, TP=71) |
| **Total Classification Errors** | 36 (10 False Positives, 26 False Negatives) |
| **Per-Source Accuracy Mean** | 86.90% (0.869035) |
| **Per-Source Accuracy Sample Std** | 0.1927 (0.192663) |
| **Per-Source Accuracy Minimum** | 30.0% (0.300000) |
| **Fold-Mean Accuracy $\pm$ Std** | 86.22% $\pm$ 6.39% |
| **Fold-Mean Balanced Accuracy $\pm$ Std** | 81.63% $\pm$ 10.69% |
| **Fold-Mean Incorrect Recall $\pm$ Std** | 68.12% $\pm$ 24.68% |

The baseline exhibits high specificity on `Correct` movement (94.54%) but a pronounced false-negative rate on `Incorrect` movement (26/97 = 26.8% missed), representing the primary clinical and statistical limitation of the unweighted model.

---

## 3. Error Analysis (The 36 Held-Out Phase 1 Errors)

Every one of the 36 classification errors produced by the frozen Phase 1 SVM was individually audited across feature values, quality control logs, landmark visibility, temporal boundaries, and decision scores. Detailed row-by-row records are preserved in [`error_analysis.csv`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/error_analysis.csv).

### 3.1 Error Breakdown by Direction
- **False Negatives (Incorrect labeled as Correct): 26 repetitions (72.2% of errors).** The model failed to detect movement execution flaws, assigning negative decision scores.
- **False Positives (Correct labeled as Incorrect): 10 repetitions (27.8% of errors).** Clean repetitions were penalized as erroneous.

### 3.2 Decision Score Margin Distribution
The signed SVM decision scores ($f(x)$, where $f(x) > 0 \implies \text{Incorrect}$) reflect model margin distance:
- **Near-Margin Errors ($|f(x)| \le 0.25$):** 13 errors (36.1% of errors). These cases lie directly along the hyperplane boundary and represent boundary sensitivity rather than gross misclassifications.
- **Moderate Margin ($0.25 < |f(x)| \le 0.75$):** 17 errors (47.2%).
- **High-Confidence Errors ($|f(x)| > 0.75$):** 6 errors (16.7%). These represent strong feature conflicts with the training fold distribution.

### 3.3 Quality Control and Repair Audit
- **Landmark Repair Frequency:** Only **4 of the 36 errors (11.1%)** involved recorded pose repairs (`rep_496c495105f1f840b1` [24 values], `rep_27f29611af9d868d70` [1 value], `rep_c4774628dd2fa04641` [8 values], `rep_25bfdbda7925e0e1a4` [1 value]). All remaining 32 error repetitions had zero repaired values.
- **Partial Representations:** **0 of the 36 errors** involved truncated or partial sequence representations.
- **Phase Minimum at Endpoints:** **0 of the 36 errors** had a phase minimum located at the start or end frame, confirming that segmentation boundaries did not truncate the flexion apex.
- **Average Core Joint Visibility:** Across the 36 error cases, mean core landmark visibility was $0.978 \pm 0.015$, confirming that pose tracking confidence was generally high.

### 3.4 Descriptive Failure Mechanisms
Audit tagging categorized the observed failure characteristics without attributing clinical diagnoses:

| Primary Descriptive Category | Errors Flagged | Key Characteristics |
| :--- | :---: | :--- |
| **High Mean Angular Speed** | 8 | Rapid movement pacing exceeding training class references; elevated angular velocities. |
| **High Torso / View Proxy** | 7 | Elevated `mean_torso_lean` or `shoulder_depth_ratio` driven by camera obliquity or posture shifts. |
| **Overlapping Biomechanical Signal** | 6 | Feature values falling directly within the interquartile range (IQR) overlap of both classes. |
| **Shallow Measured Flexion** | 5 | Incomplete flexion apex (`active_min_angle` > 90°), creating ambiguity between incomplete exercise and poor execution. |
| **Visibility / Repair Interventions** | 4 | Minor landmark interpolation or momentary joint occlusions during arm crossover. |
| **Jitter-Like Angular Spike** | 3 | Peak-to-p95 angular velocity ratio > 4.0; isolated frame derivative jumps. |
| **High Flare Proxy** | 3 | Elevated elbow abduction relative to shoulder width. |

---

## 4. Source Failure Analysis (All 29 Sources)

The canonical dataset originates from 29 distinct source video files. Full source-level diagnostics are compiled in [`source_failure_analysis.csv`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/source_failure_analysis.csv).

### 4.1 Source Composition and Partition Imbalance
- **Single-Class Sources: 24 of 29 videos (82.8%)**
  - 16 videos contain exclusively `Correct` repetitions (161 repetitions).
  - 8 videos contain exclusively `Incorrect` repetitions (63 repetitions).
- **Mixed-Class Sources: Only 5 of 29 videos (17.2%)**
  - These 5 videos contain 56 repetitions (22 `Correct`, 34 `Incorrect`).
- **Subject Identity Mapping:** Videos are tagged with 5 inherited subject IDs (`person1` through `person5`). However, as established in Phase 1, subject identity mapping was inherited and has not been independently verified (subject verification checkboxes remain unconfirmed).

### 4.2 Source-Level Accuracy Distribution
Under the frozen Phase 1 SVM:
- **Mean Source Accuracy:** 86.90%
- **Sample Standard Deviation:** 19.27%
- **Accuracy Range:** 30.0% to 100.0%
- **Perfect Accuracy (100%):** 16 of 29 sources.
- **Problem Sources (< 70% Accuracy):**
  - `vid_03222b4845d8ef2c` (10 repetitions, all `Incorrect`): Accuracy **30.0%** (7 false negatives). Exhibited high shoulder depth ratio shift (+3.52 robust SD) and restricted ROM.
  - `vid_aa01d8740a74fd7d` (8 repetitions, all `Incorrect`): Accuracy **37.5%** (5 false negatives). Characterized by high torso lean (+1.78 robust SD) and shoulder depth ratio (+1.85 robust SD).
  - `vid_e61ec8fb945f06ad` (6 repetitions, all `Incorrect`): Accuracy **50.0%** (3 false negatives).
  - `vid_b568ee5702581fd9` (8 repetitions, 4 Correct / 4 Incorrect): Accuracy **62.5%** (3 false negatives).

### 4.3 Mixed-Class vs. Single-Class Performance
Evaluating performance separately on mixed-class vs. single-class sources reveals the impact of source partition:

| Model | Subset | Sources | N | Accuracy | Balanced Acc | Correct Recall | Incorrect Recall |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **FrozenPhase1SVM** | Mixed Sources | 5 | 56 | 80.36% | 81.42% | 86.36% | 76.47% |
| **FrozenPhase1SVM** | Single-Class Sources | 24 | 224 | 88.84% | 83.54% | 95.65% | 71.43% |
| **BalancedSVM** | Mixed Sources | 5 | 56 | **85.71%** | **85.03%** | 81.82% | **88.24%** |
| **BalancedSVM** | Single-Class Sources | 24 | 224 | **88.84%** | **85.47%** | 93.17% | **77.78%** |

On mixed sources where both classes coexist within the exact same recording session, `BalancedSVM` achieves 88.24% Incorrect Recall (vs 76.47% for the baseline) and 85.03% Balanced Accuracy.

---

## 5. Feature Robustness Analysis

The 34 scalar features and 11 temporal representations were audited for physical interpretation, camera-view invariance, numerical stability, and source confounding. The results are preserved in [`feature_robustness.csv`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/feature_robustness.csv).

### 5.1 Evidence Behind the Two Focused Feature Hypotheses

#### A. Extreme Peak Angular Velocities
- Differentiation of estimated 3D joint coordinates against presentation timestamps (PTS) produces high-frequency numerical artifacts.
- In the active channel, the median ratio of peak velocity to 95th-percentile velocity ($\text{peak} / p95$) was **1.713**, with individual repetitions reaching an extreme ratio of **9.221** (e.g., peak velocity 1591.4°/s vs p95 of 172.6°/s in `rep_9ff0bc77263dfff528`).
- This motivated testing **`VelocityP95`**, replacing peak velocity with time-weighted empirical 95th-percentile velocity.

#### B. Camera-Axis Torso and Shoulder Depth Proxies
- Several engineered features rely on coordinate projections along the camera optical axis:
  - `mean_torso_lean`, `max_torso_lean`, `range_torso_lean`
  - `mean_shoulder_depth_ratio`, `max_shoulder_depth_ratio`, `range_shoulder_depth_ratio`
- Analysis of variance revealed massive source association:
  - `mean_torso_lean`: $\eta^2 = 0.9328$ (**0.9327 after subtracting class-specific means**).
  - `max_torso_lean`: $\eta^2 = 0.8236$ (0.8226 after class-mean adjustment).
  - `range_torso_lean`: $\eta^2 = 0.6901$ (0.6877 after class-mean adjustment).
  - `max_shoulder_depth_ratio`: $\eta^2 = 0.5773$ (0.5713 after class-mean adjustment).
- This extreme source-dependence motivated testing **`WithoutViewProxies`** (dropping all 6 view-sensitive features).

### 5.2 Controlled Comparison Results for Feature Variants

| Model Variant | Feat Dims | Accuracy | Balanced Acc | Macro-F1 | Correct Rec | Incorrect Rec | $\Delta$ Balanced Acc |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **FrozenPhase1SVM** (Baseline) | 34 | 87.14% | 83.87% | 85.18% | 94.54% | 73.20% | Ref |
| **VelocityP95** | 34 | 86.43% | 83.32% | 84.44% | 93.44% | 73.20% | -0.55% |
| **WithoutViewProxies** | 28 | 82.86% | 78.41% | 79.86% | 92.90% | 63.92% | -5.46% |

### 5.3 Scientific Conclusions on Features
1. **Peak Velocities Retain Discriminative Signal:** Replacing peaks with p95 velocities slightly diminished classification accuracy (-0.55% BA). While peaks are noisy, extreme velocity bursts often correspond to uncontrolled ballistic movements characteristic of incorrect repetitions.
2. **View-Sensitive Features Must NOT Be Discarded:** Dropping the torso and shoulder depth proxies caused a severe 5.46% collapse in Balanced Accuracy and a 9.28% drop in Incorrect Recall. Even though these features correlate with camera setup, they also capture genuine trunk sway, compensatory leaning, and torso rotation. **High source association alone does not constitute proof of spurious artifact.**

---

## 6. Controlled Model Experiments

Four controlled modifications and one nested selection procedure were evaluated using identical 5-fold source-grouped splits and training-only preprocessing. Full results are stored in [`all_results.csv`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/experiments/all_results.csv).

| Model / Procedure | Acc | Bal Acc | Macro-F1 | Corr Rec | Incorr Rec | Confusion Matrix | Source Std | Worst Source | $\Delta$ Bal Acc |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **FrozenPhase1SVM** | 87.14% | 83.87% | 85.18% | 94.54% | 73.20% | `[[173, 10], [26, 71]]` | 0.1927 | 30.0% | Ref |
| **BalancedSVM** | **88.21%** | **86.62%** | **86.89%** | 91.80% | **81.44%** | `[[168, 15], [18, 79]]` | **0.1692** | **50.0%** | **+2.76%** |
| **InnerSelectedProcedure** | 87.86% | 86.11% | 86.46% | 91.80% | 80.41% | `[[168, 15], [19, 78]]` | 0.1676 | 50.0% | **+2.24%** |
| **VelocityP95** | 86.43% | 83.32% | 84.44% | 93.44% | 73.20% | `[[171, 12], [26, 71]]` | 0.1985 | 30.0% | -0.55% |
| **RobustScalerSVM** | 83.93% | 79.23% | 80.93% | 94.54% | 63.92% | `[[173, 10], [35, 62]]` | 0.2202 | 30.0% | -4.64% |
| **WithoutViewProxies** | 82.86% | 78.41% | 79.86% | 92.90% | 63.92% | `[[170, 13], [35, 62]]` | 0.2433 | 20.0% | -5.46% |

---

## 7. Class-Weighted SVM (`BalancedSVM`)

`BalancedSVM` applies inverse class-frequency weighting ($w_c = \frac{N}{2 \cdot N_c}$) fitted strictly on training-fold class counts within each fold. All 34 original features and `StandardScaler` were retained unchanged.

### Detailed Comparison Against Frozen SVM

```
                      FrozenPhase1SVM         BalancedSVM            Delta
Accuracy:                 87.14%                88.21%              +1.07%
Balanced Accuracy:        83.87%                86.62%              +2.76%
Macro-F1:                 85.18%                86.89%              +1.71%
Correct Recall:           94.54%                91.80%              -2.73% (5 fewer correct detected)
Incorrect Recall:         73.20%                81.44%              +8.25% (8 more incorrect detected)
False Negatives:            26                    18                -8 (-30.8%)
False Positives:            10                    15                +5 (+50.0%)
Source Accuracy Std:      0.1927                0.1692              -0.0234 (more consistent)
Minimum Source Acc:       30.0%                 50.0%               +20.0% (raised floor)
Fold Mean Bal Acc:        81.63%                85.50%              +3.87%
Fold Std Bal Acc:         0.1069                0.0862              -0.0207 (lower fold variance)
```

### Why Class-Weighted SVM is a Genuinely Stronger Candidate
1. **Clinical Sensitivity:** In therapeutic monitoring, failing to identify an incorrectly performed exercise (false negative) is typically more detrimental than flagging a marginal exercise for review. Reducing false negatives from 26 to 18 provides substantial clinical value.
2. **Dispersion Reduction:** Rather than achieving higher accuracy on easy sources at the expense of hard sources, `BalancedSVM` decreased the standard deviation across sources (0.1692 vs 0.1927) and elevated the worst source performance from 30% to 50%.
3. **Non-Tuned Formulation:** The class weights were computed analytically from class proportions; no hyperparameters were tuned against validation data.

---

## 8. Grouped Inner-Selection Procedure

To guard against selection bias, an inner selection protocol was implemented in [`experiments.py`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/experiments.py) and audited in [`experiments/inner_selections.json`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/experiments/inner_selections.json).

### Selection Protocol
- For each outer fold $k \in \{0, 1, 2, 3, 4\}$, the outer training set (comprising ~224 repetitions from ~23 sources) was partitioned using `StratifiedGroupKFold(n_splits=3, shuffle=True, random_state=42 + 100*k)` grouped by `source_sha256`.
- **Outer test sources were strictly invisible.**
- Candidates had to satisfy inner eligibility: inner Balanced Accuracy, Macro-F1, and Incorrect Recall $\ge$ inner reference, and inner per-source standard deviation $\le \text{reference} + 0.02$.
- The winning inner candidate was then trained on the full outer training set and evaluated on the held-out outer fold.

### Outer Fold Selections and Results

| Outer Fold | Eligible Inner Candidates | Selected Candidate | Rationale | Outer Bal Acc |
| :---: | :--- | :--- | :--- | :---: |
| **0** | `VelocityP95`, `BalancedSVM` | **`BalancedSVM`** | Highest inner BA (83.37% vs 67.67% P95) | 88.54% |
| **1** | `VelocityP95` | **`VelocityP95`** | `BalancedSVM` exceeded stability limit (source std 0.2472 > 0.2311) | 86.88% |
| **2** | `VelocityP95`, `WithoutViewProxies`, `BalancedSVM` | **`BalancedSVM`** | Highest inner BA (84.58%) | 90.91% |
| **3** | `VelocityP95`, `BalancedSVM` | **`BalancedSVM`** | Highest inner BA (84.58%) | 94.64% |
| **4** | `VelocityP95`, `BalancedSVM` | **`BalancedSVM`** | Highest inner BA (82.39%) | 69.58% |

### Overall Nested Result
- **Pooled Balanced Accuracy: 86.11%** (0.861078)
- **Pooled Accuracy: 87.86%** (246/280)
- **Macro-F1: 86.46%**
- **Incorrect Recall: 80.41%** (78/97)
- **Correct Recall: 91.80%** (168/183)

This proves that the advantage of class-weighting survives nested cross-validation without leakage.

---

## 9. Leave-One-Source-Out (LOSO) Diagnostic

A 29-partition leave-one-source-out evaluation was executed using the unchanged original Phase 1 SVM specification. Full details are recorded in [`source_leave_one_out_results.csv`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/source_leave_one_out_results.csv) and [`experiments/source_leave_one_out_summary.json`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/experiments/source_leave_one_out_summary.json).

### Diagnostic Metrics

| Metric | 5-Fold Stratified Group CV | 29-Fold Leave-One-Source-Out | Difference |
| :--- | :---: | :---: | :---: |
| **Training Sources per Partition** | ~23 sources | 28 sources | +5 sources |
| **Accuracy** | 87.14% | 84.64% | -2.50% |
| **Balanced Accuracy** | 83.87% | 80.98% | **-2.88%** |
| **Macro-F1** | 85.18% | 82.24% | -2.94% |
| **Correct Recall** | 94.54% | 92.90% | -1.64% |
| **Incorrect Recall** | 73.20% | 69.07% | **-4.12%** |
| **Confusion Matrix** | `[[173, 10], [26, 71]]` | `[[170, 13], [30, 67]]` | +4 FN, +3 FP |
| **Prediction Flips** | — | 11 repetitions | — |
| **Source Accuracy Sample Std** | 0.1927 | 0.2034 | +0.0107 |

### Generalization Implications
In conventional machine learning, increasing the training set size (from 23 to 28 sources) typically improves performance. Here, performance **degraded** (Balanced Accuracy fell from 83.87% to 80.98%, and Incorrect Recall fell below 70%).

This confirms that:
1. Model boundaries are sensitive to the specific composition of training sources.
2. The 5-fold stratification happened to provide balanced representation of specific recording styles across folds; isolating single sources exposes out-of-distribution shifts.
3. The pipeline cannot yet be assumed to generalize seamlessly to completely unseen camera configurations or participants.

---

## 10. Hand Analysis (Descriptive Metadata Only)

Hand metadata (`Left` vs `Right`) was tracked descriptively across all 280 repetitions. In accordance with clinical requirements, hand is not a prediction target.

### Distribution Across Canonical Set
- **Left Hand:** 143 repetitions (95 `Correct`, 48 `Incorrect`)
- **Right Hand:** 137 repetitions (88 `Correct`, 49 `Incorrect`)

### Model Performance Stratified by Hand

| Model | Hand | N | Accuracy | Balanced Acc | Macro-F1 | Correct Rec | Incorrect Rec |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **FrozenPhase1SVM** | Left | 143 | 88.81% | 83.85% | 86.32% | 98.95% | 68.75% |
| **FrozenPhase1SVM** | Right | 137 | 85.40% | 83.66% | 83.97% | 89.77% | 77.55% |
| **BalancedSVM** | Left | 143 | **91.61%** | **89.05%** | **90.27%** | 96.84% | **81.25%** |
| **BalancedSVM** | Right | 137 | **84.67%** | **84.00%** | **83.53%** | 86.36% | **81.63%** |
| **InnerSelectedProcedure** | Left | 143 | 91.61% | 89.05% | 90.27% | 96.84% | 81.25% |
| **InnerSelectedProcedure** | Right | 137 | 83.94% | 82.98% | 82.68% | 86.36% | 79.59% |

### Key Observations
- In the frozen baseline, Left-hand performance had very high specificity (98.95%) but low Incorrect recall (68.75%).
- `BalancedSVM` dramatically improved Left-hand Incorrect recall from 68.75% to 81.25% (+12.50%), raising Left Balanced Accuracy to 89.05%.
- Right-hand performance under `BalancedSVM` also improved Incorrect recall from 77.55% to 81.63%, achieving a consistent ~81.4% sensitivity across both hands.

---

## 11. Study Limitations

1. **Strong Source/Label Confounding:** 24 of the 29 source videos (82.8%) contain only a single label. When a video contains only `Correct` repetitions, camera artifacts and movement quality are mathematically entangled.
2. **Limited Source Sample Size:** With only 29 videos, effective degrees of freedom at the cluster level are small, as shown by the leave-one-source-out diagnostic.
3. **Unverified Subject Identities:** The nominal subject IDs (`person1` through `person5`) were inherited from legacy directory structures and lack independent verification. True inter-subject variability cannot be separated from recording setup.
4. **Monocular Pose Estimation Constraints:** 3D coordinates generated from single monocular RGB cameras suffer from depth ambiguity, perspective foreshortening, and self-occlusion during flexion crossover.
5. **Setup Variation:** Differences in camera height, distance, obliquity, and frame rate (30 fps vs 60 fps) introduce non-trivial distribution shifts.
6. **No External Prospective Cohort:** All data originate from the initial recording sets. No prospective, independently recorded validation set exists.
7. **No Direct Clinical Validation:** Error categories and boundary shifts are descriptive statistical properties; they do not establish medical or physical therapy validity.

---

## 12. Phase 2 Conclusion

1. **Phase 2 Research Goal Achieved:** The error behavior, feature vulnerabilities, and model sensitivity of Assisted Elbow Flexion V2 have been systematically audited and documented.
2. **Primary Candidate Selected:** `BalancedSVM` (SVM with training-fold class frequency balancing) is the strongest candidate. It delivers:
   - **86.62% Balanced Accuracy** (+2.76% over baseline)
   - **81.44% Incorrect Recall** (+8.25% over baseline, reducing missed errors from 26 to 18)
   - **Reduced source variability** (std 0.1692 vs 0.1927; worst source 50% vs 30%)
   - **Confirmed nested validation performance** (86.11% Balanced Accuracy under grouped inner selection).
3. **Feature Modifications Rejected:** Neither peak-to-p95 velocity replacement nor view-proxy removal improved generalization. The full 34-feature representation with `StandardScaler` remains the optimal representation.
4. **Complex Neural Architectures Remain Unjustified:** Given the pronounced source clustering and 280-repetition volume, sequence-level deep learning (Transformers, BiLSTMs) carries extreme overfitting risk without resolving the fundamental source-confounding bottleneck.

---

## 13. Evidence-Based Phase 3 Recommendations

For any subsequent research phase (Phase 3), the following prioritized roadmap is recommended:

1. **Do NOT Deploy or Overwrite Production Checkpoints Yet:** The current deployment model in production must remain untouched until multi-center / multi-subject validation is performed.
2. **Acquire Diverse, Multi-Class Source Video:** The highest-leverage investment is gathering new recordings where multiple individuals perform both correct and incorrect repetitions under varied, controlled camera viewpoints.
3. **Evaluate Decision Threshold Calibration:** Since `BalancedSVM` functions by shifting the hyperplane margin, formal ROC/PR threshold tuning under nested source-grouped CV should be explored before altering feature sets.
4. **Preserve View-Sensitive Features with Domain Adaptation:** Instead of eliminating torso and shoulder depth proxies (which degrades performance by 5.5%), investigate explicit feature normalization (e.g., subtracting participant rest-pose orientation) to decouple posture from camera placement.
5. **Implement Stricter Boundary Verification Protocols:** Standardize transition padding to prevent start/end acceleration bursts from entering velocity calculations.

---

## Verification & Artifact Preservation Sign-off

- **Canonical Manifest:** Verified 280 repetitions ([`processed_data/assisted_elbow_flexion_v2/releases/human280_20261004`](file:///C:/dev/Haemophilia/processed_data/assisted_elbow_flexion_v2/releases/human280_20261004)).
- **Excluded Candidates:** 22 excluded repetitions strictly excluded.
- **Protected Files Check:** 2,514 protected repository files verified unchanged via SHA-256 audit.
- **Fits Checked:** 129 new model fits audited for strict fit boundaries and zero training-validation leakage.
- **Verification Script:** Executed and passed with 0 exit code ([`verify_phase2.py`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase2/verify_phase2.py)).

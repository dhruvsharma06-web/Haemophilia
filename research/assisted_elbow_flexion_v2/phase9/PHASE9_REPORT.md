# Phase 9 — Model Optimization Report
**Assisted Elbow Flexion V2 Research Pipeline**

**Date:** 2026-10-05  
**Workspace:** `research/assisted_elbow_flexion_v2/phase9/`  
**Dataset Release:** `human280_20261004` (SHA-256: `bb4669ec492ac26cbf5b064c89390e43cac207f9785c3a5cd0003cea3c587262`)  
**Evaluation Protocol:** 5-Fold Source-Grouped Cross-Validation (`StratifiedGroupKFold`, `random_state=42`, grouped by `source_sha256`)  
**Nested Protocol:** 5 Outer Folds × 3 Inner Folds Source-Grouped Cross-Validation  
**Primary Metric:** Balanced Accuracy  
**Final Status:** **B — No Meaningful Improvement** (Keep Phase 3 BalancedSVM)

---

## 1. Executive Summary

Phase 9 was executed as a time-bounded model optimization phase operating strictly within the canonical 280-repetition dataset. The objective was to determine whether an alternative classifier architecture, hyperparameter configuration, fold-internal preprocessing pipeline, feature subset, or decision threshold could achieve a defensible, reproducible improvement ($\ge 1.0$ percentage point in Balanced Accuracy) over the frozen Phase 3 `BalancedSVM` baseline while surviving strict nested grouped cross-validation.

### Summary of Outcomes:
- **Baseline Model (Phase 3 BalancedSVM):**
  - **Balanced Accuracy:** **86.62%** (Fold mean: $85.50\% \pm 8.62\%$)
  - **Overall Accuracy:** **88.21%** (247 / 280)
  - **Macro F1:** **86.89%**
  - **Correct Recall (Class 0):** **91.80%** (168 / 183)
  - **Incorrect Recall (Class 1):** **81.44%** (79 / 97)
  - **Confusion Matrix:** `[[168, 15], [18, 79]]`
- **Candidate Model Exploration (509 Evaluated Configurations):**
  - Swept RBF SVM, Polynomial SVM, Logistic Regression, ExtraTrees, and HistGradientBoosting across Pipelines A (mean + StandardScaler), B (median + StandardScaler), and C (mean + RobustScaler).
  - In the unnested 5-fold outer sweep, the top-performing candidate was an **RBF SVM** ($C=1.0, \gamma=0.04$, `class_weight='balanced'`, Pipeline B) achieving an apparent Balanced Accuracy of **87.65%** (+1.03 pp over baseline, +2 incorrect detections).
- **Strict Grouped Nested CV Confirmation (Outer 5-fold, Inner 3-fold):**
  - When model selection decisions were strictly isolated inside inner training folds, the candidate RBF SVM space achieved an outer nested Balanced Accuracy of **85.38%** (a drop of **-1.24 pp** below the baseline's 86.62%).
  - HistGradientBoosting achieved a nested Balanced Accuracy of **79.47%** (-7.15 pp below baseline).
  - The apparent +1.03 pp gain observed in the outer sweep did not survive nested validation because inner folds selected disparate hyperparameters ($C \in \{0.5, 1.0, 4.0\}$, $\gamma \in \{\text{scale}, 0.02, 0.04\}$) across different source holdouts, demonstrating that hyperparameter fine-tuning overfits source clusters.
- **Formal Decision:**
  - **B — No Meaningful Improvement**
  - In accordance with the pre-registered decision rule, **THE EXISTING PHASE 3 BALANCED SVM IS RETAINED AS THE AUTHORITATIVE MODEL**.

---

## 2. Model Family Exploration & Preprocessing Sweep

All 509 configurations were evaluated using identical 5 source-grouped folds. Preprocessing transformations and feature selections were fit strictly on the training partitions of each fold to prevent data leakage.

### Table 1: Model Family Performance Comparison (Top Configuration per Family)

| Model Architecture | Hyperparameters | Preprocessing | Feature Count | Threshold | Balanced Accuracy | Accuracy | Macro F1 | Correct Recall | Incorrect Recall | Fold Mean BA | Runtime (s) |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **RBF SVM (Top Candidate)** | $C=1.0, \gamma=0.04, w=\text{bal}$ | Pipeline B (median+std) | 34 | 0.0 | **87.65%** | 88.93% | 87.75% | 91.80% | 83.51% | $87.50\% \pm 5.49\%$ | 0.03 |
| **Baseline Phase 3 SVM** | $C=1.0, \gamma=\text{scale}, w=\text{bal}$ | Pipeline A (mean+std) | 34 | 0.0 | **86.62%** | 88.21% | 86.89% | 91.80% | 81.44% | $85.50\% \pm 8.62\%$ | 0.03 |
| **ExtraTrees** | $N=300, d=\text{None}, msl=1, w=\text{bal}$ | Pipeline A (mean+std) | 34 | 0.0 | **86.35%** | 87.86% | 86.53% | 91.26% | 81.44% | $84.97\% \pm 9.53\%$ | 1.45 |
| **Polynomial SVM** | $\text{deg}=2, C=0.5, \gamma=\text{scale}, w=\text{bal}$ | Pipeline A (mean+std) | 34 | 0.0 | **85.34%** | 86.43% | 85.12% | 89.62% | 81.05% | $84.34\% \pm 8.63\%$ | 0.02 |
| **HistGradientBoosting** | $lr=0.03, \text{iter}=200, \text{nodes}=7, l_2=1.0$ | Pipeline A (mean+std) | 34 | 0.0 | **84.81%** | 86.79% | 85.18% | 92.35% | 77.32% | $84.14\% \pm 7.91\%$ | 0.16 |
| **Logistic Regression** | $C=1.0, \text{penalty}=l_2, w=\text{bal}$ | Pipeline C (mean+robust) | 34 | 0.0 | **84.05%** | 86.07% | 84.33% | 91.80% | 76.29% | $83.67\% \pm 8.60\%$ | 0.02 |

### Key Observations from Model Sweeps:
1. **RBF Kernel Superiority:** RBF SVM configurations consistently outperformed linear (Logistic Regression), polynomial (degree 2/3), and tree-based architectures (ExtraTrees, HistGradientBoosting) in both balanced accuracy and incorrect-class sensitivity.
2. **Preprocessing Invariance:** Moving from mean imputation (Pipeline A) to median imputation (Pipeline B) yielded identical predictions for the baseline $C=1.0, \gamma=\text{scale}$ model (86.62% BA), because the canonical feature dataset contains low overall missingness. RobustScaler (Pipeline C) slightly compressed extreme kinematics, helping $C=1.0, \gamma=0.08$ (87.14% BA) but showing no systemic advantage over standard z-score normalization.
3. **Tree-Based Models:** ExtraTrees achieved 86.35% BA with 300 trees and balanced weights, but displayed higher cross-fold variance ($\pm 9.53\%$) and slower inference throughput than the SVM. HistGradientBoosting plateaued at 84.81% BA.

---

## 3. Fold-Internal Feature Selection Audit

To determine if feature dimensionality reduction could mitigate source clustering, ANOVA F-value feature ranking (`f_classif`) was executed strictly inside each fold's training split for top candidate models.

### Table 2: Feature Selection Results (Fold-Internal Selection vs Full 34)

| Model Base | Feature Count ($k$) | Balanced Accuracy | Overall Accuracy | Macro F1 | Incorrect Recall | Correct Recall |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **RBF SVM ($C=1, \gamma=0.04$)** | **34 (Full)** | **87.65%** | **88.93%** | **87.75%** | **83.51%** | **91.80%** |
| RBF SVM ($C=1, \gamma=0.04$) | 30 | 86.59% | 87.86% | 86.59% | 82.47% | 90.71% |
| RBF SVM ($C=1, \gamma=0.04$) | 28 | 85.50% | 86.79% | 85.39% | 81.44% | 89.62% |
| RBF SVM ($C=1, \gamma=0.04$) | 24 | 84.41% | 85.71% | 84.18% | 80.41% | 88.52% |
| **Baseline Phase 3 SVM** | **34 (Full)** | **86.62%** | **88.21%** | **86.89%** | **81.44%** | **91.80%** |

**Conclusion on Features:** Reducing the feature space from 34 to 30, 28, or 24 resulted in a monotonic drop in Balanced Accuracy and Incorrect Recall across all folds. The full 34 biomechanical kinematic features capture orthogonal aspects of execution (ROM, velocity, torso lean, asymmetry, flare) that are vital for distinguishing pathology. **Full 34 features must be preserved.**

---

## 4. Nested Decision Threshold Optimization

The baseline decision rule uses a natural sign threshold ($score > 0.0 \Rightarrow \text{Incorrect}$). To evaluate whether threshold calibration could improve performance without test leakage, an inner 3-fold grouped cross-validation was conducted inside each outer fold:
1. Inner scores were calculated across outer-training folds.
2. The threshold maximizing inner Balanced Accuracy was selected from $\{-0.50, -0.25, -0.10, 0.0, +0.10, +0.25, +0.50\}$.
3. The chosen threshold was frozen and applied to the completely unseen outer validation fold.

### Table 3: Nested Decision Threshold Outcomes

| Model | Threshold Strategy | Chosen Thresholds per Outer Fold | Balanced Accuracy | Accuracy | Macro F1 | Incorrect Recall | Correct Recall |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Baseline Phase 3 SVM** | **Fixed ($0.0$)** | `[0.0, 0.0, 0.0, 0.0, 0.0]` | **86.62%** | **88.21%** | **86.89%** | **81.44%** | **91.80%** |
| Baseline Phase 3 SVM | Nested Inner Selection | `[-0.10, 0.00, -0.25, 0.00, -0.50]` | 86.01% | 86.79% | 85.58% | 83.51% | 88.52% |

**Conclusion on Thresholds:** Nested threshold selection shifted decision boundaries aggressively toward negative scores on Fold 0 (-0.10), Fold 2 (-0.25), and Fold 4 (-0.50) in an attempt to capture borderline Incorrect repetitions. While Incorrect Recall slightly rose to 83.51%, Correct Recall fell from 91.80% to 88.52%, reducing overall Balanced Accuracy from 86.62% to 86.01%. The fixed threshold of **$0.0$** is optimal and robust against source shifts.

---

## 5. Strict Nested Grouped CV Confirmation

To produce uncompromised evidence of whether the top candidate's apparent gain (+1.03 pp) represents genuine generalization or fold-specific tuning, a full **nested grouped cross-validation** was executed:
- **Outer Loop:** 5-fold `StratifiedGroupKFold` (random_state=42, grouped by `source_sha256`).
- **Inner Loop:** 3-fold `StratifiedGroupKFold` on the outer training set.
- All model selection decisions (hyperparameters $C, \gamma, \text{class\_weight}$) were determined exclusively by inner CV.

### Table 4: Nested Model Comparison (`nested_model_comparison.csv`)

| Candidate Architecture | Nested Balanced Accuracy | Nested Accuracy | Nested Macro F1 | Nested Correct Recall | Nested Incorrect Recall | Fold Mean BA | Selection Behavior & Stability Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Baseline Phase 3 BalancedSVM** | **86.62%** | **88.21%** | **86.89%** | **91.80%** | **81.44%** | **85.50%** $\pm 8.62\%$ | **Frozen baseline; perfectly stable across all source splits.** |
| **Candidate 1 (RBF SVM Space)** | **85.38%** | **87.86%** | **86.24%** | **93.44%** | **77.32%** | **84.02%** $\pm 8.81\%$ | Inner selections selected different configs per fold: Fold 0: ($C=1, \gamma=\text{scale}$), Fold 1: ($C=4, \gamma=0.02$), Fold 2: ($C=4, \gamma=0.04$), Fold 3: ($C=4, \gamma=\text{scale}$), Fold 4: ($C=0.5, \gamma=0.04$). Net drop: **-1.24 pp**. |
| **Candidate 2 (HistGradientBoosting Space)** | **79.47%** | **83.93%** | **81.06%** | **93.99%** | **64.95%** | **78.62%** $\pm 10.29\%$ | Severe collapse on unseen source groups; Incorrect Recall fell to 64.95%. Net drop: **-7.15 pp**. |

### Detailed Rationale for Retaining Phase 3 BalancedSVM:
1. **Failure to Survive Nested Validation:** While a specific post-hoc hyperparameter setting ($C=1.0, \gamma=0.04$) achieved 87.65% on the outer folds, the nested protocol proved that an autonomous model selection procedure chooses unstable configurations across folds, yielding an aggregate out-of-fold Balanced Accuracy of **85.38%**, which is **1.24 percentage points worse** than the frozen baseline.
2. **Phase 3 Model Robustness:** The Phase 3 BalancedSVM ($C=1.0, \gamma=\text{scale} \approx 0.0294$) uses the natural scaling heuristic $\gamma = 1 / (N_{\text{features}} \cdot \text{Var}(X))$. This un-tuned parameterization avoids chasing individual source idiosyncrasies, achieving higher empirical generalization across completely held-out source videos.
3. **Engineering Parity and Stability:** The Phase 3 model is supported by an established, bit-exact deployment adapter (`research/assisted_elbow_flexion_v2/phase4/deployment_adapter.py`) with zero numerical drift across the entire canonical corpus. Replacing it with a marginally tuned variant that fails nested validation would introduce technical debt and degrade actual out-of-distribution robustness.

---

## 6. Offline Parity Verification of Phase 9 Candidate

To satisfy the Stage 12 requirements, a pure NumPy research deployment adapter (`phase9_model_adapter.py`) was developed for the top candidate model ($C=1.0, \gamma=0.04$, Pipeline B) and audited against the scikit-learn reference fit on all 280 canonical repetitions:
- **Maximum Imputer Difference:** $0.00 \times 10^{0}$
- **Maximum Scaler Difference:** $0.00 \times 10^{0}$
- **Maximum Decision Score Difference:** $1.15 \times 10^{-14}$ (well within machine precision)
- **Class Prediction Agreement:** **280 / 280 (100.00%)**
- **Parity Log:** Exported to [`phase9/offline_parity_results.csv`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase9/offline_parity_results.csv).

Both the parameter artifact ([`final_model_v2_optimized_parameters.json`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase9/checkpoints/final_model_v2_optimized_parameters.json)) and metadata artifact ([`final_model_v2_optimized_metadata.json`](file:///C:/dev/Haemophilia/research/assisted_elbow_flexion_v2/phase9/checkpoints/final_model_v2_optimized_metadata.json)) have been preserved in the Phase 9 checkpoint directory for full provenance.

---

## 7. Data Provenance & Integrity Governance

The Phase 9 evaluation conformed to all pre-registered project rules:
1. **Canonical Dataset Only:** Exclusively the 280 human-reviewed repetitions from `human280_20261004/canonical_manifest.csv` were used.
2. **Zero Contamination from Disallowed Sources:**
   - No Phase 8 prospective recordings were used as validation data.
   - Phase 8 remains strictly classified as: `B — Inconclusive for independent validation`.
   - No V1 historical clips or historical normalized arrays were used.
   - All 22 excluded candidates remained excluded.
3. **Grouping Compliance:** All folds were grouped strictly by `source_sha256` (29 source groups). No repetitions from the same source video were split across training and validation folds.
4. **Codebase Preservation:** No changes were made to Flutter, backend services, or production models.

---

## 8. Final Governance Status

Under the mandatory decision criteria:
- **A — Meaningful Improvement:** Candidate improves grouped balanced accuracy by $\ge 1.0$ percentage point AND survives nested validation. *(Not met: candidate gained +1.03 pp in outer sweep but dropped to 85.38% under nested CV).*
- **B — No Meaningful Improvement:** Search does not establish a reproducible $\ge 1.0$ point improvement. *(Confirmed).*
- **C — Inconclusive:** Search incomplete or unstable.

### Formal Status:
$$\mathbf{B \text{ — No Meaningful Improvement}}$$

### Formal Directive:
**KEEP THE EXISTING PHASE 3 BALANCED SVM.**  
The Phase 3 `BalancedSVM` ($C=1.0, \gamma=\text{scale}$, `class_weight='balanced'`) remains the frozen, authoritative research classifier for Assisted Elbow Flexion V2.

---

## 9. Limitations & Research Boundaries

1. **Development Set Saturation:** The 280 canonical repetitions exhibit high internal consistency. Fine-tuning hyperparameters on this dataset risks capturing source-specific noise rather than biomechanical truth.
2. **Absence of External Cohort:** All evaluations in this phase represent internal cross-validation on model development data. As established in Phase 8.1, zero independent continuous recording videos currently exist in the repository.
3. **No Clinical or Production Claim:** This model is an offline research component. It is **NOT clinically validated**, **NOT clinically proven**, and **NOT production validated**. Production integration remains prohibited until prospective multi-center data can be gathered.

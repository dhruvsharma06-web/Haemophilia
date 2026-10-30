# Assisted Elbow Flexion V2 — Model Development & Governance Guide

This document describes the archived V2 model and its original experiments. The current app uses trained V5 with the V6 controller; see `docs/elbow-integration.md`. Claims below about the permanent or authoritative model refer to that earlier V2 development workflow, not to the current app selection or independent clinical validation.

- **Release Version:** 2.0.0-phase3
- **Status:** Research Model Authoritative Baseline
- **Canonical Dataset:** `human280_20261004` (SHA-256: `bb4669ec492ac26cbf5b064c89390e43cac207f9785c3a5cd0003cea3c587262`)
- **Primary Metric:** Balanced Accuracy

---

## 1. Executive Summary

This document establishes the authoritative model architecture, feature representation, evaluation benchmarks, and governance decisions for **Assisted Elbow Flexion V2**.

The authoritative model is the **Phase 3 `BalancedSVM`**, trained on the canonical 280-repetition human-reviewed dataset. Extensive model optimization experiments conducted in Phase 9 across 509 configurations demonstrated that apparent small gains in outer-fold sweeps failed to survive strict nested grouped cross-validation due to hyperparameter sensitivity across source video clusters. Consequently, the Phase 3 `BalancedSVM` remains the permanent, frozen authoritative model.

---

## 2. Canonical Supervised Dataset Specifications

All supervised model development and validation are restricted to the finalized canonical release `human280_20261004`:
- **Total Validated Repetitions:** **280**
- **Binary Target Class Distribution:**
  - **Correct (Class 0):** 183 repetitions (65.36%)
  - **Incorrect (Class 1):** 97 repetitions (34.64%)
- **Hand Distribution (Metadata Only):**
  - **Left Hand:** 143 repetitions (51.07%)
  - **Right Hand:** 137 repetitions (48.93%)
  - *Hard Invariant: Hand is metadata only and is never used as an input feature or prediction class.*
- **Source Videos:** 29 unique video recordings from 5 recording session blocks.
- **Excluded Candidates:** Exactly 22 candidate segments were excluded during quality-control auditing and remain excluded from all training and evaluation sets.
- **Historical Data:** Historical V1 isolated clips and historical normalized arrays are reference provenance only and are strictly barred from training.

---

## 3. Authoritative Pipeline Architecture

The authoritative inference pipeline executes deterministic, bit-exact transformations from raw world landmarks to signed decision scores:

```
Raw World Landmarks (3D)
  │
  ▼
34 Biomechanical Scalar Kinematic Features
  │
  ▼
Mean Imputation (SimpleImputer, strategy='mean', keep_empty_features=True)
  │
  ▼
Standard Scaling (StandardScaler, with_mean=True, with_std=True)
  │
  ▼
RBF Support Vector Classifier (sklearn.svm.SVC, C=1.0, gamma='scale', class_weight='balanced')
  │
  ▼
Signed Decision Score: f(x) = ∑ α_i K(x, s_i) + b
  │
  ▼
Decision Threshold Rule:
  • f(x) > 0.0  =>  Incorrect (Class 1)
  • f(x) <= 0.0 =>  Correct   (Class 0)
```

### Effective Hyperparameters:
- **Kernel:** Radial Basis Function (RBF)
- **$C$:** $1.0$
- **$\gamma$:** `'scale'` ($\approx 0.029412 = 1 / (34 \cdot \text{Var}(X))$)
- **Class Weights:** Balanced
  - Correct ($w_0$): $0.765027$
  - Incorrect ($w_1$): $1.443299$
- **Intercept ($b$):** $+0.730076$
- **Support Vectors:** 147 total (85 Correct, 62 Incorrect)

---

## 4. 34-Feature Representation

The 34 locked scalar features summarize 3D kinematics across the full repetition window:

1. `active_min_angle`: Minimum 3D active elbow angle (degrees)
2. `active_max_angle`: Maximum 3D active elbow angle (degrees)
3. `active_rom`: Range of motion (max - min angle, degrees)
4. `opposing_min_angle`: Contralateral elbow minimum angle (degrees)
5. `opposing_max_angle`: Contralateral elbow maximum angle (degrees)
6. `opposing_rom`: Contralateral range of motion (degrees)
7. `duration`: Repetition duration (seconds)
8. `active_peak_abs_velocity`: Peak angular velocity of active elbow (deg/s)
9. `active_mean_abs_velocity`: Mean angular velocity of active elbow (deg/s)
10. `opposing_peak_abs_velocity`: Contralateral peak velocity (deg/s)
11. `opposing_mean_abs_velocity`: Contralateral mean velocity (deg/s)
12. `active_mean_flare`: Mean active elbow shoulder-flare ratio
13. `active_max_flare`: Peak active elbow shoulder-flare ratio
14. `opposing_mean_flare`: Contralateral mean flare ratio
15. `opposing_max_flare`: Contralateral peak flare ratio
16. `mean_angle_asymmetry`: Mean bilateral angle absolute difference (degrees)
17. `max_angle_asymmetry`: Peak bilateral angle difference (degrees)
18. `mean_flare_asymmetry`: Mean bilateral flare difference
19. `max_flare_asymmetry`: Peak bilateral flare difference
20. `mean_torso_lean`: Mean torso lean relative to vertical (degrees)
21. `max_torso_lean`: Peak torso lean (degrees)
22. `range_torso_lean`: Range of torso lean (degrees)
23. `mean_shoulder_depth_ratio`: Mean shoulder z-depth asymmetry ratio
24. `max_shoulder_depth_ratio`: Peak shoulder depth ratio
25. `range_shoulder_depth_ratio`: Range of shoulder depth ratio
26. `flexion_duration`: Duration of flexion phase (start to peak flexion, seconds)
27. `extension_duration`: Duration of extension phase (peak to return, seconds)
28. `flexion_fraction`: Ratio of flexion duration to total duration
29. `active_start_angle`: Elbow angle at initiation (degrees)
30. `active_end_angle`: Elbow angle at termination (degrees)
31. `flexion_excursion`: Angular displacement during flexion (degrees)
32. `extension_excursion`: Angular displacement during extension (degrees)
33. `flexion_net_speed`: Net velocity during flexion (deg/s)
34. `extension_net_speed`: Net velocity during extension (deg/s)

---

## 5. Authoritative Performance Benchmarks

### 5-Fold Source-Grouped Cross-Validation (`StratifiedGroupKFold`, seed=42)
*Grouping by `source_sha256` ensures zero video overlap between training and test folds.*

- **Overall Accuracy:** **88.21%** (247 / 280)
- **Balanced Accuracy:** **86.62%** (Fold mean: $85.50\% \pm 8.62\%$)
- **Macro F1 Score:** **86.89%**
- **Correct Sensitivity / Recall:** **91.80%** (168 / 183)
- **Incorrect Sensitivity / Recall:** **81.44%** (79 / 97)
- **Confusion Matrix:**
  $$\begin{pmatrix} 168 & 15 \\ 18 & 79 \end{pmatrix}$$
- **False Positive Rate (Correct misclassified as Incorrect):** 8.20% (15 / 183)
- **False Negative Rate (Incorrect missed as Correct):** 18.56% (18 / 97)

### Leave-One-Source-Out (LOSO) Validation (29 Folds)
- **Balanced Accuracy:** **84.26%**
- **Incorrect Recall:** **78.35%** (76 / 97)
- **Overall Accuracy:** **86.07%** (241 / 280)

---

## 6. Phase 9 Model Optimization Audit

In Phase 9, an extensive optimization sweep evaluated 509 model configurations across RBF SVM, Polynomial SVM, Logistic Regression, ExtraTrees, and HistGradientBoosting, incorporating fold-internal feature selection, preprocessing variations (Pipelines A, B, and C), and nested decision threshold tuning:

1. **Outer Sweep Findings:** An RBF SVM configuration ($C=1.0, \gamma=0.04$, Pipeline B) achieved an apparent outer-sweep Balanced Accuracy of 87.65% (+1.03 pp gain).
2. **Strict Nested Confirmation (5 Outer $\times$ 3 Inner Folds):** When all hyperparameters and thresholds were selected strictly inside inner cross-validation folds, the candidate RBF SVM space achieved an outer nested Balanced Accuracy of **85.38%** (**-1.24 pp below the baseline**). HistGradientBoosting collapsed to **79.47%** (-7.15 pp).
3. **Audit Conclusion:** The outer sweep's apparent gain was an artifact of hyperparameter fine-tuning to specific source clusters. Under uncompromised nested validation, the baseline un-tuned $\gamma=\text{scale}$ parameterization generalizes superiorly to novel sources.
4. **Final Phase 9 Decision:** **`B — No Meaningful Improvement`**. The Phase 3 BalancedSVM baseline is retained unchanged.

---

## 7. Repetition Segmentation & Runtime Architecture

For continuous webcam streaming, repetition windowing is managed by the **Causal Cycle Segmenter** validated in Phase 7.2:
- **Pre-Roll Window:** 15 frames
- **Post-Roll Window:** 10 frames
- **Deterministic Runner Micro-Wobble Filter:** Drops candidate cycles with duration $< 1.50$ seconds AND ROM $< 26^\circ$.
- **Validation Throughput:** Achieved 88.2% cycle completion and 86.3% end-to-end classification accuracy on continuous real-human webcam evaluation streams.

---

## 8. Governance & Regulatory Limitations

1. **Internal Development Dataset Only:** All reported benchmarks represent internal cross-validation on model development recordings.
2. **Independent Validation Status:** Phase 8.1 established that exactly zero continuous video recordings currently exist outside the 29 source videos used in dataset construction. Therefore, Phase 8 is formally designated:
   $$\mathbf{B \text{ — Inconclusive for independent validation}}$$
3. **Regulatory Truth in Advertising:**
   - **NOT clinically validated**
   - **NOT clinically proven**
   - **NOT production validated**
   - True external validation requires a prospective clinical cohort of novel human subjects recorded under multi-camera, multi-lighting protocols.

# Assisted Elbow Flexion V2: Phase 4 Offline Numerical Parity Report

**Date:** 2026-10-04  
**Authoritative Model:** BalancedSVM (`sklearn.svm.SVC(kernel="rbf", C=1.0, gamma="scale", class_weight="balanced")`)  
**Canonical Dataset:** `processed_data/assisted_elbow_flexion_v2/releases/human280_20261004` (280 supervised repetitions)  
**Status:** **PASSED WITH ZERO LOGICAL DISCREPANCY (EXACT PARITY)**

---

## 1. Executive Summary

Before authorizing any webcam or live hardware testing, the Phase 4 deployment adapter (`deployment_adapter.py`) was subjected to a rigorous offline numerical parity verification against the frozen Phase 3 authoritative model parameters.

### Parity Audit Checklist
1. **Feature Ordering:** Exactly identical 34-feature vector definition matching `feature_definition_snapshot.json` (0 discrepancies).
2. **Imputation:** Exactly identical mean imputation statistics across all 34 features (maximum absolute difference = **0.0**).
3. **Standard Scaling:** Exactly identical standard scaler mean and scale coefficients across all 34 features (maximum absolute difference = **0.0**).
4. **SVM Mathematical Parameters:** Exactly identical support vectors ($N_{sv}=147$), dual coefficients, intercept ($b=0.730075786$), and effective gamma ($\gamma=0.029411765$).
5. **Decision Score Parity:** Maximum absolute difference in signed decision score across all 280 canonical repetitions = **1.5543e-14** (pure floating-point epsilon). Mean absolute difference = **3.8989e-15**.
6. **Class Decision Parity:** Exact **100.0% agreement** (280 / 280 repetitions).
7. **Apparent Metrics:** Reproduced the exact Phase 3 training apparent metrics:
   - Apparent Accuracy: **98.57%** (276 / 280)
   - Apparent Balanced Accuracy: **98.18%**
   - Confusion Matrix (TN, FP / FN, TP): `[[182, 1], [3, 94]]`
   - Correct Movement Specificity: **99.45%** (182 / 183)
   - Incorrect Movement Sensitivity: **96.91%** (94 / 97)

---

## 2. Quantitative Verification Results

| Dimension | Verification Metric | Observed Value | Tolerance Threshold | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Feature Dimensions** | Scalar Count | 34 / 34 | Exact match | **PASS** |
| **Feature Alignment** | Order Check | 100% Identical | Exact match | **PASS** |
| **Imputation Statistics** | Max Abs Delta | `0.00e+00` | $\le 10^{-12}$ | **PASS** |
| **Scaler Centering** | Max Mean Delta | `0.0` | $\le 10^{-12}$ | **PASS** |
| **Scaler Scaling** | Max Scale Delta | `0.0` | $\le 10^{-12}$ | **PASS** |
| **Support Vectors** | Vector Shape & Values | `(147, 34)` | Exact match | **PASS** |
| **Effective Gamma** | Kernel Width | `0.0294117647` | Exact match | **PASS** |
| **Intercept** | SVM Bias Term | `0.7300757861` | Exact match | **PASS** |
| **Decision Function** | Max Abs Diff | `1.5543e-14` | $\le 10^{-10}$ | **PASS** |
| **Decision Function** | Mean Abs Diff | `3.8989e-15` | $\le 10^{-12}$ | **PASS** |
| **Classification Output** | Label Agreement | **100.0%** (280/280) | 100.0% | **PASS** |

---

## 3. Class Mapping & Decision Boundary Rule

The Phase 4 deployment adapter adheres strictly to the authoritative Phase 3 binary mapping:
- Class 0: `Correct` ($n = 183$)
- Class 1: `Incorrect` ($n = 97$)

The decision rule is evaluated directly on the signed RBF score $f(x) = \sum_{i=1}^{147} lpha_i \exp(-\gamma \|x - s_i\|^2) + b$:
$$	ext{Prediction} = egin{cases} 	ext{Incorrect} & 	ext{if } f(x) > 0 \ 	ext{Correct} & 	ext{if } f(x) \le 0 \end{cases}$$

Notice:
- No synthetic probability threshold tuning was conducted.
- No Platt scaling or sigmoid calibration was applied.
- The signed score is reported directly as `decision_score`, never masked as a fake "confidence percentage".

---

## 4. End-to-End Landmark Extraction Parity

In addition to feature array inference, raw world landmarks from all 29 source videos in `preprocessing/raw_landmarks/` were processed through `BalancedSVMDeploymentAdapter.extract_features()` for all 280 repetitions:
- Maximum feature extraction delta against canonical `features/scalar_features.csv` = **0.0**.
- Confirms that the Phase 4 signal repair, numerical integration (`np.trapezoid`), gradient velocity derivation, and phase segmentation reproduce the canonical dataset with bit-level accuracy.

---

## 5. Conclusion & Clearance for Live Testing

The Phase 4 deployment adapter is **mathematically and logically identical** to the frozen Phase 3 authoritative `BalancedSVM` model.

Offline parity is verified. Phase 4 is cleared to proceed to repetition segmentation design and shadow webcam testing.

# Assisted Elbow Flexion: Cross-Subject Benchmark & Model Evaluation Report

> [!IMPORTANT]
> **PHASE 9 SYSTEM STATUS (FROZEN PIPELINE & EXPANDED COHORT)**:
> The authoritative benchmark on the clean human-verified expanded dataset ($N=195$ repetitions, 3 subjects) is:
> - **Production Biomechanical Evaluator (Base 8A)**: **85.24% Balanced Accuracy**, **84.62% Accuracy**, **84.40% Macro-F1** (`min_elbow_angle <= 101.0°`, `elbow_flare <= 0.30`, `rom >= 25.0°`, `abs(torso_rotation) <= 20.0°`). This is the active production evaluator.
> - **Research Benchmark (Nested LOSO Duration Selection)**: **85.87% Balanced Accuracy**, **85.13% Accuracy**, **84.94% Macro-F1** (Confusion Matrix: `[[72, 8], [21, 94]]`). This is strictly a research benchmark; fold-specific duration thresholds (P1=1.00s, P2=1.75s, P3=1.75s) are NOT a deployable universal production rule.
> - **Research ML Model (`v2_phase_bilateral_195`)**: **77.42% Balanced Accuracy**, **78.97% Accuracy**, **77.85% Macro-F1**. Maintained as an independent experimental neural model.
> - **Exploratory Candidate (`ext_dur >= 0.70s`)**: Descriptive Balanced Accuracy: **87.31%** (Accuracy: 86.15%, Macro-F1: 86.03%). Strictly exploratory; NOT validated or production-ready.
>
> For full component breakdown, see [assisted_elbow_flexion_system_status.md](file:///c:/dev/Haemophilia/docs/assisted_elbow_flexion_system_status.md).

## 1. Executive Summary & Authoritative Benchmark

This document details the cross-subject Leave-One-Subject-Out Cross-Validation (LOSO-CV) benchmark for **Assisted Elbow Flexion** using the authoritative human-verified repetition-level dataset (`data/clean_elbow_train.csv`, $N=150$ usable repetitions initial cohort; expanded to $N=195$ repetitions in `data/clean_elbow_train_expanded.csv`).

```text
Method                                 LOSO Balanced Accuracy   Aggregate Accuracy   Macro-F1
-------------------------------------------------------------------------------------------------
Research Benchmark: Nested Duration    85.87%                   85.13%               84.94%
Production Biomechanical Evaluator     85.24%                   84.62%               84.40%
Phase-Bilateral LSTM v2 (N=195)        77.42%                   78.97%               77.85%
Deterministic Rules Baseline (N=150)   79.14%                   78.67%               78.20%
Logistic Regression (N=150)            65.81%                   64.67%               64.40%
Random Forest (N=150)                  62.40%                   58.00%               57.77%
Human-verified LSTM v1 (N=150)         58.30%                   61.33%               58.37%
```

### Critical Findings & Clinical Disclaimer
1. **Pilot Cross-Subject Results on $N=3$ Subjects**:
   - These results represent an engineering validation on 3 recorded subjects.
   - **They do NOT constitute clinical validation or medical diagnosis.**
2. **Deterministic Rules Are the Strongest Cross-Subject Evaluator**:
   - The deterministic biomechanical rule evaluator (`evaluate_repetition_biomechanics`) achieves **79.14% balanced accuracy** under LOSO.
   - It is currently the primary evaluator in live production (`primary_evaluator = biomechanical_rules`).
3. **Role of the LSTM**:
   - **The LSTM did NOT achieve the best performance.** Simpler linear baselines (Logistic Regression at 65.81%) and deterministic rules (79.14%) clearly outperform it on this small sample cohort.
   - The ExerciseLSTM is retained as the project's neural deep learning implementation required by the architecture specifications. It serves as an experimental research model that logs predictions independently.

---

## 2. Dataset & Repetition-Level Annotation

- **Total Detected Repetitions**: 209
- **Accepted Segmented Repetitions**: 153 across 14 labelled videos
- **Human-Verified Annotations**:
  - Correct: 91
  - Incorrect: 59
  - Ambiguous / Exclude: 3 (tracking occlusions or video boundary truncations)
  - Total usable supervised repetitions: 150
- **Agreement Analysis**:
  - Folder Label vs. Human Ground Truth: 148 / 153 (96.7% agreement across all accepted; 148 / 150 = 98.7% on usable repetitions).
  - Provisional Auto-Label vs. Human Ground Truth: 95 / 153 (62.1% agreement; 58 decisions corrected by human review).
- **Excluded Recordings**:
  - The 4 "Both hand assisted mix" videos (`20260825_121230.mp4`, `20260825_135917.mp4`, `VID20260825125415.mp4`, `VID20260825125816.mp4`) are strictly excluded from supervised training until individualized ground-truth annotations are performed.

---

## 3. Detailed Model Evaluations

### A. Untouched Person 3 Final Test Set (LSTM Checkpoint)
- **Model Checkpoint**: `models/assisted_elbow_lstm_human_verified.pth`
- **Training Pool**: Persons 1 & 2 only (90 train reps, 25 internal validation reps from isolated videos)
- **Person 3 Repetitions**: 35 (20 Correct, 15 Incorrect) — 100% held out from feature selection, threshold calibration, and checkpoint selection
- **Performance**:
  - Accuracy: 62.86% (22 / 35)
  - Balanced Accuracy: 65.83%
  - Macro-F1: 62.37%
  - Correct Recall (Specificity): 45.00% (9 / 20)
  - Incorrect Recall (Sensitivity): 86.67% (13 / 15)
  - Confusion Matrix:
    ```text
                        Pred Correct   Pred Incorrect
      True Correct (0)             9               11
      True Incorrect (1)           2               13
    ```

### B. True 3-Fold Leave-One-Subject-Out (LOSO) Cross-Validation
Each fold trained a fresh model from scratch, using only the training subjects for model selection:

1. **Fold 1: Held-out Person 1** (Train: 74, Val: 17, Test: 59):
   - LSTM Accuracy: 64.41% | Balanced Accuracy: 60.65% | Macro-F1: 59.79%
   - Correct Recall: 85.29% | Incorrect Recall: 36.00%
2. **Fold 2: Held-out Person 2** (Train: 76, Val: 18, Test: 56):
   - LSTM Accuracy: 69.64% | Balanced Accuracy: 55.26% | Macro-F1: 50.18%
   - Correct Recall: 100.00% | Incorrect Recall: 10.53%
3. **Fold 3: Held-out Person 3** (Train: 90, Val: 25, Test: 35):
   - LSTM Accuracy: 42.86% | Balanced Accuracy: 50.00% | Macro-F1: 30.00%
   - Correct Recall: 0.00% | Incorrect Recall: 100.00%

### C. Aggregate Multi-Model Comparison Table
| Metric | Deterministic Rules | Logistic Regression | Random Forest | Human-verified LSTM |
| :--- | :---: | :---: | :---: | :---: |
| **Balanced Accuracy** | **79.14%** | **65.81%** | **62.40%** | **58.30%** |
| **Aggregate Accuracy** | **78.67%** (118/150) | 64.67% (97/150) | 58.00% (87/150) | 61.33% (92/150) |
| **Macro-F1** | **78.20%** | 64.40% | 57.77% | 58.37% |
| **Correct Recall** | 76.92% (70/91) | 60.44% (55/91) | 41.76% (38/91) | 72.53% (66/91) |
| **Incorrect Recall** | 81.36% (48/59) | 71.19% (42/59) | 83.05% (49/59) | 44.07% (26/59) |

---

## 4. Production Integration, Model Registry & Research Model Architecture

In `backend/app/services/model_registry.py`:
- Registered Production/Research Checkpoints:
  - `assisted_elbow_lstm_human_verified`: loads `models/assisted_elbow_lstm_human_verified.pth` (Legacy v1 model: 2-layer unidirectional `ExerciseLSTM`, 8 canonical features, 54,370 parameters, trained on initial $N=150$ cohort).
  - `assisted_elbow_lstm_experimental`: loads `models/assisted_elbow_lstm.pth` (Pilot baseline checkpoint).
- Authoritative Research ML Model (`v2_phase_bilateral_195` / `temporal_phase_bilateral_hybrid`):
  * Architecture: `HybridTemporalScalarModel` (7,690 trainable parameters).
  * Temporal Branch: `[batch, 128, 10]` $\rightarrow$ 1-layer LSTM hidden 32 (`batch_first=True`, dropout 0.4).
  * Scalar Branch: `[batch, 34]` $\rightarrow$ 16 $\rightarrow$ 16 MLP (dropout 0.4) on 34 phase-aware/bilateral scalar metrics.
  * Fusion Head: `48` $\rightarrow$ `24` $\rightarrow$ `2` (`Linear(48, 24) -> ReLU -> Dropout(0.4) -> Linear(24, 2)`).
  * Total Parameters: **7,690** trainable parameters.
  * Evaluated via strict 3-fold LOSO cross-validation with inner-validation threshold tuning on the expanded $N=195$ dataset ([`data/clean_elbow_train_expanded.csv`](file:///c:/dev/Haemophilia/data/clean_elbow_train_expanded.csv)).
  * Authoritative LOSO Result: **78.97% Accuracy / 77.42% Balanced Accuracy / 77.85% Macro-F1** (reproduced in [`scratch/verify_v2_reproduction.py`](file:///c:/dev/Haemophilia/scratch/verify_v2_reproduction.py)).
- The live engine (`src/exercises/assisted_elbow_flexion.py`) uses:
  - `primary_evaluator = biomechanical_rules` for all primary user feedback and scoring.
  - `learned_ml_prediction` is evaluated and logged as an explicitly separated dictionary block, without contaminating or merging with the biomechanical confidence score.

---

## 5. Main Remaining Limitations & Next Steps

1. **Cohort Size ($N=3$ Subjects)**:
   - With only 3 participants, machine learning classifiers overfit to individual body morphology, clothing contrast, and camera positioning.
   - Adding additional participants is required before neural models can outperform deterministic kinematics.
2. **Bilateral Assistance Variation**:
   - The 4 mixed bilateral videos remain unannotated and excluded. Annotating them will expand the dataset to ~180-190 repetitions.

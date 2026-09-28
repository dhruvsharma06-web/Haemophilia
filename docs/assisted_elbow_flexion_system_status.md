# Assisted Elbow Flexion: Authoritative System Status & Benchmark Hierarchy
**Status**: Entire Pipeline FROZEN (Phase 9)  
**Cohort**: 195 clean human-verified repetitions across 3 subjects (`person1`, `person2`, `person3`)  
**Next Objective**: Multi-subject generalization expansion via Persons 4 and 5

---

## 1. Executive Benchmark Hierarchy

To maintain scientific integrity and prevent leakage or premature claims, the project strictly distinguishes between **Production Evaluator**, **Research Benchmark**, **Research ML Models**, **Exploratory Temporal Candidates**, and **Descriptive In-Sample Benchmarks**.

```text
========================================================================================================================
EVALUATION LEVEL                              BALANCED ACC   ACCURACY   MACRO-F1   STATUS / ROLE
========================================================================================================================
1. Production Biomechanical Evaluator (Base 8A) 85.24%       84.62%     84.40%     Production Biomechanical Engine
2. Research Benchmark (Nested LOSO Duration)    85.87%       85.13%     84.94%     Research Benchmark (NOT Production)
3. Research ML Model (v2_phase_bilateral_195)   77.42%       78.97%     77.85%     Experimental Neural Model in Registry
4. Descriptive Fixed 1.75s Benchmark           86.49%       86.15%     85.99%     Descriptive Full-Dataset Reference
5. Exploratory Candidate (ext_dur >= 0.70s)     87.31%       86.15%     86.03%     Exploratory Only (NOT Production Ready)
========================================================================================================================
```

> [!WARNING]
> **CRITICAL PRODUCTION vs. RESEARCH DISTINCTION**:
> - The **Production Biomechanical Evaluator** is strictly composed of the 4 validated geometric criteria (85.24% BalAcc).
> - The **Nested LOSO Duration-Aware Result (85.87% BalAcc)** is strictly a **Research Benchmark**. It is **NOT** the production engine.
> - The fold-specific duration thresholds (Person 1 = 1.00s, Person 2 = 1.75s, Person 3 = 1.75s) reflect inner-fold exploratory adaptations and must **NOT** be described or deployed as a universal production threshold.
> - The **eccentric-duration candidate (`ext_dur >= 0.70s`)** is strictly **exploratory**. It is **NOT** validated or production-ready.

---

## 2. Component Taxonomy & Boundary Definitions

### A. Production Biomechanical Evaluator
- **Implementation**: Evaluated deterministically within [`src/exercises/assisted_elbow_flexion.py`](file:///c:/dev/Haemophilia/src/exercises/assisted_elbow_flexion.py).
- **Threshold Criteria**:
  1. `min_elbow_angle <= 101.0°` (Flexion depth criterion)
  2. `elbow_flare <= 0.30` (Lateral abduction excursion relative to reference shoulder width $W_{\text{ref}}$)
  3. `rom >= 25.0°` (Minimum active angular excursion)
  4. `abs(torso_rotation) <= 20.0°` (Transverse trunk compensation limit established in Phase 8A)
- **Performance (Strict 3-Subject LOSO)**:
  - **Balanced Accuracy: 85.24%**
  - **Accuracy: 84.62%** (165/195)
  - **Macro-F1: 84.40%**
  - Correct Recall: 81.74% (94 / 115)
  - Incorrect Recall: 88.75% (71 / 80)
  - Confusion Matrix: `[[71, 9], [21, 94]]`
- **Deployment Role**: Authoritative active biomechanical assessment engine for user scoring and form feedback.

### B. Research Benchmark: Nested LOSO Duration-Aware Evaluation
- **Methodology**: 
  - Strictly holds out one entire subject at a time.
  - An inner stratified validation partition (20% of training subjects, seed 42) selects the optimal minimum duration threshold $\theta \in [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 3.0, 3.5, 4.0]\text{s}$.
  - The winning threshold is evaluated once on the untouched held-out subject.
- **Research Benchmark Performance**:
  - **Balanced Accuracy: 85.87%**
  - **Accuracy: 85.13%** (166/195)
  - **Macro-F1: 84.94%**
  - Correct Recall: 81.74% (94 / 115)
  - Incorrect Recall: 90.00% (72 / 80)
  - Confusion Matrix: `[[72, 8], [21, 94]]`
- **Per-Fold Inner Selections**:
  - **Fold 1 (Person 1 held out)**: Selected $\ge 1.00\text{s}$ $\rightarrow$ Test BalAcc: **81.70%** (Acc: 81.69%, CM: `[[27, 6], [7, 31]]`)
  - **Fold 2 (Person 2 held out)**: Selected $\ge 1.75\text{s}$ $\rightarrow$ Test BalAcc: **81.07%** (Acc: 77.94%, CM: `[[26, 1], [14, 27]]`)
  - **Fold 3 (Person 3 held out)**: Selected $\ge 1.75\text{s}$ $\rightarrow$ Test BalAcc: **97.50%** (Acc: 98.21%, CM: `[[19, 1], [0, 36]]`)
- **Operational Constraint**: Because fold-specific selections differed across folds (Person 1 selected 1.00s; Persons 2 & 3 selected 1.75s), this represents a **Research Benchmark** establishing the informational value of temporal control. It is **NOT** a single fixed universal production rule.

### C. Research ML Model (`temporal_phase_bilateral_hybrid` / `v2_phase_bilateral_195`)
- **Model Identity**: `temporal_phase_bilateral_hybrid` (authoritative research ML model on the 195 expanded repetitions).
- **Exact Confirmed Architecture**:
  * **Temporal Branch**: `[batch, 128, 10]` $\rightarrow$ 1-layer LSTM hidden 32 (`batch_first=True`, dropout 0.4) on 10 subject-normalized sequence features (excluding absolute joint angles).
  * **Scalar Branch**: `[batch, 34]` $\rightarrow$ 16 $\rightarrow$ 16 MLP (`Linear(34, 16) -> ReLU -> Dropout(0.4) -> Linear(16, 16) -> ReLU -> Dropout(0.4)`) on 34 subject-standardized phase-aware/bilateral scalar metrics.
  * **Fusion Head**: `48` $\rightarrow$ `24` $\rightarrow$ `2` (`Linear(48, 24) -> ReLU -> Dropout(0.4) -> Linear(24, 2)`).
  * **Total Parameters**: **7,690** trainable parameters.
- **Training & Cross-Validation**:
  * Evaluated under true 3-fold Leave-One-Subject-Out (LOSO) on the 195 clean repetitions ([`data/clean_elbow_train_expanded.csv`](file:///c:/dev/Haemophilia/data/clean_elbow_train_expanded.csv)).
  * `StandardScaler` fitted strictly on training subjects in each fold.
  * Inner-validation threshold tuning on training subjects (`P1=0.51, P2=0.49, P3=0.46`).
  * Source file for evaluation and reproduction: [`scratch/run_phase_aware_ablation.py`](file:///c:/dev/Haemophilia/scratch/run_phase_aware_ablation.py) / [`scratch/verify_v2_reproduction.py`](file:///c:/dev/Haemophilia/scratch/verify_v2_reproduction.py).
- **Authoritative LOSO Results**:
  * **Accuracy: 78.97%** (154 / 195)
  * **Balanced Accuracy: 77.42%**
  * **Macro-F1: 77.85%**
  * Correct Recall: 86.09% (99 / 115)
  * Incorrect Recall: 68.75% (55 / 80)
  * Confusion Matrix: `[[55, 25], [16, 99]]`
  * Per-Fold: Person 1 (BalAcc: 70.77%), Person 2 (BalAcc: 68.52%), Person 3 (BalAcc: 95.83%).
- **Explicit Distinction from Legacy v1 Model**:
  * The **Legacy v1 Model** (`ExerciseLSTM` in [`src/models/lstm_model.py`](file:///c:/dev/Haemophilia/src/models/lstm_model.py), weights in [`models/assisted_elbow_lstm_human_verified.pth`](file:///c:/dev/Haemophilia/models/assisted_elbow_lstm_human_verified.pth)) is a 2-layer unidirectional LSTM on 8 canonical features (54,370 parameters), trained on the initial $N=150$ dataset ([`data/clean_elbow_train.csv`](file:///c:/dev/Haemophilia/data/clean_elbow_train.csv)) during Phase 0 (58.30% Balanced Accuracy).
  * It is currently registered in [`backend/app/services/model_registry.py`](file:///c:/dev/Haemophilia/backend/app/services/model_registry.py) under `assisted_elbow_lstm_human_verified` as the legacy reference checkpoint. It must **NOT** be confused with or labeled as `v2_phase_bilateral_195`.

### D. Exploratory Candidate: Eccentric-Extension Duration (`ext_dur >= 0.70s`)
- **Metric Formulation**: $\text{ext\_dur} = \text{duration\_sec} \times \frac{128 - \text{idx\_peak}}{128}$, where $\text{idx\_peak} = \arg\min(\text{active\_elbow\_angle})$.
- **Authoritative Phase 8D Descriptive Result** (Layered on Research Nested Benchmark):
  - Catches 3 ballistic eccentric drop errors (`person1` reps #6, #9, #15) with 1 false alarm (`person1` rep #14, duration 2.0s).
  - **Balanced Accuracy: 87.31%**
  - **Accuracy: 86.15%**
  - **Macro-F1: 86.03%**
  - Confusion Matrix: `[[75, 5], [22, 93]]`
- **Standalone on Base Rules** (Layered directly on Base 8A without duration):
  - Balanced Accuracy: **86.68%** | Accuracy: **85.64%** | Macro-F1: **85.50%** | Confusion Matrix: `[[74, 6], [22, 93]]`
- **Why It Is NOT Production-Ready**:
  - In nested LOSO, Fold 1 selected `None` because the training cohort (Persons 2 & 3) contained zero un-caught eccentric drops (their fast drops also violated flare or rotation). Consequently, the inner validation partition could not learn to activate the rule without seeing Person 1's isolated eccentric drops.
  - **Clinical / Engineering Mandate**: `ext_dur >= 0.70s` is strictly exploratory and MUST NOT be deployed into production or advertised as validated until Persons 4 and 5 provide an independent test of eccentric generalization.

### E. Descriptive Full-Dataset Reference Benchmarks
- **Descriptive Fixed 1.75s Duration**: 86.49% Balanced Accuracy (in-sample reference on all 195 reps).
- **Descriptive Fixed 0.70s Eccentric Duration**: 87.31% Balanced Accuracy (in-sample reference on all 195 reps).
- **Critical Distinction**: Descriptive benchmarks reflect whole-cohort parameter scans with full dataset visibility. They serve for error diagnosis and feature discovery, **NOT** as cross-validated generalization estimates.

---

## 3. Protocol & Tooling for Adding Persons 4 and 5

Phase 9 establishes the infrastructure to seamlessly onboard Persons 4 and 5:

1. **Collection Protocol**: [`docs/protocols/assisted_elbow_flexion_data_collection_protocol.md`](file:///c:/dev/Haemophilia/docs/protocols/assisted_elbow_flexion_data_collection_protocol.md)
   - Defines hardware placement, bilateral and single-hand modes, and 10 targeted error modes (A through J).
2. **Automated Dataset Audit & Dry-Run Intake**: [`src/data/audit_elbow_dataset.py`](file:///c:/dev/Haemophilia/src/data/audit_elbow_dataset.py)
   - CLI flags: `--strict` (audit current dataset) and `--dry-run` (intake validation for newly formatted participant files).
3. **Automated Dataset Reporter**: [`src/data/report_elbow_dataset.py`](file:///c:/dev/Haemophilia/src/data/report_elbow_dataset.py)
   - Summarizes reps, class balance, assistance modes, error tags, and distributions across all enrolled subjects.
4. **Extensible LOSO Cross-Validation Runner**: [`src/evaluation/run_extensible_loso.py`](file:///c:/dev/Haemophilia/src/evaluation/run_extensible_loso.py)
   - Reproducible evaluation and verification commands:
     ```bash
     # Verify authoritative benchmarks on old 3-subject cohort
     python src/evaluation/run_extensible_loso.py --mode old_3 --verify
     
     # Run extensible evaluation when Person 4 is added
     python src/evaluation/run_extensible_loso.py --mode plus_person4
     
     # Run extensible evaluation when Persons 4 and 5 are added
     python src/evaluation/run_extensible_loso.py --mode plus_person4_5
     ```

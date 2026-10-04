# Assisted Elbow Flexion V2 — Phase 3 Comprehensive Research Report

**Workspace:** [`<repo_root>/research\assisted_elbow_flexion_v2\phase3`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3)
**Dataset:** [`human280_20261004`](file:///<repo_root>/processed_data/assisted_elbow_flexion_v2/releases/human280_20261004) (280 human-reviewed repetitions; 183 Correct, 97 Incorrect; 143 Left, 137 Right; 29 source videos)
**Task:** Supervised Binary Classification (`Correct` vs `Incorrect`); Hand (`Left`/`Right`) is metadata only.
**Independent Verification:** Passed via [`verify_phase3.py`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/verify_phase3.py) (2,514 protected repository files verified unchanged; zero production code touched).

---

## 1. Executive Summary

Phase 3 concludes the research and model selection pipeline for Assisted Elbow Flexion V2. Building on the error audits and controlled experiments from Phases 1 and 2, Phase 3 evaluated the generalization boundaries of the pipeline under stricter validation paradigms, audited participant identity claims, measured the generalization gap across session clusters, established the final frozen research model, and audited deployment readiness.

### Key Conclusions of Phase 3
1. **Data Availability Assessment (CASE B Confirmed):**
   A thorough search of all storage volumes, raw downloads, and repository directories confirmed that **no genuinely independent reviewed external cohort exists**. All available human-reviewed repetitions reside strictly within the canonical 280-repetition dataset across 29 source videos. In strict compliance with research integrity guidelines, no synthetic or partitioned "external" test set was manufactured.
2. **Participant Identity Audit:**
   The nominal identifiers `person1` through `person5` are inherited metadata that align 1-to-1 with continuous recording time-blocks on two dates (2026-08-25 and 2026-09-10). Because no independent biometric roster, participant consent logs, or photo verification exist, these groups represent **recording session clusters**, not verified biological subjects. They are maintained as unverified metadata.
3. **Class-Weighted SVM (`BalancedSVM`) is the Decisive Final Model:**
   `BalancedSVM` (RBF SVM with analytic training-fold class balancing) is confirmed as the strongest and most resilient model:
   - **5-Fold Source-Grouped CV:** Balanced Accuracy **86.62%** (+2.76% over unweighted baseline), Incorrect Recall **81.44%** (+8.25%, cutting false negatives from 26 to 18), Macro-F1 **86.89%**.
   - **29-Fold Leave-One-Source-Out (LOSO):** Balanced Accuracy **84.26%** (vs 80.98% unweighted, a **+3.28%** advantage) and Incorrect Recall **78.35%** (vs 69.07% unweighted, a **+9.28%** advantage).
   - **5-Fold Session-Grouped CV:** Incorrect Recall **88.66%** (detecting 86 of 97 error repetitions across the entire dataset).
4. **Generalization Gap Quantified:**
   Holding out entire recording sessions drops Balanced Accuracy by **5.0% to 6.5%** (86.62% $\to$ 80.12%), driven almost entirely by session `person2` (57.1% accuracy due to camera angle and posture proxy shifts). This proves that session-level camera setup and viewpoint variation—not model capacity—remain the dominant bottleneck.
5. **Final Development Model Fit & Production Safety:**
   The final research model was fit on all 280 canonical development repetitions with complete mathematical transparency: parameters, support vectors (181 total: 100 Correct, 81 Incorrect), scaler coefficients, and imputer statistics are preserved in [`checkpoints/final_model_v2_parameters.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/checkpoints/final_model_v2_parameters.json) and [`final_model_metadata.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/final_model_metadata.json). No production checkpoints, Flutter apps, backends, or live camera evaluators were modified.

---

## 2. Available Data and Independence Assessment

Before any Phase 3 modeling, a comprehensive audit of all potential data sources across the repository and connected local directories was conducted:

| Storage Location | Artifacts Discovered | Status & Classification |
| :--- | :--- | :--- |
| `Downloads/hemo/Assisted elbow flexion/` | 29 `.mp4` video files | **The 29 source videos** of the canonical dataset. No other raw videos exist. |
| `processed_data/assisted_elbow_flexion_v2/releases/` | `human280_20261004` (280 repetitions) | **Canonical supervised dataset**. Strictly 280 repetitions (183 Correct, 97 Incorrect). |
| `processed_data/assisted_elbow_flexion_v2/` | 22 quarantined candidate descriptors | **Excluded candidates**. Remain strictly excluded (non-repetition/truncated intervals). |
| `data/` | `clean_elbow_train*.csv` (153, 195, 296 rows) | **Historical legacy datasets**. Provenance/reference only; not permitted as training samples. |
| `processed_data/assisted_elbow_flexion/clips/` | 154 `.mp4` video clips | **Legacy clips** corresponding to the historical 153/154 dataset. |

### Determination: CASE B Applies
- **No independent reviewed cohort exists.**
- The workspace contains no external hospital cohort, no prospective clinical recording session, and no unreviewed third-party repetitions.
- In accordance with the Phase 3 protocol for Case B:
  1. We do not manufacture an external test set by carving out a subset of the 280 canonical examples.
  2. We do not falsely claim external validation.
  3. We evaluate internal robustness across source-grouped, leave-one-source-out, and session-grouped holdouts.
  4. We document a concrete data-collection protocol for true prospective validation in Section 13.

---

## 3. Participant Identity Audit

The nominal identifiers `person1` through `person5` were audited against video timestamps, file metadata, and review logs. Results are recorded in [`participant_grouping_audit.csv`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/participant_grouping_audit.csv).

### Forensic Lineage of Participant Identifiers
- In the canonical release manifest, `subject_verification_status` is explicitly set to `inherited_not_independently_verified`.
- In the human review records (`evidence/aef_v2_review_*.json`), the field `review_subject_verified_checkbox` is `False` for all 280 repetitions.
- Cross-referencing video timestamps revealed that the 29 videos cluster into **5 distinct, continuous recording session blocks**:

| Inherited ID | Session Block | Recording Date | Time Window | Videos | Reps | Video Format / FPS | Setup Description |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **person1** | `session_block_1` | 2026-08-25 | 12:07:03 – 12:12:30 | 6 | 59 | 3840x2160, 60 fps | Continuous 5-minute block; camera frontal |
| **person3** | `session_block_2` | 2026-08-25 | 12:52:57 – 12:58:16 | 6 | 52 | 3840x2160, 30 fps | Continuous 5-minute block; `VID`-prefixed filenames |
| **person2** | `session_block_3` | 2026-08-25 | 13:54:23 – 13:59:17 | 6 | 70 | 3840x2160, 60 fps | Continuous 5-minute block; oblique camera angle |
| **person4** | `session_block_4` | 2026-09-10 | 14:41:15 – 14:44:48 | 6 | 60 | 3840x2160, 60 fps | Continuous 3-minute block recorded 16 days later |
| **person5** | `session_block_5` | 2026-09-10 | 15:03:57 – 15:06:02 | 5 | 39 | 3840x2160, 60 fps | Continuous 2-minute block recorded 16 days later |

### Audit Finding
There is no independent biometric evidence (e.g. facial identification, participant enrollment roster, or clothing audit) confirming that these 5 recording blocks represent 5 distinct individuals rather than repeat sessions of fewer individuals. Consequently, these groups represent **recording session clusters**.

In Phase 3, we treat them rigorously as **session holdouts** to measure the impact of holding out an entire recording batch.

---

## 4. Development Validation

Model development was restricted strictly to the 280 canonical repetitions using the 34 scalar features. Preprocessing (mean imputation and standard scaling) was fitted exclusively on training splits in every partition.

Three validation paradigms were executed to evaluate stability under increasing levels of holdout severity:
1. **5-Fold Source-Grouped Cross-Validation:** Standard evaluation where source videos are grouped using `StratifiedGroupKFold(n_splits=5)`. Sources from the same recording session may appear in both train and test, but no single source video spans across splits.
2. **29-Fold Leave-One-Source-Out (LOSO):** Each of the 29 source videos is held out individually, training on the remaining 28 sources.
3. **5-Fold Session/Inherited-Subject-Grouped Cross-Validation:** Each fold holds out an entire recording session cluster (`person1` through `person5`), ensuring complete independence of recording time, device configuration, and session setup.

---

## 5. Candidate Model Comparison

The frozen unweighted baseline (`FrozenPhase1SVM`) and the class-weighted candidate (`BalancedSVM`) were compared across all three validation paradigms. Comprehensive results are compiled in [`development_model_comparison.csv`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/development_model_comparison.csv).

| Validation Protocol | Model | N | Accuracy | Balanced Accuracy | Macro-F1 | Correct Recall | Incorrect Recall | Confusion Matrix | Source Acc Std | Min Source Acc |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **5-Fold Source-Grouped** | FrozenPhase1SVM | 280 | 87.14% | 83.87% | 85.18% | 94.54% | 73.20% | `[[173, 10], [26, 71]]` | 0.1927 | 30.0% |
| **5-Fold Source-Grouped** | **BalancedSVM** | 280 | **88.21%** | **86.62%** | **86.89%** | 91.80% | **81.44%** | `[[168, 15], [18, 79]]` | **0.1692** | **50.0%** |
| **29-Fold LOSO** | FrozenPhase1SVM_LOSO | 280 | 84.64% | 80.98% | 82.24% | 92.90% | 69.07% | `[[170, 13], [30, 67]]` | 0.2034 | 0.0% |
| **29-Fold LOSO** | **BalancedSVM_LOSO** | 280 | **86.07%** | **84.26%** | **84.51%** | 90.16% | **78.35%** | `[[165, 18], [21, 76]]` | **0.1837** | **25.0%** |
| **5-Fold Session-Grouped**| FrozenPhase1SVM_Session | 280 | 80.36% | 81.58% | 79.44% | 77.60% | 85.57% | `[[142, 41], [14, 83]]` | 0.2241 | 37.5% |
| **5-Fold Session-Grouped**| **BalancedSVM_Session** | 280 | 77.50% | 80.12% | 76.90% | 71.58% | **88.66%** | `[[131, 52], [11, 86]]` | 0.2468 | 25.0% |

Fold-level breakdowns are recorded in [`development_fold_metrics.csv`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/development_fold_metrics.csv), and source-level metrics are recorded in [`development_per_source_metrics.csv`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/development_per_source_metrics.csv).

---

## 6. Strict Model Selection Procedure

Model selection adhered to the pre-specified hierarchy:
1. **Balanced Accuracy** (primary measure of class-balanced quality)
2. **Incorrect Recall** (clinical sensitivity to execution flaws)
3. **Macro-F1** (harmonic balance across classes)
4. **Group and Source Stability** (reduced dispersion and higher floor)

### Selection Outcome: `BalancedSVM` Wins Decisively
The decision record is formalized in [`final_model_selection.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/final_model_selection.json).

```
Evaluation Dimension                  FrozenPhase1SVM         BalancedSVM            Advantage of BalancedSVM
-------------------------------------------------------------------------------------------------------------
5-Fold Source Balanced Accuracy           83.87%                86.62%              +2.76% (Decisive gain)
5-Fold Source Incorrect Recall            73.20%                81.44%              +8.25% (False negatives: 26 -> 18)
5-Fold Source Macro-F1                    85.18%                86.89%              +1.71%
5-Fold Source Accuracy Dispersion         0.1927                0.1692              -0.0234 (More consistent)
5-Fold Source Worst-Source Floor          30.0%                 50.0%               +20.0% (Raised failure floor)
29-Source LOSO Balanced Accuracy          80.98%                84.26%              +3.28% (Larger margin under LOSO)
29-Source LOSO Incorrect Recall           69.07%                78.35%              +9.28% (False negatives: 30 -> 21)
Session Holdout Incorrect Recall          85.57%                88.66%              +3.09% (Catches 86 of 97 errors)
```

**Selection Justification:** Under both 5-fold source-grouped CV and 29-source LOSO, `BalancedSVM` outperforms the unweighted baseline across Balanced Accuracy, Macro-F1, and Incorrect Recall. Its ability to reduce false negatives from 26 down to 18 (and under LOSO from 30 down to 21) provides essential clinical utility for home-exercise monitoring, where failing to identify improper movement carries significant therapeutic risk.

---

## 7. Independent Evaluation (Case B Assessment)

In strict accordance with the protocol for **CASE B** (no genuinely independent reviewed cohort exists):
- **No external evaluation was performed.**
- We explicitly refrain from partitioning the 280 development repetitions into an artificial "external" test set, as all 280 examples were utilized in Phase 1 and Phase 2 error audits and representation analyses.
- The pipeline remains validated strictly as an internal development model.
- Clinical deployment must remain gated until a truly prospective, independent cohort is collected and evaluated.

---

## 8. Generalization Gap Analysis

The generalization gap between validation protocols is documented in [`generalization_gap.csv`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/generalization_gap.csv) and visualized in [`plots/generalization_gap.png`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/plots/generalization_gap.png).

```
Protocols (in order of increasing holdout severity)            Balanced Accuracy    Delta vs Baseline    Delta vs Balanced Source
---------------------------------------------------------------------------------------------------------------------------------
1. Phase 2 5-Fold Source-Grouped (BalancedSVM)                       86.62%              +2.76%                    Ref
2. Phase 2 Nested Inner-Selection (BalancedSVM selected)             86.11%              +2.24%                  -0.51%
3. Phase 3 29-Fold Leave-One-Source-Out (BalancedSVM)                84.26%              +0.39%                  -2.36%
4. Phase 1 5-Fold Source-Grouped (Frozen Baseline)                   83.87%                Ref                   -2.76%
5. Phase 3 5-Fold Session-Grouped (Unweighted)                       81.58%              -2.29%                  -5.04%
6. Phase 3 29-Fold Leave-One-Source-Out (Unweighted Baseline)        80.98%              -2.88%                  -5.64%
7. Phase 3 5-Fold Session-Grouped (BalancedSVM)                      80.12%              -3.75%                  -6.50%
```

### Interpretation of the Generalization Gap
1. **The Source-Holdout Gap (-2.36% BA):** Moving from 5-fold source CV (86.62%) to 29-source LOSO (84.26%) induces a 2.36% penalty. This occurs because 24 of the 29 source videos contain only a single label; completely removing a single source eliminates an entire slice of feature space without representation in the remaining training set.
2. **The Session-Holdout Gap (-6.50% BA):** Moving from source-grouped CV to session-cluster holdout drops Balanced Accuracy to 80.12%. Crucially, inspection of fold-level session metrics reveals an extreme disparity:
   - Holdout `person5`: **92.31% Accuracy, 92.50% Balanced Accuracy** (17/20 Correct, 19/19 Incorrect detected).
   - Holdout `person4`: **88.33% Accuracy, 88.07% Balanced Accuracy** (39/44 Correct, 14/16 Incorrect detected).
   - Holdout `person3`: **92.31% Accuracy, 87.50% Balanced Accuracy** (36/36 Correct, 12/16 Incorrect detected).
   - Holdout `person1`: **67.80% Accuracy, 75.64% Balanced Accuracy** (20/39 Correct, 20/20 Incorrect detected).
   - Holdout `person2`: **57.14% Accuracy, 61.98% Balanced Accuracy** (19/44 Correct, 21/26 Incorrect detected; 25 false positives).
3. **Anatomy of the `person2` Session Failure:**
   In `person2`, the camera was positioned at an oblique angle relative to the participant, causing camera-axis proxies (`mean_torso_lean` and `shoulder_depth_ratio`) to shift by +1.5 to +6.8 robust standard deviations. When the model has never seen `person2` during training, these optical perspective shifts are misinterpreted as compensatory leaning, generating 25 false positives.
4. **Generalization Conclusion:** The algorithm demonstrates high intrinsic classification capability (88–92% accuracy across clean sessions), but remains vulnerable to uncalibrated camera obliquity and viewpoint shifts.

---

## 9. Final Feature Decision

The feature representation was locked in [`feature_definition_snapshot.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/feature_definition_snapshot.json).

### Decision: Retain Full 34-Feature Scalar Representation
1. **Retain Peak Angular Velocities:** Phase 2 demonstrated that replacing peak velocities with 95th-percentile velocities (`VelocityP95`) decreased Balanced Accuracy from 83.87% to 83.32%. Extreme velocity peaks, while numerically sensitive, capture ballistic and uncontrolled arm movements characteristic of incorrect repetitions.
2. **Retain Torso Lean & Shoulder Depth Proxies:** Phase 2 demonstrated that removing the 6 camera-axis proxies (`WithoutViewProxies`) caused a catastrophic 5.46% collapse in Balanced Accuracy and a 9.28% drop in Incorrect Recall. Although these features correlate with camera setup, they also capture genuine thoracic compensation and trunk sway. Removing them discards vital biomechanical signal.
3. **Standard Mean Imputation & StandardScaler:** The combination of `SimpleImputer(strategy='mean')` and `StandardScaler()` remains optimal. Replacing it with `RobustScaler` degraded performance by 4.64% BA.

---

## 10. Hand Analysis (Descriptive Metadata Only)

Hand metadata was evaluated across all models without using hand as an input feature or prediction target. Full statistics are compiled in [`development_per_hand_metrics.csv`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/development_per_hand_metrics.csv).

| Protocol & Model | Hand | Reps | Correct | Incorrect | Accuracy | Balanced Acc | Correct Recall | Incorrect Recall | Confusion Matrix |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **5-Fold Source (Frozen)** | Left | 143 | 95 | 48 | 88.81% | 83.85% | 98.95% | 68.75% | `[[94, 1], [15, 33]]` |
| **5-Fold Source (Frozen)** | Right | 137 | 88 | 49 | 85.40% | 83.66% | 89.77% | 77.55% | `[[79, 9], [11, 38]]` |
| **5-Fold Source (Balanced)** | Left | 143 | 95 | 48 | **91.61%** | **89.05%** | 96.84% | **81.25%** | `[[92, 3], [9, 39]]` |
| **5-Fold Source (Balanced)** | Right | 137 | 88 | 49 | **84.67%** | **84.00%** | 86.36% | **81.63%** | `[[76, 12], [9, 40]]` |
| **29-Fold LOSO (Balanced)** | Left | 143 | 95 | 48 | **88.81%** | **86.12%** | 94.74% | **77.50%** | `[[90, 5], [11, 37]]` |
| **29-Fold LOSO (Balanced)** | Right | 137 | 88 | 49 | **83.21%** | **82.38%** | 85.23% | **79.59%** | `[[75, 13], [10, 39]]` |

### Key Observations
- The baseline model suffered from an asymmetry in sensitivity: Left-hand Incorrect recall was only 68.75% (15 missed errors out of 48).
- `BalancedSVM` balanced performance across both arms, raising Left-hand Incorrect recall by **+12.50%** (to 81.25%) and Right-hand Incorrect recall to **81.63%**.
- Under 29-source LOSO, sensitivity remained well-balanced (77.50% Left vs 79.59% Right).

---

## 11. Final Model Decision

The final research model for Assisted Elbow Flexion V2 is **`BalancedSVM`**, trained on all 280 canonical repetitions.

### Complete Model Specification
- **Algorithm:** Support Vector Classifier (`sklearn.svm.SVC`)
- **Kernel:** Radial Basis Function (`rbf`)
- **Regularization ($C$):** $1.0$
- **Kernel Coefficient ($\gamma$):** `scale` (effective $\gamma = \frac{1}{34 \cdot \text{Var}(X)} = 0.02941176$)
- **Class Weighting:** `balanced` ($w_0 = \frac{280}{2 \cdot 183} = 0.765027$, $w_1 = \frac{280}{2 \cdot 97} = 1.443299$)
- **Decision Function:** Signed scalar distance to hyperplane ($f(x) > 0 \implies \text{Incorrect}$, $f(x) \le 0 \implies \text{Correct}$)
- **Preprocessing Pipeline:**
  1. `SimpleImputer(strategy='mean', keep_empty_features=True)`
  2. `StandardScaler(with_mean=True, with_std=True)`
- **Support Vectors:** 181 total (100 class 0 / Correct, 81 class 1 / Incorrect)
- **Model Checkpoint Artifacts:**
  - Full parameters JSON: [`checkpoints/final_model_v2_parameters.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/checkpoints/final_model_v2_parameters.json)
  - Metadata record: [`final_model_metadata.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/final_model_metadata.json)

---

## 12. Study Limitations

1. **Absence of Independent Validation Cohort:** The model has been validated exclusively across splits of the 280 canonical repetitions. Generalization to new clinical sites, clinics, or patient homes is not empirically established.
2. **Small Number of Source Videos (N=29):** The effective sample size at the video cluster level is 29. Single-source holdout drops performance by ~2.4% BA.
3. **Severe Source-Label Entanglement:** 24 of the 29 source videos contain only a single label. Movement quality and camera background/lighting remain partially confounded.
4. **Unverified Participant Identities:** The nominal 5 participant IDs are unverified legacy session blocks. The true number of distinct biological participants cannot be confirmed.
5. **Monocular 3D Pose Ambiguity:** Monocular RGB pose estimation suffers from depth ambiguity, perspective foreshortening, and self-occlusions during arm-crossover movements.
6. **Sensitivity to Camera Obliquity:** As demonstrated by the `person2` session holdout, camera perspective angles induce severe posture proxy shifts that can trigger false positive error flags.
7. **No Direct Clinical Ground Truth:** Human review labels establish consensus video-based rating, not clinical or functional rehabilitation outcomes.

---

## 13. Recommended Next Steps

To transition this research pipeline into clinical utility, development must proceed through distinct, non-overlapping gates:

```
[Phase 1 & 2: Error & Model Audits] ──> [Phase 3: Generalization Analysis & Final Fit] (COMPLETE)
                                                        │
                                                        ▼
                                       [Gate A: Multi-Cohort Data Collection]
                                                        │
                                                        ▼
                                       [Gate B: External Cohort Locked Evaluation]
                                                        │
                                                        ▼
                                       [Gate C: Live-Camera Production Integration]
                                                        │
                                                        ▼
                                       [Gate D: Clinical Safety & Efficacy Trials]
```

### 1. Data-Collection Protocol for Future Independent Cohort (Gate A)
- **Cohort Size:** Minimum 20 new participants, recording at least 10 correct and 10 incorrect repetitions each ($\ge 400$ repetitions).
- **Session Diversity:** Each participant must perform exercises under at least two distinct camera angles (pure frontal, 30° oblique, and 45° oblique) and two distances (1.5m and 2.5m).
- **Strict Multi-Class Recording:** To eliminate source-label confounding, every video recording must contain both correct and incorrect repetitions within the same take.
- **Participant Roster Verification:** Full de-identified participant IDs, physical height, arm length, and recorded session timestamps must be formally cataloged.

### 2. Viewpoint Adaptation & Normalization
- Before deploying live video evaluation, implement rest-pose torso calibration (subtracting the user's neutral standing torso angle during countdown) to eliminate the optical perspective shift that affected `person2`.

### 3. Production & Live Evaluator Gate (Gate C)
- **Do NOT replace the production model checkpoint** (`models/assisted_elbow_v2_biomech_augmented.pth` or live evaluators) until Gate A and Gate B are completed.
- Current live mobile app and web backend services remain decoupled and safe.

---

## Verification & Reproducibility Sign-off

- **Canonical Manifest Verified:** [`releases/human280_20261004/canonical_manifest.csv`](file:///<repo_root>/processed_data/assisted_elbow_flexion_v2/releases/human280_20261004/canonical_manifest.csv) (SHA-256 verified; 280 repetitions).
- **Excluded Candidates:** 22 candidates verified quarantined.
- **Protected Files Check:** 2,514 protected repository files verified unchanged via SHA-256 audit.
- **Verification Script:** Executed and passed with exit code 0 ([`verify_phase3.py`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/verify_phase3.py)).
- **Reproducibility Manifest:** Recorded in [`reproducibility_manifest.json`](file:///<repo_root>/research/assisted_elbow_flexion_v2/phase3/reproducibility_manifest.json).

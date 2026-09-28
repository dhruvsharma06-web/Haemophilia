# Assisted Elbow Flexion - Assessment & Machine Learning Pipeline Guide

This document describes the biomechanical evaluation engine, repetition annotation infrastructure, and experimental machine learning pipeline for **Assisted Elbow Flexion** in the Haemophilia physiotherapy system.

---

## 1. Executive Summary & Current Evidence Status

A rigorous Leave-One-Subject-Out Cross-Validation (LOSO-CV) diagnostic audit across all 3 subjects (14 labelled videos, 153 accepted repetitions) established the following empirical findings:

1. **Learned Models Do Not Generalize Reliably Across Subjects**:
   - Under true LOSO-CV, all statistical models (LSTM, Random Forest, Logistic Regression, GRU) perform below the 59.48% whole-dataset majority baseline.
   - The LSTM achieved **55.56% aggregate accuracy, 51.07% balanced accuracy, and 50.00% Macro-F1**, exhibiting severe majority-class prediction collapse (predicting 100% "Correct" on Person 2, capturing only 27.4% of true errors).
   - Random Forest achieved **54.25% aggregate accuracy and 56.40% balanced accuracy**, collapsing on Person 3 (0.0% correct recall).
   - This failure is caused by an over-parameterized model trained on only $N=3$ subjects, where classifiers memorize subject-specific posture artifacts rather than generalizable error manifolds.

2. **Video-Level Folder Labels Contain Substantial Repetition-Level Noise**:
   - Folders were labelled at the video level (e.g., "Right hand assisted wrong").
   - Detailed kinematic auditing revealed that **16.1% of repetitions in "incorrect" videos actually demonstrate good form**, and **14.3% of repetitions in "correct" videos exhibit severe deficits** (e.g. ROM < 30° or shallow flexion > 105°).
   - This ~15% label discordance injects severe noise into supervised gradient descent.

3. **Deterministic Biomechanical Baseline Outperforms All Learned Models**:
   - A transparent rule-based evaluator calibrated strictly on training folds achieves:
     * **Accuracy: 75.16%**
     * **Balanced Accuracy: 73.72%**
     * **Macro-F1: 73.95%**
     * **Correct Recall: 81.32% | Incorrect Recall: 66.13%**
   - **Important Note**: Do NOT advertise 75.16% as "ML accuracy". It is strictly the **Deterministic biomechanical LOSO baseline**.

4. **Interim Architecture & Future ML Roadmap**:
   - If an academic or project specification requires a trained ML model, rule-based systems are NOT a permanent replacement.
   - However, training deep networks on unverified folder labels produces invalid models. The correct development lifecycle is:
     ```text
     Current dataset (153 reps)
           ↓
     Human repetition-level clinical annotation (`repetition_annotations.csv`)
           ↓
     Verified supervised dataset (excluding ambiguous samples)
           ↓
     Train ML model (LSTM / GRU) with zero-leakage subject splits
           ↓
     True cross-subject validation (LOSO-CV)
           ↓
     Final production ML model
     ```
   - In the interim, the system exposes **two explicitly separated evaluation outputs**:
     * **Biomechanical / Rule-Based Assessment** (current production evaluator)
     * **Learned ML Prediction** (retained for research and future retraining)

---

## 2. Dataset & Directory Layout

### Dataset Location
```text
Assisted elbow flexion/
├── Both hand assisted correct/     # 2 videos (Persons 1 & 2) - Bilateral assisted
├── Both hand assisted mix/         # 4 videos (EXCLUDED from supervised training)
├── Left hand assisted correct/     # 3 videos (Persons 1, 2, & 3) - Left active, right assisting
├── Left hand assisted wrong/       # 3 videos (Persons 1, 2, & 3) - Left active with compensation
├── Right hand assisted correct/    # 3 videos (Persons 1, 2, & 3) - Right active, left assisting
└── Right hand assisted wrong/      # 3 videos (Persons 1, 2, & 3) - Right active with compensation
```

---

## 3. Biomechanical Feature Representation (8 Canonical Dimensions)

Features are canonicalized to **Active Arm** and **Assisting Arm** semantics. Landmark visibility has been removed from the learned feature vector (retained purely for frame quality control):

| Index | Feature Name | Biomechanical Description | Normalization |
|---|---|---|---|
| 0 | `active_elbow_angle` | 3D joint angle at active elbow (`shoulder → elbow → wrist`) | Angle / `180.0` |
| 1 | `assisting_elbow_angle` | 3D joint angle at assisting elbow | Angle / `180.0` |
| 2 | `active_elbow_velocity` | First derivative across frames of active elbow angle | Vel / `180.0`, clipped to `[-1.5, 1.5]` |
| 3 | `assisting_elbow_velocity` | First derivative across frames of assisting elbow angle | Vel / `180.0`, clipped to `[-1.5, 1.5]` |
| 4 | `torso_tilt` | Angle between shoulder midpoint and hip midpoint from vertical | Tilt / `3.0` (calibrated on training P99 distribution) |
| 5 | `torso_rotation` | Landmark depth ratio `(rs.z - ls.z) / shoulder_width` | Rotation / `15.0` |
| 6 | `active_elbow_flare` | Lateral displacement `abs(elbow.x - shoulder.x) / W_ref` | Normalized by robust reference shoulder width $W_{\text{ref}}$ |
| 7 | `assisting_elbow_flare`| Lateral displacement `abs(elbow.x - shoulder.x) / W_ref` | Normalized by robust reference shoulder width $W_{\text{ref}}$ |

### Robust Shoulder Width Normalization
To prevent extreme flare spikes when landmarks collapse during assisting-hand occlusion, flare is normalized by $W_{\text{ref}} = \text{median}(\{W_i \mid \text{vis}>0.5, W_i > 0.05\})$. Instantaneous widths below $0.5 \times W_{\text{ref}}$ fallback to $W_{\text{ref}}$.

---

## 4. Repetition Segmentation & Audit

In `src/feedback/assisted_elbow_rep_counter.py`:
- **Constrained Search Window**: $\max(\text{last\_end\_frame}, \max(0, t - \text{lookback}))$ prevents temporal overlap with prior repetitions.
- **Configurable Parameters**: All parameters (`min_rom=20.0°`, `min_duration_sec=0.8s`, `debounce_sec=0.3s`, `fps`) are dynamically configurable.
- **Audit Results**: 209 detected, 153 accepted (91 correct, 62 incorrect), 56 rejected (46 `HIGH_DEBOUNCE_OVERLAP`, 10 `INSUFFICIENT_ROM`). 0 NaNs or Infs.

---

## 5. Production Assessment Engine (`src/exercises/assisted_elbow_flexion.py`)

The live engine outputs a repetition dictionary with explicitly separated evaluation blocks:

```json
{
  "exercise": "Assisted Elbow Flexion",
  "rep_number": 1,
  "primary_assessment_method": "biomechanical_rules",
  "form": "Correct",
  "score": 86.5,
  "feedback": "Acceptable movement: good flexion depth and controlled elbow alignment.",
  "biomechanical_assessment": {
    "status": "Correct",
    "rule_passed": true,
    "violations": [],
    "feedback": "Acceptable movement: good flexion depth and controlled elbow alignment.",
    "metrics": {
      "min_elbow_angle": 92.4,
      "max_elbow_angle": 138.1,
      "rom": 45.7,
      "peak_elbow_flare": 0.22,
      "peak_torso_tilt": 1.2,
      "duration": 3.1,
      "smoothness": 0.42
    },
    "thresholds_used": {
      "max_flexion_angle": 101.0,
      "max_elbow_flare": 0.30,
      "min_rom": 25.0
    }
  },
  "learned_ml_prediction": {
    "available": true,
    "predicted_class": "Correct",
    "confidence_pct": 82.4,
    "model_architecture": "ExerciseLSTM (2-layer, 8-feature)",
    "evaluation_note": "Research/experimental; true LOSO demonstrates 51.1% balanced accuracy on 3 subjects."
  }
}
```

### Configurable Biomechanical Thresholds:
- `max_flexion_angle_threshold`: default `101.0°` (training fold calibration boundary)
- `max_elbow_flare_threshold`: default `0.30` (training fold calibration boundary)
- `min_rom_threshold`: default `25.0°` (ensures non-trivial active excursion)
- `max_torso_tilt_threshold`: default `5.0°`
- `max_torso_rotation_threshold`: default `15.0°`

*Clinical Disclaimer*: These rules represent empirical engineering thresholds derived from training folds; they are not clinically certified diagnostic criteria.

---

## 6. Repetition-Level Annotation Infrastructure

To prepare the dataset for valid future ML training, a machine-readable annotation repository is established at:
`processed_data/assisted_elbow_flexion/repetition_annotations.csv`

### Schema:
```text
subject_id
video_name
repetition_index
assistance_type
folder_label             (Preserved original coarse folder label)
ground_truth_label       (STRICTLY blank/null until human clinician review)
error_tags               (e.g., insufficient_flexion, excessive_elbow_flare, poor_control)
annotator                (Reviewer ID)
notes                    (Observations / reason for exclusion)
start_frame, end_frame, duration_sec, rom, min_elbow_angle, max_elbow_angle, elbow_flare, torso_tilt
```

### Interactive Annotation Tool:
```bash
# Check progress and folder-label agreement
python src/annotation/review_elbow_annotations.py --stats

# Launch interactive CLI review
python src/annotation/review_elbow_annotations.py --annotator dr_smith

# Filter by subject
python src/annotation/review_elbow_annotations.py --subject person1

# Export reviewed clean dataset for future ML training
python src/annotation/review_elbow_annotations.py --export-clean data/clean_elbow_train.csv
```

---

## 7. Retraining the ML Model (Future Workflow)

Once clinical annotations are populated:
```bash
python src/training/train_assisted_elbow_lstm.py --annotations processed_data/assisted_elbow_flexion/repetition_annotations.csv --epochs 50
```
The training script will automatically:
1. Filter for reviewed `ground_truth_label` entries (`correct` vs `incorrect`).
2. Exclude `ambiguous` and unreviewed repetitions.
3. Train with zero Person 3 leakage.
4. Guarantee that deterministic rule outputs are NEVER used as pseudo-labels.

---

## 8. Preserved ML Artifacts

All components of the ML infrastructure remain intact and active:
- `models/assisted_elbow_lstm.pth` (PyTorch LSTM checkpoint)
- `models/assisted_elbow_config.json` (architecture and normalization parameters)
- `src/features/assisted_elbow_features.py` (8-feature canonical extractor)
- `src/training/create_assisted_elbow_sequences.py` (128-frame sequence generator)
- `src/training/train_assisted_elbow_lstm.py` (leakage-audited training pipeline)
- `src/inference/evaluate_assisted_elbow_lstm.py` (evaluation and LOSO-CV engine)

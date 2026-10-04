# Assisted Elbow Flexion V2: Phase 4 Live Pipeline Audit

**Date:** 2026-10-04  
**Status:** Complete  
**Scope:** Strict read-only audit of existing live inference pipelines, repetition segmenters, and model-loading mechanisms. No production code was modified during this audit.

---

## Executive Summary

An exhaustive inspection of `live_elbow_camera.py`, `src/exercises/assisted_elbow_flexion.py`, `backend/app/services/model_registry.py`, `src/feedback/assisted_elbow_rep_counter.py`, and `scratch/live_elbow_camera_v2.py` reveals that **the existing live camera pipeline is completely incompatible with the Phase 3 authoritative `BalancedSVM` model**.

Specifically:
1. The production live pipeline is wired to an obsolete 8-channel temporal `ExerciseLSTM` checkpoint (`assisted_elbow_lstm_human_verified.pth`) and hardcoded heuristic rules, rather than the 34 biomechanical scalar features learned in Phase 3.
2. The live pipeline assumes a fixed 30.0 FPS and measures repetition duration by frame count division (`len(buffer) / 30.0`), while offline rep counters and experimental runners suffered from search-window and timestamp indexing errors that generated negative repetition durations.
3. MediaPipe landmarks in the live runner use screen-normalized 2D/pseudo-3D coordinates (`results.pose_landmarks`), whereas Phase 1/2/3 feature extraction used metric world coordinates (`results.pose_world_landmarks`).
4. Active arm selection in the live runner relies on an unverified automatic state machine attempting "both_hand_assisted", whereas the canonical V2 dataset strictly defines hand as `Left` or `Right` (the exercised arm).

---

## Detailed Audit Questions & Findings

### 1. What landmarks are extracted?
- **In `src/features/assisted_elbow_features.py` / `live_elbow_camera.py`:**
  Extracts 8 landmarks from `mp.solutions.pose.Pose`:
  - Shoulders: Left (11), Right (12)
  - Elbows: Left (13), Right (14)
  - Wrists: Left (15), Right (16)
  - Hips: Left (23), Right (24)
- **Coordinate Space Discrepancy:**
  - `live_elbow_camera.py` passes `results.pose_landmarks` (image-relative normalized coordinates $[0, 1]$ in x, y, and scaled z).
  - In contrast, the Phase 1 canonical pipeline (`preprocessing/extract_landmarks.py` and `features/build_features.py`) extracted and used `results.pose_world_landmarks` (metric 3D Cartesian coordinates in meters centered at the hip midpoint).
  - Normalizing by shoulder width in 2D image coordinates vs 3D world meters produces scale discrepancies for flare, lean, and shoulder depth ratio.

### 2. How left/right arms are represented?
- In `extract_frame_kinematics` (`src/features/assisted_elbow_features.py`), kinematics are calculated symmetrically for both sides:
  - `left_angle = compute_angle_3d(ls, le, lw)`
  - `right_angle = compute_angle_3d(rs, re, rw)`
  - `left_flare = abs(le[0] - ls[0]) / shoulder_width`
  - `right_flare = abs(re[0] - rs[0]) / shoulder_width`
- In `map_canonical_features`, these are mapped into `active_*` and `assisting_*` fields based on `assistance_type`.
- In Phase 3 canonical features (`features/build_features.py`), the exercised arm is designated `active` and the assisting arm is designated `opposing`, calculating 34 scalars across both arms.

### 3. How the active/exercised hand is selected?
- In `live_elbow_camera.py` and `assisted_elbow_flexion.py`:
  - Defaults to `assistance_type="both_hand_assisted"`.
  - The live engine tracks independent candidate states for `left` and `right`. If both finish, it tags the rep as `both`. If only one arm moves through ROM $\ge 25^\circ$, it assigns `left` or `right`.
  - When `mode == "both"`, `map_canonical_features` maps `active` to Left and `assisting` to Right, averaging visibility.
- **Critical Flaw:** The canonical V2 dataset contains exactly 280 repetitions classified strictly as `hand = "Left"` (143) or `hand = "Right"` (137). There is no "both" category. In assisted elbow flexion, the patient exercises one arm while the other assists. Treating "both" as a mode corrupts the active vs opposing feature assignment.
- **Phase 4 Requirement:** Explicit user-selectable active hand (`Left` or `Right`) must be provided to ensure deterministic feature mapping.

### 4. How repetitions start/end?
- In `assisted_elbow_flexion.py`:
  - **Start:** Arm begins in `EXTENDED`. When elbow angle drops below `DEFAULT_FLEXION_THRESHOLD` ($110.0^\circ$), state transitions to `FLEXING`, recording `start_frame`.
  - **Turnaround:** In `FLEXING`, when angle increases by $\ge 12.0^\circ$ from the minimum observed angle, state transitions to `EXTENDING`.
  - **End:** In `EXTENDING`, when angle rises back above `DEFAULT_START_EXTEND_ANGLE` ($120.0^\circ$), state transitions to `COMPLETED_CANDIDATE`.
  - **Validation:** If range of motion ($\text{ROM} \ge 25.0^\circ$) and buffer length ($\ge 15$ frames), repetition is finalized.
- In `assisted_elbow_rep_counter.py`:
  - Peak-detection (`scipy.signal.find_peaks` on inverted smoothed angle signal `-angles_s`).
  - Searches backward for start inflection and forward for end inflection within bounded windows.

### 5. How repetition duration is calculated?
- In `assisted_elbow_flexion.py`:
  `duration = len(rep_k) / self.fps` (where `rep_k` is the collected frame buffer).
- In `assisted_elbow_rep_counter.py`:
  `duration = (rep_end - rep_start) / self.fps`.
- In experimental/scratch runners and live timing bugs:
  - Where start/end frames were computed via argmax over overlapping search windows (`rep_start = start_window + np.argmax(...)`), edge cases or debounce overlaps allowed `rep_start > rep_end`, causing **negative duration**.
  - Additionally, using `cap.get(cv2.CAP_PROP_POS_MSEC)` on Windows DSHOW webcams returns `-1` or `0`, causing timestamp subtraction failures.

### 6. How FPS/timestamps are handled?
- In `live_elbow_camera.py`:
  - Hardcoded parameter: `fps = 30.0`.
  - No real-time wall-clock or presentation timestamping is performed during capture.
  - If a webcam runs at 15 FPS or 20 FPS (common under high-resolution or low-light conditions), dividing frame counts by 30.0 underestimates repetition duration by up to 50% and inflates angular velocity by up to 200%.
- **Phase 4 Requirement:** Repetition segmentation and feature calculations must record actual monotonic timestamps (`time.perf_counter()`) per frame, computing true elapsed seconds.

### 7. What features are currently calculated?
- The live pipeline calculates an 8-channel temporal sequence:
  1. `active_elbow_angle`
  2. `assisting_elbow_angle`
  3. `active_elbow_velocity`
  4. `assisting_elbow_velocity`
  5. `torso_tilt`
  6. `torso_rotation`
  7. `active_elbow_flare`
  8. `assisting_elbow_flare`
  Resampled to a fixed length of 128 timesteps using linear interpolation.

### 8. Whether those features are identical to Phase 3?
- **NO.** They are fundamentally different:
  - The live pipeline outputs a $(128, 8)$ sequence matrix.
  - Phase 3 requires **34 exact biomechanical scalar features** defined in `feature_definition_snapshot.json` (active/opposing min/max/ROM, duration, peak/mean velocities, mean/max flares, angle and flare asymmetries, torso lean mean/max/range, shoulder depth ratio mean/max/range, flexion/extension durations and excursions, net speeds).
  - Feeding the $(128, 8)$ representation into Phase 3's `BalancedSVM` is impossible without the Phase 3 feature adapter.

### 9. Which model the current live pipeline actually loads?
- `model_registry.py` and `assisted_elbow_flexion.py` attempt to load:
  - Primary path: `models/assisted_elbow_lstm_human_verified.pth` (an `ExerciseLSTM` PyTorch model: 8 input channels, 64 hidden units, 2 layers, 2 classes).
  - Fallback: Hardcoded biomechanical rules (`primary_evaluator="biomechanical_rules"` with thresholds: angle $\le 101.0^\circ$, flare $\le 0.30$, $\text{ROM} \ge 25.0^\circ$).
- The live camera never loads or references any SVM model, and has no support for `BalancedSVM`.

### 10. Whether the old 8-channel sequence pipeline is still being used?
- **YES.** The entire production live camera stack (`live_elbow_camera.py`, `AssistedElbowFlexionAssessment`, `build_normalized_sequence`, `ExerciseLSTM`) remains 100% bound to the legacy 8-channel representation.

---

## Action Plan for Phase 4

1. **Keep Production Untouched:**
   Do not modify `live_elbow_camera.py`, `src/exercises/assisted_elbow_flexion.py`, `backend/app/services/model_registry.py`, or any files in `models/`.
2. **Build Standalone Research Deployment Adapter (`deployment_adapter.py`):**
   - Implement the exact 34-feature extraction from 3D world pose landmarks (and robust normalized landmarks fallback).
   - Recreate the exact Phase 3 `SimpleImputer` $\to$ `StandardScaler` $\to$ `BalancedSVM` inference mathematically using the frozen parameters JSON.
3. **Verify Offline Numerical Parity (`offline_parity_report.md`):**
   - Benchmark adapter predictions against canonical development targets and Phase 3 frozen outputs.
4. **Build Research Live Runner (`live_elbow_camera_v2.py`):**
   - Monotonic time tracking (`time.perf_counter()`).
   - Clean state machine guaranteeing `end_time > start_time` and `duration > 0`.
   - Explicit user selection of active hand (`Left` / `Right`).
   - Diagnostic display with real signed decision score and label (`Correct` / `Incorrect`) without fake confidence percentages.

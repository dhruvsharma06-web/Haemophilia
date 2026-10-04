# Fresh world kinematics v1.2

Input is every decoded frame in each exact zero-based, inclusive human-reviewed range, in original source presentation order. World xyz is MediaPipe's estimated metric coordinate system centered at the hips. These monocular estimates are not calibrated joint motion measurements. Raw image xyz and visibility are retained separately for audit. All features below use world coordinates; hand selects active/opposing joint indices only. Hand, source, folder, subject, label, QC flags and repetition IDs are never model inputs.

The six base signals use shoulders 11/12, elbows 13/14, wrists 15/16 and hips 23/24. The left tuple is (11,13,15), right (12,14,16). `Left` means the left arm is being exercised.

| Temporal channel | Exact definition | Units |
|---|---|---|
| active_angle, opposing_angle | arccos of the clipped normalized dot product of shoulder−elbow and wrist−elbow; degenerate vectors invalid | degrees, 0–180 |
| active_flare, opposing_flare | absolute projection of elbow−shoulder onto the unit right−left shoulder axis, divided by 3D shoulder width | dimensionless ratio |
| torso_lean | atan2(norm of horizontal/depth components of midpoint(shoulders)−midpoint(hips), absolute vertical component) | degrees, 0–90; camera-coordinate proxy |
| shoulder_depth_ratio | absolute right−left shoulder depth difference / 3D shoulder width | ratio, 0–1; camera-orientation proxy, NOT rotation degrees |
| active_velocity, opposing_velocity | central finite differences via `np.gradient(angle, actual_source_PTS)`; one-sided endpoints | degrees/second |
| angle_asymmetry | absolute active−opposing elbow angle | degrees |
| flare_asymmetry | absolute active−opposing flare | ratio |
| elapsed_seconds | current source PTS minus first PTS of this repetition | seconds |

The model sequence has **128 × 11** values. After validity checks and bounded repairs, each channel is linearly resampled at 128 equally spaced actual times from the first to last frame PTS. This time-grid resampling is separate from missing-value repair. No smoothing, clipping, old normalization constants, or synthetic augmentation is applied. Signed velocity distinguishes flexion (decreasing elbow angle) from extension. Elapsed seconds preserves duration despite time normalization.

The scalar vector has **34 values**, in this order:

1. Active angle minimum, maximum, range (max−min), then opposing minimum, maximum, range: 6 degrees-valued features.
2. Duration: last frame presentation END minus first frame START, seconds. This includes the final frame's display interval, matching the canonical duration.
3. Active peak absolute angular velocity and time-weighted mean absolute angular velocity, then the opposing pair: 4 degrees/second features.
4. Active mean and maximum flare, then opposing mean and maximum flare: 4 ratios.
5. Mean and maximum angle asymmetry: 2 degrees-valued features; mean and maximum flare asymmetry: 2 ratios.
6. Mean, maximum and range of torso lean: 3 degrees-valued features; mean, maximum and range of shoulder depth ratio: 3 ratios.
7. Flexion duration, extension duration and flexion fraction: 3 features. Phase boundary is the first global minimum active elbow angle within the reviewed range. Flexion is from first frame PTS to minimum PTS; extension is minimum PTS to last frame PTS. Fraction divides flexion time by first-to-last PTS span. This is an operational phase proxy; multiple peaks, padding and endpoint minima can make it imperfect.
8. Active start/end angle: 2 degree features.
9. Flexion excursion (start−minimum), extension excursion (end−minimum): 2 degree features.
10. Flexion/extension net speed: respective excursion/phase duration, degrees/second; zero for a zero-duration phase, explicitly flagged in QC by endpoint minimum.

All means are time-weighted trapezoidal integrals divided by first-to-last PTS span. Peaks and ranges use original-frame kinematics, not the resampled grid.

## Missing data and validation

Each base feature requires all of its participating joints to have finite xyz and visibility ≥0.5. Flare also requires both shoulders; torso lean requires both shoulders and hips. Invalid/absent detections and degenerate vectors are NaN, never zero landmarks. A channel must have at least 80% original validity to qualify for bounded repairs. An internal missing run may be linearly interpolated only if its bracketing valid timestamps are ≤0.50 seconds apart. A missing endpoint run may be held at the nearest valid value only within 0.10 seconds. Every repaired channel/run/frame range is written to `repair_operations.csv`; raw and repaired signals are retained together. Unsupported intervals remain NaN, and the repetition is explicitly marked partial rather than dropped.

The initial 0.25-second internal cap failed one low-visibility wrist gap (0.466467 seconds between valid support frames). Before any learned-model fit or result inspection, the cap was uniformly revised to 0.50 seconds; all other gates, features, folds and hyperparameters stayed unchanged. The original protocol and initial failure evidence are preserved under `provenance/protocol_before_qc_revision` and `qc_before_policy_amendment.json`; the decision is in `pretraining_quality_amendment.json`. This engineering tolerance is not clinically validated and interpolation may omit real dynamics in that interval.

Two further repetitions fail the unchanged 80% validity or endpoint limit. A second preprocessing amendment, recorded before any model fitting in `pretraining_fold_imputation_amendment.json`, retains their unsupported values as NaN. A scalar summary requiring an incomplete channel stays NaN instead of being asserted as a complete range or time integral. Phases are unavailable when the active-angle channel is incomplete; valid endpoint angles and independent opposing/torso features remain available. Derivatives adjacent to missing samples propagate NaNs. Resampling propagates NaNs across unsupported intervals; no long interpolation or endpoint extension is fabricated.

Before training: require exactly 280 arrays, expected feature shapes, exact canonical ID ordering and valid source/frame provenance. Pre-fold data have 33 scalar and 202 temporal NaNs across two partial repetitions, with zero Inf. Each classical pipeline fits a per-feature mean imputer on only its outer training repetitions. The UniLSTM fits a per-channel mean imputer on only training repetitions and timesteps. No missingness indicator is included. Transformed training/validation model inputs must be finite. Imputer means, missing counts, fit membership and scaler parameters are saved. Distribution tables describe finite observed/repaired values and count remaining NaNs separately. Outliers are descriptive only, never removed or used to choose features after evaluation.

After training-fold imputation, LR/SVM StandardScaler fits only the outer training rows. Trees use imputed physical-unit scalar features without scaling. UniLSTM StandardScaler fits imputed outer training repetitions and timesteps only. Each fold's means, scales, fitted row/timestep counts and imputation parameters are independently verified. No labels or held-out data determine formulas, imputer values or scaler parameters. Mean imputation is a statistical substitute for model input, not a claim that the missing movement was measured.

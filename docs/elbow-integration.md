# Elbow exercise integration — 2026-10-07

## Current app configuration

Assisted elbow flexion uses the trained V5 SVM with the V6 cycle controller and measured telemetry (`SVM_V5_Controller_V6_Telemetry2`). Only this assisted-elbow option appears in the exercise catalogue. Legacy assisted-elbow prescriptions resolve to it. The V2 source and model export remain in the repository for reference.

Elbow flexion and extension uses the complete `ai-elbow-model-v1` branch from `arvindshekhawat-techie/haemophilia-final`, commit `0c37549fe26015f0ddfc25e9e3876b7e21616714`. The V4 checkpoint accepts 30 frames with 22 features from right-arm normalized image XY landmarks. Zero padding occurs at the end before the supplied normalization. Model assets and feature construction are recorded in `models/elbow_v4_provenance.json`. The original V3 adapter and checkpoint are retained.

Both active elbow adapters use timestamp-based movement handling, tracking guards, bounded buffers, feedback and annotated review frames. Saved patient/doctor reports expose measured movement statistics where available. The movement-control score is descriptive; it is not a clinical score or calibrated model confidence. Independent unseen-participant accuracy above 90% has not been established.

Run the current software checks with `python -m pytest backend/tests -q`. The live backend release is `2026-10-07-session-expiry-elbow-v4`. See `docs/RELEASE_2026_10_07.md` for the session workflow and deployment status.

## Historical integration — 2026-10-05

The following describes the previous V2/V3 configuration. It is retained for provenance and does not describe the active exercise catalogue.

Assisted elbow flexion uses the frozen 34-feature world-coordinate BalancedSVM from b4b86de. The original imputation, scaling, support vectors, decision rule, and feature order are retained. The supplied augmented causal segmenter groups movement into cycles. Bilateral overlapping cycles count once. Missing or poorly visible landmarks discard a partial cycle. A positive margin means Incorrect, and a non-positive margin means Correct. This model does not provide a calibrated percentage score or confidence.

Elbow flexion and extension uses the V3 LSTM from a252160 with the exact realtime_test.py feature construction (25 frames, 14 features), its decision thresholds and recent-prediction averaging. The app adapter retains complete flexion/extension cycle counting, visibility safeguards, bounded buffers and the stable API contract. It locks the visible arm during a repetition.

Both exercises are available in live camera and uploaded-video assessment. The existing shoulder models remain in the registry. Practice assessments write no artifacts. Session history retains model identity and SVM decision margin when supplied. Software checks do not establish clinical accuracy.

Run checks with `python -m pytest backend/tests/test_elbow_integration.py -q` from the repository root. Use Python 3.12, MediaPipe 0.10.21 and NumPy 1.26.4 on the VM. Do not replace MediaPipe with a version lacking the solutions API. Use a CPU Torch installation on the CPU VM.

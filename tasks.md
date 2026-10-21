
# Project Progress

## Completed
- AI development environment configured.
- Initial architecture and existing-test review completed on 2026-10-20.
- Baseline checks passed: 44 backend tests, 15 Python workflow tests, and 133 Flutter tests.

## In Progress
- On-device angle-threshold assessment replacing the LSTM models. The user confirmed the direction on 2026-10-21: processing runs on the phone, and each exercise gets measured angle thresholds from supplied files rather than a trained classifier.
- Scope: all upper-body exercises **except** assisted shoulder flexion with the wand. Assisted shoulder flexion keeps its existing path.
- Delivered 2026-10-21: elbow flexion and extension, then shoulder rotation. See their sections below.

## Pending
- Awaiting the threshold files for the remaining upper-body exercise (assisted elbow flexion) and confirmation of how assisted shoulder flexion should stay unchanged.
- Shoulder rotation's numbers are proposed engineering settings, not measurements. They need the recording review the report itself asks for before any patient use.
- Device validation on a real phone for every converted exercise: labelled recordings, left/right identification, mirroring, occlusion, performance and threshold-boundary cases.
- Lower-body angle smoothing and clinical calibration remain outstanding, unchanged by this work.

## Shoulder rotation (2026-10-21)
- Source: `Shoulder_Rotation_Threshold_Report.pdf`, a draft engineering specification dated 2026-10-15. Bundled in `docs/calibration/shoulder-rotation.json`.
- Unlike the elbow file, this is a specification rather than measurements. Only the elbow bend range (60-120°, target 90°) and the 12° sideways lean are retained from the previous implementation; all other limits are proposed starting settings, and the report says so explicitly.
- The report warns the old counting values 8, 10, 3, 15 and 20 were normalized displacement units, not degrees. None were converted. The unused 15° minimum-excursion and 25° left/right ROM difference constants were not adopted.
- Engine: `haemophilia_app/lib/services/shoulder_rotation_assessment.dart`, dispatched when the exercise is `shoulder_rotation`. Torso-relative body frame from world landmarks, forearm-azimuth proxy, ±5° centre band, 20° extreme held 0.15 s, 0.5 s neutral calibration, 20% posture persistence, 0.7 visibility, intentional tracking-gap abandonment.
- Enables `worldPose` for this exercise, so it shares the native MediaPipe path added for the elbow.
- Replaces the legacy camera-azimuth proxy and its old `ROTATION_DIRECTION` / `INCOMPLETE_RETURN` codes; the legacy fixture tests for those were updated to assert that path no longer produces a verdict.
- Tests: 22 direct engine tests plus 5 integration assertions. Whole suite 184 tests.

## Elbow flexion and extension (2026-10-21)
- Source files: `mediapipe_angle_thresholds.json`, `angle_statistics.csv`, `reviewed_rep_measurements.csv` (22 approved reps, one session, `person_specific_candidate`). Bundled values are in `docs/calibration/elbow-flexion-extension.json`; raw reviewed CSV data is not shipped in the app.
- Verified the bundled constants reproduce the supplied statistics exactly: `flexion_max_deg` = p90 of the per-rep minimum + 5, `extension_min_deg` = p10 of initial/final − 5, `rom_min_deg` = p10 of ROM − 5, `return_error_max_deg` = p90 of return error + 5, and the bilateral limits are the p90 of the per-rep maxima. The 5-degree margins are the source method's engineering allowances.
- Engine: `haemophilia_app/lib/services/elbow_world_assessment.dart`, dispatched from `ExerciseRulesAssessment.update` when the exercise is `elbow_flexion_extension`. Measures shoulder-elbow-wrist in MediaPipe world metres, causal low-pass with tau 0.08 s, per-arm thresholds, bilateral angle/ROM limits, 0.3 s ready and 0.2 s target/return holds.
- Fixed a blocking defect: the return gate required both arms to satisfy `returned` on the same frame, which never latched when the two arms had different extension floors (left 152.59 vs right 153.62), so repetitions never completed and no rep was ever recorded.
- Fixed a threshold-boundary defect: the low-pass filter converges asymptotically, so a hold exactly at a displayed threshold settled a few thousandths of a degree short and was rejected. A 0.05-degree numerical tolerance now applies to the extension, flexion, return and ROM comparisons. This is a convergence tolerance, not a clinical or jitter margin.
- Native: the bridge previously returned only ML Kit image landmarks, so the elbow exercise would have reported `tracking_valid: false` permanently on a real phone. `LocalPoseBridge` now runs MediaPipe Tasks (`tasks-vision`) with the bundled `pose_landmarker_lite.task` for this exercise only and returns `world_landmarks` plus `angle_source`. Both models are created lazily.
- Tests: 163 Flutter tests pass, including 25 direct `ElbowWorldAssessment` tests and 5 integration tests. `flutter analyze lib test` reports no issues. `:app:compileDebugKotlin` succeeds.

## Architecture Baseline
- Active Flutter application: `haemophilia_app/lib/main.dart`, role-based routing in `screens/auth/auth_gate.dart`, and clinical services in `lib/services/`.
- Android live exercise assessment runs on-device through `lib/services/local_pose_service.dart`, the native ML Kit bridge, and the Flutter upper/lower-body rule engines. Normal live camera frames are not sent to the Python backend; see `docs/on-device-assessment.md`.
- FastAPI entry point: `backend/app/main.py`. Uploaded video and legacy live assessment share `backend/app/services/exercise_factory.py`; movement logic, features, and models live under `src/` and `models/`.
- Firebase workflow sources: `haemophilia_app/firebase/`, including access rules, scheduling/notifications, and pure report/workflow decisions in `functions/workflow.py`.

## Review Follow-ups (Not Selected for Implementation)
- `backend/app/api/routes/live.py:109-116`: valid non-object JSON such as `[]` or `null` reaches `control.get(...)` and raises an exception, ending the current handler. Add input-shape coverage when backend hardening is in scope.
- `backend/app/services/exercise_factory.py:26-50`: substring matching accepts unknown identifiers containing `elbow` or `rotation`. Confirm intended aliases and add negative identifier tests before changing dispatch.
- Fresh real-device movement/performance checks and lower-body calibration remain documented work in `docs/on-device-assessment.md`.
- Lower-body RF bundles require sklearn 1.9.0 and are deliberately unavailable under the existing sklearn 1.6.1 pin; experimental rule-based assessment remains available. This is a documented compatibility limitation, not a new test failure.

## Verification — 2026-10-20
- Python: 59 tests passed (44 backend + 15 pure Firebase workflow), with one Starlette/AnyIO deprecation warning.
- The initial Python run timed out after 120 seconds. A rerun with bounded CPU threading passed in 10.30 seconds; no application change was required. From the repository root:

  ```powershell
  $env:OMP_NUM_THREADS='1'
  $env:MKL_NUM_THREADS='1'
  & .\.venv\Scripts\python.exe -c "import torch, pytest; torch.set_num_threads(1); raise SystemExit(pytest.main(['backend/tests', 'haemophilia_app/firebase/functions/test_workflow.py', '-q']))"
  ```

- Flutter: the completed rerun passed all 133 existing tests in approximately 47 seconds, replacing the earlier interrupted run. From `haemophilia_app`:

  ```powershell
  flutter test --no-pub --concurrency=1 --reporter expanded
  ```

- Firestore emulator integration tests, native device/camera checks, static analysis, and release builds were not run during this baseline pass.

## Team Coordination
- Local developer and local reviewer were invoked sequentially.
- Local-agent tool attempts did not produce independent repository inspection. The developer assessed lead-supplied code excerpts; reviewer suggestions required correction and were not accepted as a verified review.
- Codex performed direct source inspection, checked the review follow-ups against the code, and ran the baseline suites.

## Current Agent
- Claude Code — implementing on-device angle thresholds per exercise.

## Handoff Notes
- Read AGENTS.md and inspect the project.
- Continue from the latest completed task.
- Do not overwrite existing changes.
- Branch: `codex/upper-body-angle-thresholds` (created 2026-10-21), based on `codex/lower-body-source-integration`.
- Next exercise to convert: whichever threshold file arrives next. Follow the established pattern — bundle the supplied constants verbatim in a `docs/calibration/*.json` with a test asserting the engine matches it, add an engine under `lib/services/`, dispatch from `ExerciseRulesAssessment.update` only for that exercise, and select the pose backend in `LocalPoseService.initialize`.
- The remaining upper-body conversions will need the same native decision as the elbow: ML Kit image landmarks are not interchangeable with MediaPipe world landmarks, so an exercise measured in world coordinates must request `worldPose` and must not silently fall back.
- Two traps already cost time and will recur: a per-arm threshold with a same-frame bilateral `&&` gate never latches when the arms converge asymptotically, and a causal low-pass filter never quite reaches its input, so threshold comparisons need a small convergence tolerance (documented as numerical, never as a clinical margin).
- Shoulder rotation is the first conversion whose source was a *specification* rather than measurements. Keep that distinction visible in code and UI copy; do not let a proposed setting read as a measured or validated one.
- Preserve the existing untracked agent/configuration files identified at the start of this session.

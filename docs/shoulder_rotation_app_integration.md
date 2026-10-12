# Shoulder rotation integration handover

The current contract is **centre -> one extreme -> centre -> opposite extreme**,
followed by a centre reset. Either side can come first. See
[the current runbook](shoulder_rotation_runbook.md) for PowerShell commands,
baseline metrics, dataset review, deployment and physical phone checks.

## Root causes and fixes

* Old live/training detector counted each half-cycle; a second CSV detector
  used three extrema. Both now use the shared bilateral state machine.
* Arbitrary starting-position calibration accepted an initial extreme.
  Calibration now requires geometric neutral, then retains individual grip
  offsets. Tracking loss discards partial movement and requires centre again.
* Signed averaging of depth-derived azimuth could cancel movement and wrapping
  could produce velocity spikes. Counting now uses both observed horizontal hand
  displacements; LSTM azimuth features are unwrapped across valid observations.
* Normal arm length was called elbow drift. New upper-arm form assessment uses
  perpendicular distance from the torso axis. Sustained elbow-angle, arm-position,
  hand-coordination, tilt and twist errors give specific feedback. Bad form does
  not prevent counting a completed repetition.
* Backend defaulted to a tabular adapter despite the required LSTM pipeline.
  It now defaults to the original LSTM, validates checkpoint feature metadata,
  and reports its need for retraining under the new segmentation contract.
* Flutter mapped normalized coordinates to the full screen although preview
  retained camera aspect ratio. Preview and painter now share one aspect-ratio
  rectangle. Portrait capture is locked, mirroring is applied once, rotation and
  crop transforms are tested, and points are no longer clamped to invented edges.
* Empty results retained stale landmarks and smoothed visibility hid occlusion.
  Empty/low-visibility results clear tracking; landmarks expire after 500 ms.
  Current visibility is used immediately. Camera plane bytes are copied before
  asynchronous conversion. One request is in flight; echoed frame IDs reject
  obsolete responses. A current preview still has network latency; it cannot
  perfectly synchronize an older processed pose to a moving person.
* Correct-class probability was presented as a score and live smoothness was
  always zero. Score, model output and measured ROM/speed/smoothness are now
  separate fields. No evaluated accuracy is inferred from live probabilities.
  Patient history now calls correct-repetition percentage "Correct Rep Rate"
  instead of "Accuracy".
* Training now rejects old extraction contracts, duplicate sequences and
  cross-subject video aliases. It keeps the two-layer LSTM and subject splits,
  training-only weights and validation-only model selection. Evaluation includes
  per-class precision/recall/F1 as well as Incorrect recall and macro F1.

## Changed source files

Backend: `backend/app/api/routes/live.py`, `exercises.py`,
`backend/app/services/model_registry.py`.

Shared pipeline: `src/exercises/shoulder_rotation.py`,
`shoulder_rotation_assessment.py`, `src/features/shoulder_rotation_features.py`,
`src/feedback/rotation_cycle_detector.py`, `shoulder_rotation_rep_counter.py`,
`src/models/shoulder_rotation_loader.py`, `scripts/shoulder_rotation_pipeline.py`.

Flutter: `haemophilia_app/lib/screens/assessment/live_assessment_screen.dart`,
`lib/utils/pose_coordinates.dart`,
`lib/widgets/exercise_demo/shoulder_rotation_painter.dart`,
`exercise_demo_model.dart`.
Also `lib/screens/patient/patient_history.dart` for the metric label.

Tests: `tests/test_rotation_cycle_detector.py`,
`test_shoulder_rotation_timing.py`, `test_shoulder_rotation_backend.py`,
`test_shoulder_rotation_features.py`, `test_shoulder_rotation_pipeline.py`,
`haemophilia_app/test/pose_coordinates_test.dart`.

Docs: this handover, `shoulder_rotation_runbook.md`, `shoulder_rotation_accuracy.md`.

The IDE's `Haemophilia/src/inference/live_camera.py`, root `live_camera.py` and
`src/inference/live_camera.py` are older **assisted shoulder flexion** scripts,
not the rotation engine used by the FastAPI/Flutter flow. They remain separate.

## Actual verification results

* Python regression suite: **34 tests passed** (including synthetic training,
  frozen inputs, subject splits, tracking, counting and API checks).
* Flutter focused regression suite: **5 tests passed**; coordinate rotations,
  mirroring, crop, tutorial rendering and backend configuration.
* Flutter analysis of changed camera/geometry/tutorial files: no issues.
* Corrected recorded extraction: **8 candidates** in A_correct_01 and **9** in
  A_incorrect_01; all 17 boundaries and labels remain pending human review.
  No independent detector precision/recall has been measured.
* Assisted elbow model loads. Other two exercise smoke checks are blocked by
  the pre-existing missing checkpoints listed below.

## Remaining requirements

Review regenerated boundaries and labels, verify manifest IDs correspond to
actual people, supply independent human counts, and reserve unseen subjects for
final evaluation. Existing old-format accuracy does not establish new-format
accuracy. Do not blanket-accept candidates to train a replacement.

Physical phone front/back-camera alignment, real camera rates, network latency
and live exercise testing remain unverified. Current conversion requires YUV420;
BGRA-only camera streams need a separate conversion path. Single-view anatomical
ROM and depth remain uncertain. Broader camera-view and reviewer-labelled
recordings are required before treating the form heuristics as validated.

Other exercise implementations were preserved. Runtime smoke checks are limited
by existing missing checkpoints: `models/assisted_shoulder_lstm.pth` and
`models/elbow_lstm.pth`. Restore the authoritative trained files to test those
exercises; do not substitute random or differently shaped weights.

Both backend deployment/restart and app rebuild/install are required for all
fixes to appear on the phone. No merge into main or remote deployment was done.

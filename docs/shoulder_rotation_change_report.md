# Shoulder rotation change report

Date: 12 October 2026  
Branch: `feature/shoulder-rotation-model`  
Status: local source changes, uncommitted; no push, merge or deployment performed.

The implementation now follows the requested bilateral repetition definition.
The installed phone app and the backend it connects to have not been updated
by these local changes. Code verification passed, but physical phone testing
and new-format model evaluation remain outstanding.

**Implemented changes**

| Area | Cause found | Change made |
| --- | --- | --- |
| Repetition counting | Live counting treated centre -> one side -> centre as a complete repetition; separate CSV tooling used a different cycle definition. | Both paths now use the shared state machine: centre -> one extreme -> centre -> opposite extreme. Count at the opposite extreme, then require centre before starting again. Both directions are supported. |
| Starting position | Calibration could adopt an arbitrary initial position, including an extreme. | Initial calibration requires geometric neutral using the wand/elbow midpoint relationship, then stores each hand's individual grip offset. |
| Movement signal | Averaging signed forearm azimuth could cancel bilateral movement; angle wrapping could create velocity spikes. | Counting uses both hands' normalized horizontal displacement. LSTM azimuth is unwrapped over valid observations. Shoulder flexion is not used to detect rotation extremes. |
| Tracking interruptions | Partial segments could be joined after an interruption; missing poses left old skeletons visible. | Missing/low-visibility/nonfinite landmarks and long timestamp gaps discard incomplete movement. Completed counts survive. Flutter clears missing poses and expires the skeleton after 500 ms. |
| Overlay geometry | Landmark coordinates were stretched over the screen while the preview retained camera aspect ratio. | Preview and painter share one aspect-ratio rectangle; capture is locked to upright portrait. Rotation, mirroring and crop mapping have focused tests. Coordinates are no longer clamped to invented edge positions. |
| Asynchronous frames | Camera plane buffers were passed to asynchronous conversion; requests could accumulate old frames. | Plane bytes are copied before conversion. One frame request is in flight. Backend responses echo frame IDs, timestamps and image size; the client rejects obsolete response IDs. |
| Form assessment | Upper-arm length was used as an elbow-drift measure; feedback was generic. | Upper-arm offset is measured perpendicular to the torso axis. Sustained elbow-angle, arm-position, hand-coordination, torso-tilt and twist errors produce specific feedback. A completed repetition still counts when form is Incorrect. |
| Performance display | Correct-class probability doubled as a score; live smoothness was zero. | Form score is calculated separately from model probabilities. Duration uses elapsed sampled time, speed uses mean absolute angular motion, and smoothness uses measured acceleration. The app distinguishes form score, forearm ROM and model estimate. |
| History display | Correct-repetition percentage was labelled Accuracy. | The label is now Correct Rep Rate. |
| Model selection | The backend default was a tabular classifier despite the required LSTM pipeline. | Default restored to the existing LSTM. Its feature order, sequence length and normalization metadata are checked. A retraining flag identifies the old repetition contract. |
| Training/evaluation | Old segmented arrays could be reused under the new counting definition. | Training rejects old extraction contracts, duplicate sequence paths and videos assigned across subjects. Existing subject splits, training-only class weights and validation selection are retained. Reports now include both classes' precision, recall and F1. |

The MediaPipe -> biomechanical features -> PyTorch LSTM -> repetition assessment
pipeline, FastAPI routes and Flutter application are retained. The LSTM remains
10 inputs, 128 time steps, two layers, 64 hidden units and two classes:
0 = Correct, 1 = Incorrect. Four extra observed features support counting and
form rules without changing the LSTM input size. Existing API fields are retained
with additional tracking, debug and model-status fields.

**Counting behaviour**

* Centre -> left -> centre -> right counts once at right.
* Centre -> right -> centre -> left counts once at left.
* Centre -> one side -> centre remains partial.
* The post-count return to centre does not add a count.
* Starting at an extreme requires centre before a valid sequence can begin.
* Tracking loss discards the incomplete sequence rather than joining disconnected segments.
* Both hands must reach the side extreme; one arm cannot complete a repetition alone.
* Bad form can make a completed repetition Incorrect without suppressing its count.

Initial neutral calibration uses 10 samples at the 20-Hz processing rate.
Side extremes require three consecutive samples. A centre crossing requires one
observed sample, allowing continuous movement through centre. The thresholds,
coordination tolerance and 25-second timeout are engineering settings requiring
broader validation, not clinical ROM limits.

**Verification performed during implementation**

| Check | Actual result |
| --- | --- |
| Python regression suite | 34 tests passed. Includes both directions, initial extreme, partial movements, jitter, pauses, reset, repeated reps, tracking loss, bad form, features, timing, API and synthetic training checks. |
| Focused Flutter regression suite | 5 tests passed: coordinate mapping, rotation, mirroring, crop, tutorial rendering and backend configuration. |
| Flutter analysis of changed UI files | No issues in the final run. |
| Git whitespace check | Passed. |
| A_correct_01 replay | 8 candidate repetitions from 739 sampled frames. |
| A_incorrect_01 replay | 9 candidate repetitions from 728 sampled frames. |
| Candidate arrays | All 17 are finite and have shape (128, 10); all 17 remain pending review. |
| Other-exercise model loading | Assisted elbow loads. Two other exercises are blocked by existing missing checkpoints. |

Recorded candidate counts are not detector precision/recall: independent human
counts and boundary review have not been supplied. Synthetic training tests
verify the software workflow and do not establish exercise-classification accuracy.

**Model evaluation and dataset audit**

The existing LSTM baseline was rerun before changing the counting implementation
on its original frozen run04 sequences: 25 test samples from subject E.

| Metric | Existing old-format LSTM |
| --- | ---: |
| Accuracy | 84.00% |
| Balanced accuracy | 83.65% |
| Macro F1 | 83.77% |
| Correct precision / recall / F1 | 80.00% / 92.31% / 85.71% |
| Incorrect precision / recall / F1 | 90.00% / 75.00% / 81.82% |

Confusion matrix, actual rows and predicted columns:

| Actual / predicted | Correct | Incorrect |
| --- | ---: | ---: |
| Correct | 12 | 1 |
| Incorrect | 3 | 9 |

The old dataset contains 263 accepted sequences across five subject IDs:
177 Correct and 86 Incorrect. These sequences describe the former half-cycle
contract. New-format candidates need reviewed boundaries and labels before
replacement training. No production retraining or improved-accuracy claim was
made. Existing subjects have already been inspected in earlier experiments;
new subjects are needed for a genuinely untouched final test set.

Saved evidence:

* `reports/shoulder_rotation_exact/baseline/test_metrics.json`
* `reports/shoulder_rotation_exact/baseline/test_predictions.csv`
* `reports/shoulder_rotation_exact/dataset_audit.json`
* `processed_data/shoulder_rotation/exact_contract03/annotations.csv`
* `processed_data/shoulder_rotation/exact_contract03/detection_diagnostics.json`
* `processed_data/shoulder_rotation/exact_contract03/movement_traces/`

**Changed files**

| Group | Files |
| --- | --- |
| Backend | `backend/app/api/routes/live.py`; `backend/app/api/routes/exercises.py`; `backend/app/services/model_registry.py` |
| Shared counting and assessment | `src/exercises/shoulder_rotation.py`; `src/exercises/shoulder_rotation_assessment.py`; `src/feedback/rotation_cycle_detector.py`; `src/feedback/shoulder_rotation_rep_counter.py` |
| Features, checkpoint loading and training | `src/features/shoulder_rotation_features.py`; `src/models/shoulder_rotation_loader.py`; `scripts/shoulder_rotation_pipeline.py` |
| Flutter camera and display | `haemophilia_app/lib/screens/assessment/live_assessment_screen.dart`; `haemophilia_app/lib/utils/pose_coordinates.dart`; `haemophilia_app/lib/screens/patient/patient_history.dart` |
| Flutter tutorial | `haemophilia_app/lib/widgets/exercise_demo/exercise_demo_model.dart`; `haemophilia_app/lib/widgets/exercise_demo/shoulder_rotation_painter.dart` |
| Python tests | `tests/test_rotation_cycle_detector.py`; `tests/test_shoulder_rotation_timing.py`; `tests/test_shoulder_rotation_backend.py`; `tests/test_shoulder_rotation_features.py`; `tests/test_shoulder_rotation_pipeline.py` |
| Flutter tests | `haemophilia_app/test/pose_coordinates_test.dart` |
| Documentation | `docs/shoulder_rotation_runbook.md`; `docs/shoulder_rotation_app_integration.md`; `docs/shoulder_rotation_accuracy.md`; this report |

The open `Haemophilia/src/inference/live_camera.py` and the other older
`live_camera.py` copies implement assisted shoulder flexion. The shoulder
rotation changes were made in the engine used by FastAPI and Flutter.
Pre-existing untracked split and report files were preserved.

**What remains before phone use reflects all changes**

1. Deploy or restart the updated backend that the installed app connects to.
2. Rebuild and install the updated Flutter app to receive the overlay and UI fixes.
3. Test front/back-camera mirroring, physical preview alignment and network latency on the phone.
4. Review regenerated boundaries and labels, then retrain and evaluate the LSTM.

Single-camera depth and forearm angles approximate observable movement; they do
not measure true anatomical shoulder rotation reliably. The current camera
conversion requires YUV420; BGRA-only streams need another conversion path.
Form thresholds and score are engineering heuristics requiring reviewer validation.

Other exercise code was preserved, but runtime verification requires restoring
`models/assisted_shoulder_lstm.pth` and `models/elbow_lstm.pth`, which were already
missing. No APK was built or installed, and no hosted service was updated.

Exact Windows PowerShell commands for review, training, evaluation, backend
startup and phone testing are in [shoulder_rotation_runbook.md](shoulder_rotation_runbook.md).

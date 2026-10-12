# Shoulder rotation: exact bilateral repetition workflow

Run these PowerShell commands from the repository root. Remain on
`feature/shoulder-rotation-model`; no merge, commit, push or deployment was performed.

## Repetition and camera contract

One repetition is **centre -> one extreme -> centre -> opposite extreme**.
Count at the opposite extreme. Either side may come first. Return to centre
after counting to reset. Starting at an extreme never establishes neutral.
Poor visibility, invalid coordinates, missing frames, or a camera gap over
0.5 seconds discard the unfinished movement. Completed counts survive.

Use a frontal camera, upright portrait phone, and show shoulders, elbows,
wrists and hips. Keep the wand midpoint centred over the elbow midpoint for
the initial 0.5-second calibration. Individual grip offsets are then retained.
The initial neutral band is 8 engineering units, centre return band 3, side
threshold 10, and maximum hand disagreement at centre 15. Engineering units
are wrist-minus-elbow horizontal displacement / shoulder width * 90, **not
degrees of clinical shoulder rotation**. Extremes require 3 consecutive 20-Hz
samples; centre crossings need one observed sample because movement through
centre is continuous. Initial calibration needs 10 neutral samples. Incomplete
sequences time out after 25 seconds. Thresholds need broader recorded validation.

The LSTM still receives the ordered 10 biomechanical features, resampled to
128 time steps with fixed scales angle/180, velocity/360, torso tilt/90.
Both video extraction and live inference use the same assessment class.
Four extra observed features support counting and form rules; they are not
silently added to the LSTM input. Azimuth unwrapping prevents +/-180 spikes.

Single-camera depth, elbow angles, torso rotation and forearm azimuth are
approximations. They cannot establish true anatomical internal/external ROM,
pain, wand grip, clinical safety or clinical correctness. The form thresholds
and smoothness scale are engineering heuristics requiring reviewer validation.

## Model status and measured results

Default backend model: `models/shoulder_rotation_run01/shoulder_rotation_lstm.pth`.
The previous default was an Extra Trees adapter. This existing LSTM was trained
on the old half-cycle definition. `model_requires_retraining` is exposed in
health and live responses until a compatible checkpoint is selected.

Baseline was rerun on the original frozen run04 arrays, subject E, 25 samples:
accuracy **0.84**, macro F1 **0.837662**, Incorrect recall **0.75**.
Confusion matrix (actual rows / predicted columns, Correct then Incorrect):
`[[12,1],[3,9]]`. Correct precision/recall/F1: `0.8/0.923077/0.857143`;
Incorrect: `0.9/0.75/0.818182`.
Full results: `reports/shoulder_rotation_exact/baseline/test_metrics.json`.

These are old-segmentation results, not evidence of accuracy after this change.
New boundaries must be extracted and reviewed. No new accuracy claim or
production retraining is supplied using pending candidates. The existing E
partition has already been evaluated in earlier experiments; recruit new
subjects for a genuinely untouched final test. The A/D/E split below is a
legacy comparison workflow, not a new pristine test benchmark.

`confidence` and the two probabilities describe the uncalibrated model output.
`model_prediction` preserves 0=Correct / 1=Incorrect. Sustained observable form
errors can make a completed repetition Incorrect independently of that output.
`score` is a separate engineering score from measured posture deviation; it
is not model accuracy. ROM is camera-relative forearm azimuth excursion.
Speed now measures mean absolute angular motion per second, duration measures
elapsed 20-Hz sample time, and smoothness uses acceleration magnitude with a
fixed 360 scale. ROM/control/consistency metrics are descriptive, not prescribed
clinical limits.

## Environment and checks

```powershell
cd "C:\Users\burha\Desktop\HK\Hemophilia new\Haemophilia"
$srPython = (Resolve-Path .\.venv-shoulder\Scripts\python.exe).Path
& $srPython -m unittest discover -s tests -v
Set-Location haemophilia_app
flutter test --no-pub test/pose_coordinates_test.dart test/shoulder_rotation_preview_test.dart test/backend_config_test.dart
flutter analyze --no-pub lib/screens/assessment/live_assessment_screen.dart lib/utils/pose_coordinates.dart lib/widgets/exercise_demo
Set-Location ..
```

If creating a new Python environment, install `requirements-shoulder-rotation.txt`.
MediaPipe must expose `mp.solutions.pose`; the existing environment does.

## Regenerate and review training sequences

Videos and labels are in `dataset/shoulder_rotation/subjects.csv`.
Subject IDs must identify actual people across all recordings and sessions.
Keep every repetition/window from a person together. Never split frames randomly.
Use a fresh output directory; existing outputs are preserved.

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py extract --manifest dataset/shoulder_rotation/subjects.csv --dataset dataset/shoulder_rotation --output processed_data/shoulder_rotation/exact_all01
Import-Csv processed_data/shoulder_rotation/exact_all01/annotations.csv | Group-Object subject_id,label,review_status | Select-Object Name,Count
```

Review each original-video interval in `annotations.csv`. Mark reviewed boundaries
and labels `accepted`, ambiguous ones `excluded`; pending rows cannot train.
Do not blanket-accept inherited video labels. Boundaries cannot be changed without
regenerating arrays. `movement_traces/*.csv` and `detection_diagnostics.json`
support investigating missed candidates. Recorded candidates from two A videos
are in `processed_data/shoulder_rotation/exact_contract03`; they remain pending.
Independent human repetition counts are still required to measure detector recall.

## Train and evaluate the unchanged LSTM architecture

Once the annotations have been reviewed, for the legacy comparison:

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py split --annotations processed_data/shoulder_rotation/exact_all01/annotations.csv --train-subjects A,B,C --val-subjects D --test-subjects E --output models/shoulder_rotation_exact_split01.json
& $srPython scripts/shoulder_rotation_pipeline.py train --annotations processed_data/shoulder_rotation/exact_all01/annotations.csv --split models/shoulder_rotation_exact_split01.json --output models/shoulder_rotation_exact01 --epochs 50 --patience 10 --batch-size 8 --lr 0.001 --seed 42
& $srPython scripts/shoulder_rotation_pipeline.py evaluate --annotations processed_data/shoulder_rotation/exact_all01/annotations.csv --split models/shoulder_rotation_exact_split01.json --model models/shoulder_rotation_exact01/shoulder_rotation_lstm.pth --output reports/shoulder_rotation_exact01
```

For a new final test, add untouched subjects to the manifest and replace these
lists so every accepted person appears exactly once. Tune using validation only,
freeze all choices, then evaluate final test once. Fixed physical normalization
has no fitted dataset statistics. Class weights are fitted from training labels
only. Validation balanced accuracy selects the checkpoint. Reports include
confusion matrix, each class's precision/recall/F1, macro F1 and Incorrect recall.
Do not use `train-final` if the original test must remain held out: that command
explicitly trains on all subjects and invalidates its old test benchmark.

## Run backend and test on a phone

Current fallback LSTM, with retraining flag:

```powershell
$env:SHOULDER_ROTATION_MODEL = "models/shoulder_rotation_run01/shoulder_rotation_lstm.pth"
& $srPython -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000
```

After reviewed training, set the variable to
`models/shoulder_rotation_exact01/shoulder_rotation_lstm.pth` and restart the
backend. Keep its sibling `config.json` so feature order, normalization,
sequence length and repetition metadata are checked.

In another PowerShell terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/v1/exercises/shoulder_rotation/health
Set-Location haemophilia_app
flutter devices
flutter run -d YOUR_DEVICE_ID --dart-define=BACKEND_URL=http://YOUR_PC_LAN_IP:8000 --dart-define=POSE_DEBUG=true
```

Replace the device ID and PC LAN IPv4 from `ipconfig`; the phone and PC need
network connectivity to port 8000. For USB Android testing instead:

```powershell
adb reverse tcp:8000 tcp:8000
flutter run -d YOUR_DEVICE_ID --dart-define=BACKEND_URL=http://127.0.0.1:8000 --dart-define=POSE_DEBUG=true
```

Debug output shows state, calibration offsets, hand features, thresholds and model
probabilities; landmarks include visibility. Test both directions, initial extreme,
partial rep, reset, occlusion, multiple reps and bad form. Device preview alignment,
front camera mirroring and end-to-end latency still require physical phone testing.

**Hosted testing requires deploying/restarting the updated backend with the chosen
LSTM and config, and rebuilding/installing the updated Flutter app.** Local file
changes do not update a hosted service or installed app. Use your actual hosted URL
in `--dart-define=BACKEND_URL=https://YOUR_BACKEND_HOST`; the repository's old
Cloudflare URL is not a deployment guarantee. No hosted deployment was performed.

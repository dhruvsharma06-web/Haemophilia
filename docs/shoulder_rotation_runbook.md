# Shoulder rotation runbook

Run all commands in PowerShell from the repository root. The implementation is
`scripts/shoulder_rotation_pipeline.py`. Video names and subject IDs below are
examples to replace with actual labeled recordings. No real model has been trained.

## 1. Branch

These files are uncommitted; creating a branch carries them into your branch.

```powershell
cd "C:\Users\burha\Desktop\HK\Hemophilia new\Haemophilia"
git status --short
git switch -c feature/shoulder-rotation-model
git branch --show-current
```

If the branch exists, use `git switch feature/shoulder-rotation-model`.
Preserve unrelated changes. Coordinate the starting commit with your team before
merging; do not reset the working tree or pull over uncommitted work.

## 2. Environment

Python 3.12 is installed on this machine. Create a separate environment:

```powershell
python -m venv .venv-shoulder
.\.venv-shoulder\Scripts\python.exe -m pip install --upgrade pip
.\.venv-shoulder\Scripts\python.exe -m pip install -r requirements-shoulder-rotation.txt
$srPython = (Resolve-Path ".\.venv-shoulder\Scripts\python.exe").Path
& $srPython -c "import torch, mediapipe as mp, pandas, cv2; print('Torch', torch.__version__); print('CUDA', torch.cuda.is_available()); print('MediaPipe', mp.__version__); assert hasattr(mp, 'solutions'), 'Legacy Pose API missing'"
& $srPython scripts/shoulder_rotation_pipeline.py --help
```

Set `$srPython` again in every new terminal. Explicit executable paths avoid
activation-policy problems. MediaPipe 0.10.21 is used for the legacy Pose API.
OpenCV contrib supplies `cv2`; avoid installing another OpenCV distribution in
this environment. CPU training works; CUDA is optional.

## 3. Record and organize videos

```powershell
New-Item -ItemType Directory -Force dataset/shoulder_rotation/correct
New-Item -ItemType Directory -Force dataset/shoulder_rotation/incorrect
```

Copy real videos into these folders. Obtain labels from a human reviewer using
your supervisor's exercise protocol. Keep shoulders, elbows, wrists and hips
visible, use consistent camera orientation, and record at least 20 FPS.
Use both classes per subject where possible. Four subjects below demonstrate the
workflow; more subjects and sessions are needed to investigate generalization.
Never invent separate subject IDs for the same person.

Example video files:

```text
correct/S01_correct_01.mp4     incorrect/S01_incorrect_01.mp4
correct/S02_correct_01.mp4     incorrect/S02_incorrect_01.mp4
correct/S03_correct_01.mp4     incorrect/S03_incorrect_01.mp4
correct/S04_correct_01.mp4     incorrect/S04_incorrect_01.mp4
```

## 4. Manifest

```powershell
Copy-Item docs/shoulder_rotation_subjects.example.csv dataset/shoulder_rotation/subjects.csv
```

Edit the copied CSV to list your real files, subject IDs, session IDs, labels, and
error categories. Paths are relative to `dataset/shoulder_rotation`. Labels must
be `correct` or `incorrect`. Video IDs must be unique and use only letters,
digits, underscores, or hyphens.

```powershell
Import-Csv dataset/shoulder_rotation/subjects.csv | ForEach-Object {
    $srVideoPath = Join-Path "dataset/shoulder_rotation" $_.relative_path
    if (-not (Test-Path -LiteralPath $srVideoPath)) { throw "Missing video: $srVideoPath" }
}
```

## 5. Extract

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py extract --manifest dataset/shoulder_rotation/subjects.csv --dataset dataset/shoulder_rotation --output processed_data/shoulder_rotation/run01
```

This performs decoding, 20 FPS sampling, pose detection, existing live-engine
features, candidate counting, interpolation and normalization. Output includes
`annotations.csv`, `extraction_config.json`, normalized `(128,10)` arrays in
`sequences/`, and corresponding `_raw.npy` arrays. Candidate classification uses
a placeholder; it is not a learned judgment. Existing output folders are refused
to preserve reviews; use run02 for a new extraction.

One repetition is centre -> one side -> centre. Left and right excursions count
separately. The initial 0.5 seconds of valid tracked pose establish the centre
reference: the subject must start at centre. A movement must exceed the tunable
10-degree camera-relative excursion and return within a 3-degree band (or cross
centre) to complete. These are engineering thresholds, not medical cut-offs.
The detector resets on poor visibility but retains its calibrated centre.
Signed left/right averaging can cancel movement, and angle wrapping can produce
spikes. Check calibration, recordings and intervals before training.
The forearm signal is camera-relative, not a clinical shoulder-angle measurement.

### If old extraction returned zero or one repetition

The original live detector incorrectly required two same-side extrema to differ
by at least 15 degrees. Normal return cycles can fail that condition. The shared
live engine now uses `src/feedback/rotation_cycle_detector.py`, matching the user's
definition: centre -> one side -> centre. It stores the actual return endpoint
separately from the later confirmation frames. An unfinished movement that never
returns to centre is not counted. The former full back-and-forth implementation
is no longer the training repetition definition.

Keep old output and re-extract into a fresh directory:

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py extract --output processed_data/shoulder_rotation/run04
```

Use `run04/annotations.csv` for all subsequent review, split, and training commands.
Do not train on old sequences that span several cycles. Review the intervals;
the detector does not force a preset number of repetitions per video. The output
also contains `detection_diagnostics.json`, with quality rejections per video.

To check a single video first:

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py extract --videos B_correct_01 --output processed_data/shoulder_rotation/check_B
```

To inspect the original pose signal without rejecting low-visibility frames:

```powershell
& $srPython scripts/diagnose_shoulder_rotation.py --videos A_correct_02 B_correct_01 D_correct_01
```

Diagnostics default to 5 FPS for investigation; they are not training sequences.

## 6. Review labels and boundaries

Open `processed_data/shoulder_rotation/run01/annotations.csv`. Review each original
video interval using `start_sec` and `end_sec`. Correct `label` and `error_type`,
then set `review_status` to `accepted` or `excluded`. Pending rows are not trained.
Do not blanket-accept candidates. Exclude ambiguous movements and tracking errors.
Do not edit sequence paths or boundaries: changing a boundary requires regenerating
the array. Separately record human counts and detector misses.

```powershell
Import-Csv processed_data/shoulder_rotation/run01/annotations.csv | Group-Object review_status | Select-Object Name,Count
Import-Csv processed_data/shoulder_rotation/run01/annotations.csv | Where-Object review_status -eq accepted | Group-Object subject_id,label | Select-Object Name,Count
```

Optional plot for an actual candidate (replace the file name):

```powershell
& $srPython -c "import numpy as np; import matplotlib.pyplot as plt; x=np.load('processed_data/shoulder_rotation/run01/sequences/S01_correct_01_rep_001_raw.npy'); plt.plot(x[:,0],label='right'); plt.plot(x[:,1],label='left'); plt.xlabel('Valid frame'); plt.ylabel('Camera-relative angle'); plt.legend(); plt.show()"
```

## 7. Subject split

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py split --annotations processed_data/shoulder_rotation/run01/annotations.csv --train-subjects S01,S02 --val-subjects S03 --test-subjects S04 --output models/shoulder_rotation_split.json
```

Replace subject lists. All accepted subjects must appear exactly once; each
partition needs both classes. The script rejects overlap and missing subjects.
Freeze the split before model selection.

## 8. Training

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py train --annotations processed_data/shoulder_rotation/run01/annotations.csv --split models/shoulder_rotation_split.json --output models/shoulder_rotation_run01 --epochs 50 --patience 10 --batch-size 8 --lr 0.001 --seed 42
```

Architecture: 10 inputs, 2 LSTM layers, 64 hidden units, 2 classes, dropout 0.3.
Label 0 means correct; label 1 means incorrect. Training-only counts determine
class weights. Best validation balanced accuracy selects the checkpoint; test
sequences are not loaded. Existing experiment folders are refused.

Outputs in `models/shoulder_rotation_run01/`: `shoulder_rotation_lstm.pth`,
`best_validation.json`, `history.json`, `config.json`. Choose hyperparameters using
validation results, then fix the final experiment before test evaluation.

## 9. Evaluation

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py evaluate --annotations processed_data/shoulder_rotation/run01/annotations.csv --split models/shoulder_rotation_split.json --model models/shoulder_rotation_run01/shoulder_rotation_lstm.pth --output reports/shoulder_rotation_run01
Get-Content reports/shoulder_rotation_run01/test_metrics.json
```

Reports include accuracy, balanced accuracy, macro F1, incorrect precision/recall,
confusion matrix, subject results and individual predictions. Metrics are fractions
(0.75 = 75%). The annotations and split must match the training fingerprints.
Do not adjust the model based on test results while calling this test set untouched.
Classification metrics cover accepted detected repetitions, not detector misses.

## Test all subjects and train a final model on everyone

For the newer subject-balanced comparison and completed compact classifier, see
[shoulder_rotation_accuracy.md](shoulder_rotation_accuracy.md). It supports the
same video pipeline and an optional backend model path without overwriting the
existing LSTM checkpoint.

Use the LOSO workflow to test A, B, C, D and E each with a model trained on the
other four people. Within each fold, one of those four is reserved for selecting
the training epoch, then the fold model is refit from scratch on all four. The
outer test person's data never selects its epoch. Every accepted repetition gets
one held-out prediction. Finally, train on all subjects for the median of the
inner-validation-selected epochs.

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py loso --annotations processed_data/shoulder_rotation/run04/annotations.csv --output models/shoulder_rotation_loso01 --epochs 50 --patience 10 --batch-size 8 --lr 0.001 --seed 42 --threads 2 --fit-final
```

Outputs:

```text
models/shoulder_rotation_loso01/
  summary.json
  predictions.csv
  fold_A/... through fold_E/...
  final/shoulder_rotation_lstm.pth
  final/config.json
  final/history.json
```

Read all-subject benchmark results and individual errors:

```powershell
Get-Content models/shoulder_rotation_loso01/summary.json
Import-Csv models/shoulder_rotation_loso01/predictions.csv | Where-Object { $_.actual -ne $_.predicted } | Format-Table -AutoSize
```

The final checkpoint is `models/shoulder_rotation_loso01/final/shoulder_rotation_lstm.pth`.
LOSO metrics belong to the five held-out fold models, not the final all-subject
checkpoint. The pose pipeline/settings were already developed using this dataset,
so these are exploratory estimates; genuinely new subjects are needed for an
independent confirmation. Do not rerun to choose settings based on the outer test
results while presenting those outer results as untouched. Preserve the report.

The command refuses an existing output directory. If rerunning deliberately, use
`shoulder_rotation_loso02` to preserve the first experiment.

## Optional: final model using every subject

After the evaluation experiment and settings are fixed, refit on all accepted
repetitions. This starts fresh using the validation-selected number of epochs and
the source experiment's batch size, learning rate and seed. It preserves the
evaluated checkpoint and refuses changed annotation files. For the actual reviewed
dataset, use run04:

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py train-final --annotations processed_data/shoulder_rotation/run04/annotations.csv --experiment models/shoulder_rotation_run01 --evaluation-report reports/shoulder_rotation_run01/test_metrics.json --output models/shoulder_rotation_final01
```

Outputs are `shoulder_rotation_lstm.pth`, `config.json`, and `history.json` inside
`models/shoulder_rotation_final01/`. Every original subject is now training data.
The earlier held-out accuracy belongs to the original experiment, not this refit;
evaluate the refit on genuinely new subjects. The original `evaluate` command
rejects attempts to reuse its E partition for the final checkpoint.

For new-video replay, pass
`--model models/shoulder_rotation_final01/shoulder_rotation_lstm.pth`. If installing
this version in the backend, copy that checkpoint instead of the run01 checkpoint
and preserve any previous backend checkpoint first.

## 10. Fresh video replay

Place a new recording in `demo_videos/shoulder_rotation_new.mp4`:

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py video --video demo_videos/shoulder_rotation_new.mp4 --model models/shoulder_rotation_run01/shoulder_rotation_lstm.pth --output reports/shoulder_rotation_run01/new_video_result.json
```

Compare the JSON count and classifications with human review. Extraction and the
integrated backend share the visibility-reset policy. The backend also resamples
timestamped camera observations to the training rate; camera/network timing
still needs checking on the actual phone and hosted server.

## 11. Backend checkpoint installation

The completed app integration uses the compact classifier in
`models/shoulder_rotation/` by default. Follow
[shoulder_rotation_app_integration.md](shoulder_rotation_app_integration.md).
The following checkpoint-copy commands describe optional legacy LSTM use; select
that checkpoint explicitly with `SHOULDER_ROTATION_MODEL` if needed.

```powershell
Test-Path models/shoulder_rotation_lstm.pth
```

If False:

```powershell
Copy-Item models/shoulder_rotation_run01/shoulder_rotation_lstm.pth models/shoulder_rotation_lstm.pth
```

If True, preserve the existing checkpoint with a unique backup name first.

```powershell
& $srPython -c "from backend.app.services.model_registry import model_registry; m,d=model_registry.get_shoulder_rotation(); print(type(m).__name__, d)"
& $srPython -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

Local endpoint:
`ws://127.0.0.1:8000/v1/assessments/live?exercise=shoulder_rotation`.
Configure the Flutter app with `--dart-define=BACKEND_URL=https://YOUR-BACKEND-HOST`.
A physical phone needs a reachable backend address. The app integration guide
includes deployment, health checks and app-building commands.

## 12. Verify and record versions

```powershell
& $srPython -m pip freeze | Set-Content -Encoding utf8 models/shoulder_rotation_run01/environment.txt
& $srPython -m unittest discover -s tests -p test_shoulder_rotation_pipeline.py
Get-FileHash models/shoulder_rotation_run01/shoulder_rotation_lstm.pth -Algorithm SHA256
```

Tests cover synthetic training/evaluation plumbing, metrics, overlap rejection,
and frozen annotation checks. Synthetic tests do not establish exercise accuracy.

## 13. Commit and push

```powershell
git add scripts/shoulder_rotation_pipeline.py requirements-shoulder-rotation.txt docs/shoulder_rotation_runbook.md docs/shoulder_rotation_subjects.example.csv tests/test_shoulder_rotation_pipeline.py .gitignore
git add src/exercises/shoulder_rotation_assessment.py src/feedback/rotation_cycle_detector.py tests/test_rotation_cycle_detector.py scripts/diagnose_shoulder_rotation.py
git diff --cached --stat
git commit -m "Add shoulder rotation training and evaluation pipeline"
git push -u origin feature/shoulder-rotation-model
```

These commands stage the training pipeline only. To publish the complete backend
and app integration, use the full staging list in
[shoulder_rotation_app_integration.md](shoulder_rotation_app_integration.md).
Raw/processed data and model experiment directories are ignored; the small
production bundle at `models/shoulder_rotation/` is included in that staging list.
The pull request should include dataset sizes, evaluation results, reproduction
commands and remaining model limitations.

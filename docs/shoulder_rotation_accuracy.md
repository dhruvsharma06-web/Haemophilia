# Shoulder rotation accuracy experiment

The new nested subject-wise comparison raised pooled accuracy from 46.0% to
70.0% on the 263 accepted run04 repetitions. Balanced accuracy rose from 45.8%
to 69.3%, and macro F1 from 44.5% to 67.8%. This compares complete workflows,
including their validation strategies; it does not isolate the effect of each
change. All five people were already inspected during development. These are
development estimates, not an independent assessment of the final model.

| Held-out person | Previous LSTM accuracy | New workflow accuracy |
| --- | ---: | ---: |
| A (124 reps) | 25.8% | 75.0% |
| B (66 reps) | 78.8% | 63.6% |
| C (26 reps) | 53.8% | 57.7% |
| D (22 reps) | 45.5% | 81.8% |
| E (25 reps) | 52.0% | 64.0% |

Incorrect-form recall is 67.4% and precision is 53.2%. For C, the held-out
classifier detected only 1 of 12 incorrect repetitions. These errors remain a
priority for reviewing the videos and collecting new people and recording
sessions. A supplies 47% of the repetitions; equal-person mean balanced accuracy
is 67.2%, so pooled accuracy should not be the only result reported.

## Changes

- Summarize each normalized 128-by-10 repetition into 33 movement features:
  robust angular ranges, elbow angles, velocities, bilateral differences,
  torso compensation and smoothness. Visibility is excluded as a predictor.
- Compare absolute features and features relative to the initial position.
- Give every person/class combination equal total training weight.
- Compare regularized logistic regression, RBF SVM and Extra Trees. For each
  outer test person, select settings using leave-one-person-out validation
  restricted to the other four. Fit scaling only on each training partition.
- Select final settings by subject-wise validation, then train on all A-E.
  The final choice was Extra Trees, 200 trees, minimum leaf size 8, absolute
  features. Different outer folds selected different model families, so the
  reported 70.0% evaluates the selection workflow rather than one fixed model.

Repetition counting still uses centre -> one side -> centre.

## Reproduce training

The first experiment is already saved. Use a new directory for another run:

```powershell
cd "C:\Users\burha\Desktop\HK\Hemophilia new\Haemophilia"
$srPython = (Resolve-Path ".\.venv-shoulder\Scripts\python.exe").Path
& $srPython -m pip install -r requirements-shoulder-rotation.txt
& $srPython scripts/improve_shoulder_rotation.py --annotations processed_data/shoulder_rotation/run04/annotations.csv --output models/shoulder_rotation_improved02 --seed 42
```

Training refuses an existing output directory. It writes `summary.json`,
`predictions.csv`, fold selection reports, `final_selection.json`, `config.json`,
`checkpoint_sha256.json` and `shoulder_rotation_classifier.joblib`. The annotations
must remain frozen during comparison. Keep the Python package versions with the
artifact because sklearn artifacts depend on their training environment:

```powershell
& $srPython -m pip freeze | Set-Content -Encoding utf8 models/shoulder_rotation_improved02/environment.txt
```

## Use the completed model

`models/shoulder_rotation_improved01/shoulder_rotation_classifier.joblib` is the
completed model trained on all five subjects. It is not an LSTM `.pth` file.
The shared loader supports both formats and retains existing LSTM loading.
The app integration installs the selected model at
`models/shoulder_rotation/shoulder_rotation_classifier.joblib`, which is now the
backend default and is included with the repository's deployable assets. See
[shoulder_rotation_app_integration.md](shoulder_rotation_app_integration.md) for
the current app/deployment workflow.

For a new recording:

```powershell
& $srPython scripts/shoulder_rotation_pipeline.py video --video demo_videos/shoulder_rotation_new.mp4 --model models/shoulder_rotation_improved01/shoulder_rotation_classifier.joblib --output reports/shoulder_rotation_improved01/new_video_result.json
```

For the backend, set the model path in the PowerShell terminal used to start it:

```powershell
$env:SHOULDER_ROTATION_MODEL = "models/shoulder_rotation_improved01/shoulder_rotation_classifier.joblib"
& $srPython -c "from backend.app.services.model_registry import model_registry; m,d=model_registry.get_shoulder_rotation(); print(type(m).__name__, d)"
& $srPython -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

Restart an already running backend after changing this variable. The actual
registry is `backend/app/services/model_registry.py`; the root `model_registry.py`
is empty. Without the variable, the installed compact classifier is used.
Displayed confidence/probability values are uncalibrated model estimates.

Verification completed: six classifier/loader/registry tests and seven repetition
detector tests passed. Reloaded inference matched training predictions on all
263 saved sequences. Replaying C_correct_01 through MediaPipe with the new model
produced 14 repetitions, matching its accepted extraction count. This replay is
an integration check on a training video, not independent accuracy evidence.

## Next data improvements

1. Review the mistakes in `predictions.csv`, especially C. Check each repetition
   individually; a folder-level label may not describe every repetition.
2. Add people, sessions and camera conditions with both correct and incorrect
   examples. More repetitions of the same five people add less evidence about
   generalization to a new person than new people do.
3. Define incorrect-form categories with your exercise supervisor and collect
   consistent examples across people. Check whether the current features capture
   those errors; elbows drifting away from the torso are not directly represented
   in the existing ten sequence features.
4. Keep new evaluation people outside development and model selection. Report
   per-person balanced accuracy, incorrect recall and precision as well as pooled
   accuracy. Evaluate detector counts separately from classification.

Do not change the accepted labels simply to match predictions or report
training-set accuracy as new-person accuracy.

```powershell
Import-Csv models/shoulder_rotation_improved01/predictions.csv | Where-Object { $_.actual -ne $_.predicted } | Format-Table subject_id, video_id, rep_number, actual, predicted -AutoSize
& $srPython -m unittest discover -s tests -p test_shoulder_rotation_tabular.py -v
```

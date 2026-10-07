# Shoulder rotation in the app

The shoulder rotation classifier is installed at
`models/shoulder_rotation/shoulder_rotation_classifier.joblib`. The backend loads
it by default. Its bundle includes the training configuration, original package
versions, checksum and development benchmark. The small production bundle is
included in Git; the large training experiments and video datasets remain ignored.

The app's Shoulder Rotation card now shows "Live assessment available". Practice
and assigned sessions use the existing live camera screen, showing form,
repetitions, model score, range of motion, speed and feedback. Incorrect-repetition
frames and session history use the existing app services. The tutorial shows a
bar moving from centre to one side and returning, matching the repetition counter.

The final classifier was trained on five people. "Available" describes the
software integration; it does not claim clinical validation or independent
accuracy on new patients.

Local verification completed: both backend health endpoints return HTTP 200,
five API/model tests and three camera-timing tests pass, the two Flutter checks
pass, and `flutter analyze --no-pub lib` reports no issues. Replaying the actual
`C_correct_01` video through the backend reports all 14 reviewed repetitions.
That replay verifies integration on an existing training video, not accuracy on
a new person.

The updated Android debug APK also builds successfully and is available at
`haemophilia_app/build/app/outputs/flutter-apk/app-debug.apk`. This local build
uses the existing tunnel address; its backend still needs the new code/model
deployment. Rebuild with the permanent server URL for distribution.

## What a Git push does

Pushing uploads a branch to GitHub. Merging incorporates it into main. A running
Python server updates only when its deployment process installs and restarts the
new version. An installed mobile app updates only when a new build is installed
or distributed. A hosting provider may automate deployment after a push/merge,
but no such deployment workflow was found in this checkout.

The currently configured `trycloudflare.com` address is a temporary tunnel. It
requires its origin server and tunnel process to keep running. For access from
different Wi-Fi networks while the laptop is closed, deploy the backend onto an
always-on server and configure the app with that server's HTTPS address. See
[Cloudflare's Quick Tunnel documentation](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

## 1. Verify the local integration

From the repository root:

```powershell
cd "C:\Users\burha\Desktop\HK\Hemophilia new\Haemophilia"
$srPython = (Resolve-Path ".\.venv-shoulder\Scripts\python.exe").Path
& $srPython -m pip install -r backend/requirements.txt
& $srPython -m unittest discover -s tests -p test_shoulder_rotation_backend.py -v
& $srPython -m unittest discover -s tests -p test_shoulder_rotation_timing.py -v
& $srPython -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

In another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
Invoke-RestMethod http://127.0.0.1:8000/v1/exercises/shoulder_rotation/health
```

The shoulder endpoint must return `status: ready`,
`model_type: ShoulderRotationTabular`, and checkpoint SHA256
`60be9a89bc4d480370ea79f016905ee312206a629e2385b1b7e8d231050f136a`.
`SHOULDER_ROTATION_MODEL` can explicitly select another checkpoint. Leave it
unset to use the installed model bundle.

## 2. Commit and push the feature branch

Review `git status` before staging. These commands include the integration and
training code plus the production model, excluding generated reports and videos:

```powershell
git status --short
git add .gitignore .dockerignore backend/Dockerfile backend/requirements.txt
git add backend/app/api/routes/assessments.py backend/app/api/routes/exercises.py backend/app/api/routes/live.py
git add backend/app/services/assessment_service.py backend/app/services/model_registry.py backend/app/services/exercise_factory.py
git add src/exercises/shoulder_rotation.py src/exercises/shoulder_rotation_assessment.py src/feedback/rotation_cycle_detector.py
git add src/models/shoulder_rotation_loader.py src/models/shoulder_rotation_tabular.py
git add scripts/shoulder_rotation_pipeline.py scripts/improve_shoulder_rotation.py scripts/install_shoulder_rotation_model.py scripts/diagnose_shoulder_rotation.py
git add requirements-shoulder-rotation.txt docs models/shoulder_rotation tests
git add haemophilia_app/lib/config/backend_config.dart haemophilia_app/pubspec.lock
git add haemophilia_app/lib/utils/exercise_utils.dart haemophilia_app/lib/utils/app_localizations.dart
git add haemophilia_app/lib/services/api_service.dart haemophilia_app/lib/services/notification_service.dart
git add haemophilia_app/lib/screens/assessment/assigned_assessment_screen.dart haemophilia_app/lib/screens/assessment/live_assessment_screen.dart
git add haemophilia_app/lib/screens/patient/patient_dashboard.dart
git add haemophilia_app/lib/widgets/exercise_demo/exercise_demo_model.dart haemophilia_app/lib/widgets/exercise_demo/shoulder_rotation_painter.dart
git add haemophilia_app/test/backend_config_test.dart haemophilia_app/test/shoulder_rotation_preview_test.dart
git diff --cached --stat
git commit -m "Integrate trained shoulder rotation model with backend and app"
git push -u origin feature/shoulder-rotation-model
```

Create a pull request into `main` and merge it using the team's normal workflow.

## 3. Redeploy the hosted backend

Have the existing backend deployment pull the merged code, install
`backend/requirements.txt`, include `models/shoulder_rotation/`, and restart its
FastAPI process. Preserve the other exercises' model files when updating the
deployment. The entry point remains `backend.app.main:app`.

The existing screening pickle files emit scikit-learn version warnings at
startup: they were saved with 1.6.1, while the installed shoulder classifier uses
1.7.2. Backend startup and the shoulder endpoint succeed. The screening models
need their own compatibility check or a matching-version export before assuming
that their predictions are unchanged.

For a Python deployment on a Linux server, run inside its existing environment:

```bash
python -m pip install -r backend/requirements.txt
python -m uvicorn backend.app.main:app --host 0.0.0.0 --port 8000
```

The hosting platform or server service manager must keep that process running
and provide an HTTPS endpoint that supports WebSockets. Exact redeployment
commands depend on the existing host and cannot be inferred from GitHub alone.

A container template is provided at `backend/Dockerfile`. Build from the repository
root so `src`, `backend` and the production models are included:

```bash
docker build -f backend/Dockerfile -t haemophilia-backend .
docker run -d --restart unless-stopped -p 8000:8000 -v haemophilia-data:/app/data haemophilia-backend
```

The container accepts `PORT`. The Docker daemon was not running locally, so the
container template requires validation on the deployment host. Use the team's
existing model-storage setup when replacing an existing container.

After deployment, check the public URL, replacing the example hostname:

```powershell
$srBackendUrl = "https://YOUR-BACKEND-HOST"
Invoke-RestMethod "$srBackendUrl/health"
Invoke-RestMethod "$srBackendUrl/v1/exercises/shoulder_rotation/health"
```

Confirm the expected model type and checksum before testing the app.

## 4. Build the app against the hosted backend

All HTTP requests, live WebSockets, notifications and error-frame images now use
one `BACKEND_URL` setting. Set it to the root HTTPS URL without `/v1`:

```powershell
cd haemophilia_app
flutter pub get
flutter analyze --no-pub lib
flutter test --no-pub test/backend_config_test.dart test/shoulder_rotation_preview_test.dart
flutter build apk --release --no-pub --dart-define=BACKEND_URL=https://YOUR-BACKEND-HOST
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`. Use the team's
existing app-signing/distribution process for the actual published build. The
current project release configuration uses its debug signing configuration.
The build still uses the previous tunnel address if `BACKEND_URL` is omitted;
set the public server address when deploying.

If `flutter pub get` reports a Windows desktop symlink requirement, its Dart
packages may already be installed. Android build/test commands with `--no-pub`
were used for local verification; Windows desktop builds require Windows symlink
support separately.

## 5. Test in the app

Open **Patient dashboard -> Exercise library -> Shoulder Rotation -> Practice**.
Allow camera access. Keep both arms and the torso visible and hold the bar at
centre briefly for calibration. Perform **centre -> one side -> centre**. Check
the counter, predicted form, feedback, ROM and speed. Repeat from another Wi-Fi
network after confirming the hosted backend remains online independently of the
laptop. Doctor-assigned sessions use the same backend and model.

The local camera script under `src/inference/live_camera.py` is not the app's
server entry point. The app sends frames to
`wss://YOUR-BACKEND-HOST/v1/assessments/live?exercise=shoulder_rotation`.

# Local setup — 22 November 2026

Current branch: `codex/app-verification-2026-11-22`. Remote branches were fetched
before verification. This branch includes the preceding pose fixes and app
alignment checks. See [the verification report](docs/app-verification-2026-11-22.md)
for scope, results and remaining live/manual checks.

The earlier local setup is preserved in the stash named
`Preserve original local setup before latest branch setup 2026-11-10`.
Do not apply it blindly over the newer app.

## Environments

- Flutter 3.47.9 / Dart 3.13.7; Flutter Doctor reports no issues.
- CI pins Flutter 3.47.9; Android Gradle Plugin is 9.1.1 with Gradle 9.3.1.
- Backend: Python 3.11 environment at `.venv`, requirements installed.
- Firebase Functions: Python 3.12.15 environment at `.venv-functions`, pinned requirements installed.
- Firebase rules tests: npm dependencies installed under `haemophilia_app/firebase/tests`.
- Android SDK uses `C:/src/android-sdk`, a junction to the installed SDK.

Run backend from the repository root:

```powershell
.\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --reload
```

The current app performs exercise tracking on-device. Backend screening uses
`BACKEND_URL` (default is the repository's remote server). To use a USB-connected
Android phone with the local backend:

```powershell
adb reverse tcp:8000 tcp:8000
cd haemophilia_app
flutter --no-version-check run --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

Enable USB debugging and authorize the phone first. The Samsung SM-S938B is connected and authorized for USB debugging. The admin portal uses `lib/main_admin.dart`.

## Checks and builds

```powershell
cd haemophilia_app
flutter --no-version-check test --no-pub
flutter --no-version-check analyze --no-pub
flutter --no-version-check build apk --debug --no-pub
flutter --no-version-check build web --release --no-pub --target lib/main_admin.dart --output build/admin_web
```

APK: `haemophilia_app/build/app/outputs/flutter-apk/app-debug.apk`.
Admin web: `haemophilia_app/build/admin_web`.
Verification logs are ignored `latest-*.log` files in the repository root.

For Functions unit tests, from the root:

```powershell
.\.venv-functions\Scripts\python.exe -m unittest discover -s haemophilia_app/firebase/functions -p test_workflow.py
```

Firestore tests use the local `demo-hemo-workflow` emulator on port 8089, never
production records. See `haemophilia_app/firebase/README.md` for emulator commands.

Windows desktop plugin symlinks require Developer Mode. For this Android/web
setup, Windows/Linux desktop targets were temporarily disabled during `pub get`
and then restored, allowing Android plugin registration to finish successfully.

## Verified

- 269 Flutter tests; full analysis reports no issues.
- 44 backend tests; backend dependency compatibility passed.
- 30 Firestore rules, 25 Functions unit and 9 Functions transaction tests passed.
- Functions dependencies are compatible (`uv pip check --python .venv-functions/Scripts/python.exe`).
- Android debug APK and admin web release built successfully.

Normal builds omit `POSE_DIAGNOSTICS`. Enable numeric pose traces deliberately
with `--dart-define=POSE_DIAGNOSTICS=true` only for troubleshooting. Local logs,
scratch recordings, environments and build outputs are excluded from Git.
No website or Firebase deployment was performed during this verification.

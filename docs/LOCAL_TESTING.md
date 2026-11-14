# Local phone testing

This setup uses a fictional Firebase project (`demo-hemo-local`), local Auth/Firestore/Storage emulators, and the backend on this laptop. It does not deploy rules, change the cloud VM, or use real patient accounts. Local mode is rejected in release builds. Firebase access uses a named test app; the normal app still uses its configured default Firebase project.

## Test accounts

All accounts use the local-only password `LocalTest123!`.

| Portal | Email | Purpose |
| --- | --- | --- |
| Admin | admin@hemo.test | Assign patients, approve/reject accounts, review complaints |
| Doctor | doctor@hemo.test | Assign sessions and review patients |
| Patient | patient@hemo.test | Has the prescription created by the local workflow smoke test |
| Patient | newpatient@hemo.test | Awaiting admin assignment |
| Patient | assigned@hemo.test | Assigned to the doctor, initially without a prescription |
| Doctor | pending@hemo.test | Pending administrator approval |

Local fixtures disappear when the emulators are stopped unless explicitly exported. Re-running the seed resets fixture profiles. Google sign-in, FCM delivery, scheduled Cloud Functions, report aggregation triggers, and the admin server-side account-creation function are not running here. Use doctor self-registration and admin approval to test that workflow. Due schedules can activate through the patient app while it is open.

## Start again

From the repository root, start the backend:

```powershell
$env:HEMO_LOCAL_BROWSER='1'
& .\.venv\Scripts\python.exe -m uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

In a second terminal, from `haemophilia_app`:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
firebase emulators:start --config firebase.local.json --only auth,firestore,storage --project demo-hemo-local
```

In a third terminal, from `haemophilia_app`:

```powershell
node firebase/tests/seed_local.mjs
node firebase/tests/smoke_local.mjs
adb devices
adb reverse tcp:8000 tcp:8000
adb reverse tcp:8089 tcp:8089
adb reverse tcp:9099 tcp:9099
adb reverse tcp:9199 tcp:9199
flutter run -d 625624b1 --dart-define=LOCAL_TEST=true --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

Use the actual device ID reported by `adb devices` if the phone changes. If multiple phones are connected, pass `adb -s DEVICE_ID` for each forwarding command. Keep the laptop, backend, Firebase emulators, and USB connection running. No public tunnel is needed.

## Checks performed

- Backend `/health`, exercise catalogue, and screening service health respond successfully.
- A blank test frame through the practice WebSocket returns assessment data. This checks transport, not clinical movement accuracy.
- Authenticated local workflow checks passed for admin assignment with audit, doctor patient query, immediate prescription creation and patient reading, notification record access, two-way messaging, and patient/doctor support tickets with admin replies.
- Flutter regression suite: 43 tests passed after routing Firebase through the named local app.
- Flutter source/test analysis: no issues after the final cleanup.
- Updated debug app installed and launched on the connected CPH2691 phone. Physical exercise, notification delivery, and visual workflow checks still require using the phone.

## Suggested phone checks

1. Log in as admin and assign `newpatient@hemo.test` to the local doctor. Approve `pending@hemo.test` if testing approval.
2. Log in through the doctor portal and assign an immediate session to the new patient. Also try two different future session times.
3. Log in as that patient; confirm the prescribed session appears and future sessions are listed separately.
4. Use `patient@hemo.test` to inspect the smoke-test prescription, notification card, messages, and complaint response.
5. Start practice, stop it, and confirm that it adds no session/history record. Confirm pause/resume in a prescribed session retains repetition totals.
6. Check Hindi, reports, smaller-screen layouts, and doctor/patient Contact Admin views.

No production deployment, commit, push, or distributable release APK is part of this local run. `flutter run` necessarily creates and installs a debug build.

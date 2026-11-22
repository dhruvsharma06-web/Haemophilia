# App verification — 22 November 2026

Branch: `codex/app-verification-2026-11-22`.

The user confirmed that Shoulder Rotation and Assisted Elbow Flexion now work
well on the Samsung SM-S938B. This review preserved their movement algorithms
and checked the surrounding app workflows. The branch also includes the preceding
pose fixes and their regression tests.

## Executed checks

| Check | Result |
| --- | --- |
| Flutter unit/widget/regression suite | 269 passed |
| Full Flutter analysis | No issues |
| Backend pytest suite | 44 passed |
| Functions decision/report unit tests | 25 passed |
| Firestore authorization tests | 30 passed in `demo-hemo-workflow` |
| Functions transaction integration tests | 9 passed in the same emulator |
| Backend and Functions dependency compatibility | Passed |
| Android debug APK | Built successfully |
| Admin web release from `lib/main_admin.dart` | Built successfully |

The final APK's Full model matches the recorded SHA-256; Lite/Full models and
arm64 Flutter/MediaPipe libraries are present. The APK was installed over the
existing phone app without clearing data and launched successfully. No matching
fatal, unhandled Flutter or pose-format error appeared in that process's startup
log. This startup check does not replace the live/manual scenarios below.

All 377 automated tests passed. Firestore rules and transactions use the local
emulator; Auth account creation and FCM transport are mocked in server tests.
No production records were created for verification. Passing these tests does
not establish exhaustive coverage of every input or deployment configuration.

## Exercise alignment and corrections

All ten catalog entries have matching rule IDs, demonstrations, instructions and
threshold panels: Assisted Shoulder Flexion with Bar, Shoulder Rotation, Assisted
Elbow Flexion, Elbow Flexion & Extension, Heel Slide, Mini Squat, Seated Knee
Extension, Straight Leg Raise, Terminal Knee Extension and Squat.

Exercise-specific targets and counting requirements remain distinct. The original
independent elbow engine matches `origin/main` exactly. The bar exercise retains
its detector and rules. The two repaired exercises retain the user-confirmed full
MediaPipe VIDEO pipeline. Model provenance is recorded in
[`calibration/pose-landmarker-full.json`](calibration/pose-landmarker-full.json).

- The live threshold panel and tutorial now receive the active patient-specific
  rule, fixing a display that could show the standard target during calibration.
  Tests also prevent a rule for another exercise overriding the displayed target.
- Shoulder catalog metadata uses the active engine's onset/return constants.
  Counting behavior is unchanged by this metadata alignment.
- Assisted-elbow instructions describe its comfortable steady starting position
  instead of prescribing a fixed 150-degree camera estimate.
- Movement stages and admin role labels use readable words. Missing Hindi strings
  and numeric form-feedback translations were added. Translation tests preserve
  every measured value and audit over 500 direct static UI keys plus catalog,
  demonstration phase and tip text. Arbitrary server/user text is excluded.
- All ten compact/expanded threshold panels fit 320, 390 and 1024 pixels in
  English and Hindi with 1.4× text scaling.
- Profile validation tests found and fixed a narrow-screen gender dropdown
  overflow. They verify invalid input is blocked and email remains read-only.

Exercise regression coverage includes complete/incomplete cycles, holds, return,
totals/serialization, idle jitter, missing joints and invalid timing/coordinates.
Assisted-elbow cases cover both arms, supporting-arm interference, resting ROM
and unsupported movement. Shoulder cases cover outward/side-to-side movement,
projection limits and asynchronous arms. The common renderer has pixel checks
for front/back mapping, form colors and hidden invalid/low-confidence joints.
Lower-body demonstration start/target poses were rendered and visually reviewed.
Synthetic geometry and user feedback do not establish clinical accuracy.

## Feature coverage and remaining manual checks

| Area | Evidence in this run | Not established by this run |
| --- | --- | --- |
| Login, registration and approval screen | EN/HI responsive widgets, password/mobile validation, uniform wrong-portal errors, role/approval rules | Live sign-in, Google OAuth and password-reset delivery |
| Consent, onboarding and screening | Required answers, separate safety/camera confirmations, demographic prefill, backend tests | Actual account onboarding and live screening service availability |
| Admin management and approvals | Role-family restrictions, pending filters, privilege escalation denial; badge implementation reviewed | Live badge refresh, approval and doctor document downloads |
| Grievances and chat | Ticket creation/replies, owner/admin resolve/reopen including legacy tickets, assigned-pair access and spoofing denial | Live conversations and production notification transport |
| Assignments, schedules and transfers | Due windows, date validation, activation transactions, expiry, pause/resume preservation, cancellation and history routing | Deployed scheduler/indexes/functions and reconnect behavior |
| Assessments and tutorials | Ten catalog/demo contracts, movement regressions, personalized targets, tutorial URL validation and permissions | Physical trials for the other eight exercises and YouTube playback |
| History, reports and snapshots | Report transactions/totals, missing metric handling, frame selection, snapshot limits/permissions, report-card interaction | Live cross-device persistence and image upload/download |
| Profile and language | Validation, immutable email, narrow layout, switching and exercise/static text audit | Authenticated profile save and contextual human proofreading |
| Notifications and device sessions | Privacy-conscious copy, retry decisions, token permissions, single active-device rule | FCM transport, OS background handling and real multi-device sign-out |

There are no failing executed checks. The manual column is not claimed as passed.
iOS, clinical accuracy, assistive-device accessibility, production load and a full
offline/reconnect matrix were not verified. Existing Starlette/httpx, FCM token API
and Android plugin migration warnings did not prevent tests or builds.

## Reproduction

From the repository root:

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests -q
.\.venv-functions\Scripts\python.exe -m unittest discover -s haemophilia_app/firebase/functions -p test_workflow.py
```

From `haemophilia_app`:

```powershell
flutter --no-version-check test --no-pub
flutter --no-version-check analyze --no-pub
flutter --no-version-check build apk --debug --no-pub
flutter --no-version-check build web --release --no-pub --target lib/main_admin.dart --output build/admin_web
```

Emulator instructions: [`firebase/README.md`](../haemophilia_app/firebase/README.md).
Use the demo project only. Logs, recordings and joint traces remain ignored.
Normal builds omit `POSE_DIAGNOSTICS`; the opt-in device diagnostic entry point is
`haemophilia_app/tool/pose_device_check.dart`.

Outputs: `haemophilia_app/build/app/outputs/flutter-apk/app-debug.apk` and
`haemophilia_app/build/admin_web`. Builds are ignored by Git. This review does
not deploy the website or Firebase services.

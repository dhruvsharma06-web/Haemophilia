# Review feedback implementation — 30 October 2026

Branch base: `codex/upper-body-angle-thresholds`.

## What changed, by feedback point

| # | Feedback | Implementation |
|---|----------|----------------|
| 1 | One active device per account | Each sign-in records its token `auth_time` as `users/{uid}.sessionValidAfter` (`AuthService.claimDeviceSession`). Firestore and Storage rules refuse any request whose `auth_time` is older (`sessionCurrent()`), and the root gate signs older devices out with a notice. A device can only write its own, newer sign-in time. Applies to patients, doctors and admins, and to the doctor-creation Cloud Function. |
| 2 | Patient-specific calibration | `lib/services/patient_calibration.dart`. The doctor chooses **Standard**, **Adaptive** or **Manual** per patient and exercise (patient page → *Movement calibration*). Adaptive capability = p80 of recent peak angles (p20 of minima for exercises that decrease the angle) over the last 30 days, at least 6 reps across 2 sessions; target = capability + 3°, never past the standard target and at least 15° past rep onset. Covers assisted shoulder flexion, assisted elbow flexion and all six lower-body exercises. Elbow flexion/extension and shoulder rotation keep their measured thresholds. Every saved rep records the calibration used (`patientCalibration`). |
| 3 | YouTube tutorials | Admins attach one reviewed YouTube link per exercise in the web portal (*Exercise tutorials*). Patients see **Watch video tutorial** in the exercise guide. Links are parsed, canonicalised and validated in the app and in the rules. No links are pre-filled: the clinical team must choose them. |
| 4 | Push reminders | `send_session_reminders` (Cloud Functions, every 5 min; also run by the VM worker) notifies the patient 15 minutes before a scheduled session, once per occurrence, in English or Hindi. A queued reminder is dropped if the session was cancelled or has already opened. |
| 5 | Separate admin web portal | `lib/main_admin.dart` → `lib/admin_portal/`. Admin-only sign-in, session-only browser persistence, 30-minute idle sign-out, labelled actions. The mobile app no longer contains the admin dashboard; an admin account signing in on mobile is told to use the portal. Hosting target `admin` with strict security headers. |
| 6 | Store exercise images | After each exercise, the device stores clean (unannotated) images under `exercise_snapshots/{patient}/{day}/` with a record at `users/{patient}/exerciseSnapshots/{day}_{exercise}`. `trainingEligible` mirrors the patient's research consent, which the rules enforce. Doctors review them on the patient page (*Exercise snapshots*). |
| 7 | Similar / representative images | Pose-normalised keypoint vectors; the stored pair is the medoid (most representative) plus its closest match, preferring correct-form reps and merged with what is already stored for that day. At most two per day and exercise. |
| 8 | No real-time impact | One capture per rep, when the target is reached, never awaited in the frame loop. Native JPEG encoding moved to a separate low-priority thread (this also removes the existing review-photo stall from the detection thread). Candidates are capped by reservoir sampling; uploads start only after the exercise ends. |

## Tester notes

- **Password policy:** minimum 8 characters, at least one letter and one number. Runs of 3+ consecutive characters (`abc`, `123`, `cba`), 3+ repeats (`aaa`), keyboard runs (`qwer`), common words and the user's own name or email are blocked. The same rules apply in the app, the admin form and the server (`workflow.password_problem`). Every hint now reads "At least 8 characters …" (it used to say 6).
- **Age asked twice:** screening now prefills the registered age (and male/female when given), at no extra cost.
- **Unlabelled ✓ button / no way to resolve grievances:** replaced by **Mark as resolved** / **Reopen request** buttons, a status chip and Open/Resolved/All filters. The submitter is notified, and their reply reopens the request. Legacy `closed` shows as Resolved.
- **Doctor accounts revealed at login:** all sign-in failures use uniform messages. Password reset no longer reveals whether an email exists.
- **Admin login from the patient screen:** removed. Patient login accepts patients only; physiotherapist login accepts doctors only; admins use the portal.

## Security hardening

- Ticket creation: fixed key set, and the submitter role must match the profile. Users cannot change their own registration number or council.
- Android: cleartext limited to the existing screening backend IP (debug builds allow LAN emulators); app backup and device transfer disabled; release signing from `android/key.properties`.
- Removed committed installers and backups (`WhatsApp Installer.exe`, `*.winmd`, `*.zip`, `lib_current_backup/`, stray `main.dart`).

## Deploy (from `haemophilia_app/`)

```bash
flutter pub get                       # adds url_launcher
flutter analyze lib test
flutter test --concurrency=1
(cd firebase/tests && npm ci && npx firebase emulators:exec --only firestore "npm test")
python -m pytest firebase/functions/test_workflow.py -q

firebase deploy --only firestore:rules,firestore:indexes,storage
firebase deploy --only functions      # or restart the VM worker service

firebase hosting:sites:create haemophilia-physiotherapy-ai-admin
flutter build web --release -t lib/main_admin.dart --output build/admin_web
firebase deploy --only hosting:admin
```

After deploying the portal, add `haemophilia-physiotherapy-ai-admin.web.app` under Firebase Console → Authentication → Settings → Authorised domains. Also turn on *Email enumeration protection* there.

## Still requires people, not code

- Real-phone validation of every exercise (labelled reps, both sides, lighting, distance). Shoulder rotation's numbers remain proposed settings; assisted elbow flexion still awaits measured threshold files.
- Choosing the tutorial videos (clinical review).
- Moving the screening backend from `http://34.173.173.123:8000` to HTTPS, then deleting its cleartext exception in `android/app/src/main/res/xml/network_security_config.xml`.
- A release keystore and a real application ID (currently `com.example.haemophilia_app`; changing it needs a new Firebase Android app).

## Manual test checklist

1. Register with password `Rohit@1234` → refused with the sequence message; `Mango#47Rq` → accepted.
2. Register with age 24 → screening shows 24.
3. Sign in on phone A, then on phone B → phone A returns to login with "signed in on another device".
4. A doctor account on Patient Login and a patient account on Physiotherapist Login show the same neutral error; an admin account on mobile shows the portal notice.
5. Portal: add a tutorial link → the patient's exercise guide shows **Watch video tutorial** and opens YouTube.
6. Doctor: set a patient to Adaptive after 2+ sessions → the card shows a personalised target; the next session uses it.
7. Complete an exercise → the doctor's patient page shows up to two snapshots for today; the frame rate during the exercise is unchanged.
8. Schedule a session 20 minutes ahead → a reminder arrives about 15 minutes before it starts.
9. Raise a grievance → admin marks it resolved → the submitter gets a notification → their reply reopens it.

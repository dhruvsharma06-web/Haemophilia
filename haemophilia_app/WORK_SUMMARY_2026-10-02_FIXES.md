# Somaiya HemoPhysio — requested corrections

## Delivery

Changes are prepared on `codex/patient-workflow-fixes`. The original `main`
commit is `6dfc322331b5bbf4f856a78ff0cfa637c13bfe9b`. The branch includes the
previous workflow implementation and these corrections.

## Changes

- Help saves a grievance and its first message atomically, opens the conversation
  after sending, and shows readable failures. Prepared rules grant the owner and
  administrators access to support records.
- Administrator assignment validates the administrator, patient and active
  approved doctor. Prepared rules allow its immutable audit write.
- Assigned doctors can review diagnosis status, screening answers and the saved
  AI risk estimate, including for newly assigned patients without sessions.
- Routine access by the assigned doctor is disclosed in privacy information;
  there is no separate doctor-sharing consent choice. Research consent remains
  optional for patients. Recording still requires safety and camera/AI consent.
- Patient password login rejects doctor and pending-doctor profiles before
  dashboard routing. Existing administrator entry remains available.
- The interface uses deep teal and neutral surfaces. Existing logo artwork is
  retained for the separately planned red logo.
- Translated screens subscribe to locale changes; missing title, workflow and
  screening labels have Hindi entries with capitalization-tolerant lookup.
- Scheduling supports up to 12 distinct daily times and 366 days. Long plans
  are saved in chunks and published only after all occurrences are written.
- Firebase failures display readable guidance while retaining diagnostic logs.
  Unassigned patients do not query a placeholder doctor record.

## Current verification

- Dart analysis of `lib` and `test`: no issues found.
- No test suite was run for these corrections. Earlier test results in the
  initial summary predate this update.
- Android debug APK built successfully with the current backend URL:
  `build/app/outputs/flutter-apk/app-debug.apk`.
- Firebase's rules compiler returned HTTP 200 with no issues. This validates
  rule compilation, not production access behavior.
- `git diff --cached --check` passed.
- Phone installation and interaction checks are pending: ADB reports no device.

## Live activation still required

Read-only Firebase inspection confirmed the deployed rules do not contain
`supportTickets`, `adminAudit` or `exerciseSchedules` matches. Those missing
permissions explain the reported grievance and assignment failures. The local
rules and indexes are corrected; the live errors remain until deployment.
Live rules/index deployment approval was requested and has not been received.

Billing and the Cloud Functions API are disabled in the live project. Functions
must be enabled and deployed before scheduled activation, phone push, automatic
reports, transfer routing and admin-created doctor accounts work there. No
billing changes, API enablement or production deployments were performed.

An earlier automatic approval review failure was resolved. The final dashboard
polish was then applied, replacing banner gradients with a solid teal surface
and reducing heavy heading weights. Rule compiler validation completed without
changing live access controls.

The existing temporary backend tunnel was approved earlier. Its URL may change
when restarted; the Android build uses the URL from the current phone run.

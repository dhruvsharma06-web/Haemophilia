# Somaiya HemoPhysio — workflow implementation

## Status

Initial implementation summary. See `WORK_SUMMARY_2026-10-02_FIXES.md` for the
subsequent corrections and current deployment limitations. Changes are being
delivered on `codex/patient-workflow-fixes`; no production deployment, account
creation or database migration has been performed.
The existing Python movement models, trained assets, inference code and camera
frame encoding are unchanged.

## Features

1. Registration requires acceptance of versioned terms and privacy information.
   Camera and AI consent is requested before recording a session.
   Research use has a separate optional choice which can be changed in Help.
2. Patient onboarding starts after authentication. A diagnosed patient sees doctor
   guidance; other patients complete the existing 15-question screening. Symptom
   choices require an explicit answer. Answers and results are saved in the
   patient's profile for administrator review. Public screening was removed.
3. Unassigned patients see the waiting message and exercise demonstrations.
   Recording practice requires a doctor assignment and session consent.
4. Google login requires an existing active patient profile matching the Google
   account email. It no longer creates patient profiles automatically.
5. Registered doctors remain pending until an administrator approves them.
   Administrators can create doctor accounts through a protected server function,
   deactivate accounts, assign patients and transfer them with an audit record.
6. Transfers retain the patient's history. Access rules immediately revoke the
   former doctor's access; a retry-enabled server event updates history routing
   and cancels future schedules belonging to the former doctor.
7. Doctors can schedule up to 12 sessions per day, selected weekdays, one week,
   one calendar month or 1–366 custom days. Editing cancels/replaces an occurrence
   only when Save succeeds. A series' remaining occurrences can be cancelled.
8. A server clock activates due schedules and creates notifications together.
   Unstarted sessions expire at the scheduled day's end. Active/paused sessions
   are retained and block another assignment from overwriting them. A waiting
   occurrence may become available after the current session is completed.
9. Before recording or resuming, patients affirm that they are not bleeding and
   consent to camera processing. The dialog instructs patients to stop and contact
   their doctor if bleeding occurs. Backgrounding stops image capture.
10. Resumes reuse the same session ID and cumulative exercise progress. Rep IDs
    are deterministic, and pause/completion waits for outstanding writes. The
    assignment and session's final status are saved in one batch.
11. Patients and doctors can open short session reports. The server aggregates
    immutable rep evidence, cumulative counts, available movement scores and
    camera angle estimates. The report explains that these are prototype estimates.
12. Patient-doctor chat is restricted to the current assigned pair. Dates include
    day/month/year. Help provides patient/admin and doctor/admin conversations,
    complaint categories, replies, administrator closure and notifications.
13. Stable patient IDs appear on the dashboard and doctor patient cards. Doctors
    can search their assigned patients by ID.
14. Patient, doctor and administrator dashboards have separate navigation sections.
    The application is named **Somaiya HemoPhysio**, with a deep teal primary theme.
    Hindi coverage includes new workflow copy, terms, safety checks, support,
    reports, exercise guidance and material date/time controls. User-written names,
    messages, patient IDs, email addresses and technical identifiers are preserved.
15. Phone delivery uses server credentials and registered device tokens, with
    per-device retry tracking, invalid-token removal and suppression of obsolete
    assignment/message notices. Push copy omits health details and message text.

## Verification

The following results belong to the initial implementation, before the latest
corrections. They do not establish verification of the updated code. See the
fixes summary for checks performed on the current source.

- Dart static analysis of `lib` and `test`: no issues found.
- 40 Flutter tests passed, including existing responsive/localization tests and
  new scheduling, consent, safety, explicit screening-answer and report tests.
- 17 local Firestore emulator access tests passed, including safe initialization
  of missing metadata on older paused sessions and atomic pause saving.
- 22 Python tests passed: 14 workflow tests and 8 server transaction/handler tests.
- `git diff --check` passed. No production data was used for these tests.
- Push transport is mocked in server tests. No real phone delivery, camera session,
  Google provider login or cloud deployment has been verified in this run.

## Activation and remaining external work

The new source must be released with the Firebase functions, indexes and rules.
Without deployment, scheduled activation, push delivery, automatic report
aggregation, transfer synchronization and administrator-created doctor accounts
will not operate in the live project. See `firebase/README.md` for the staged
deployment procedure. The user has authorized a commit and push on the new
branch. Live Firebase deployment still requires approval.

After deployment, verify on an Android device: both Google login outcomes, doctor
approval, due-time notification, message push in both directions, two pause/resume
cycles and a doctor transfer. Review operator details in the terms before release.
Grievances use in-app messages; no email service or support address was supplied.
The existing logo artwork remains available for the separately planned red logo.

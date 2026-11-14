# Firebase clinical workflow

These are deployment sources. Editing them does not change the live project.

## Components

- `firestore.rules`: current role/approval, assigned-patient access, consent,
  restricted chat, support, schedules and immutable report/history fields.
- `storage.rules`: consented patient image uploads and assigned clinician review.
- `firestore.indexes.json`: schedule, patient ownership and transfer queries.
- `functions/main.py`: due-time activation, device-token pushes, report aggregation,
  transfer synchronization, support notifications and admin doctor creation.
- `functions/workflow.py`: pure decisions and report calculations.
- `functions/retrying_trigger.py`: tested compatibility adapter for retry-enabled
  Firestore deployment manifests in the pinned Python Firebase SDK.

## Local verification

Use Python 3.12 and a virtual environment; install `functions/requirements.txt`.
Run `python -m unittest test_workflow` from `functions`.

With Java 21 available, start a **demo** Firestore project from the Flutter root:

```powershell
firebase emulators:start --only firestore --project demo-hemo-workflow
```

In `firebase/tests`, install the package dependencies and run `npm test`.
The rules test uses `127.0.0.1:8089` and `demo-hemo-workflow` only.
For server transaction tests, in a separate terminal from `functions`:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8089'
python -m unittest test_server_emulator
```

The server suite mocks Firebase Authentication account creation and FCM transport;
all Firestore transactions use the demo emulator. Never use production credentials
or a live project for these tests.

## Deployment — only after explicit approval

1. Review the saved changes and terms. Confirm the target project is
   `haemophilia-physiotherapy-ai`, the runtime is Python 3.12 and function region is
   `us-central1`. Admin doctor creation calls this region from Flutter.
2. Confirm Cloud Functions, Cloud Scheduler, Eventarc and FCM are available in the
   target project. Review any billing requirement before enabling services.
3. Prepare a release of the updated app. Existing accounts will be prompted for
   current consent; existing patients will complete onboarding without losing
   their assignment or saved history. Existing approved doctor profiles with no
   legacy approval flag remain supported.
4. Deploy indexes and the `hemo-workflow` functions using the included Firebase
   configuration. Verify every Firestore event manifest has retry enabled. The
   scheduler runs once per minute, so sessions appear on the next due-time tick.
5. Release the updated app and deploy the matching Firestore/Storage rules in a
   coordinated release. Old app versions lack the new consent fields and must not
   be assumed compatible with the stricter rules.
6. Back up the live database and reconcile existing session `doctorId` routing
   against current patient ownership before rollout; do not run an unreviewed
   bulk migration. New transfers synchronize through the server event.
7. Complete the real-device scenarios listed in `WORK_SUMMARY_2026-10-02.md`.
   FCM delivery depends on device permission/connectivity and Android/iOS project
   configuration. This repository run does not verify production transport.

Schedules are never delivered early. An unfinished assignment is retained; later
occurrences wait and are missed if their availability window expires.
Doctors may select up to 12 distinct times per day and up to 366 days. Plans are
written in batches of 400 occurrences under an `exerciseScheduleSeries` parent.
The parent becomes `ready` only after every batch succeeds; the updated server
scheduler ignores unpublished plans. Deploy the matching rules, indexes and
functions together before using this scheduling flow in production.
Notification IDs and per-token delivery tracking reduce duplicate alerts.
A transport success followed by process failure before recording that success
can still redeliver; OS collapse IDs reduce duplicate visible alerts.

No email grievance delivery is configured. Help routes replies inside the app.

## Live project finding — 2 October 2026

Read-only inspection found that the deployed Firestore rules have no access
matches for `supportTickets`, `adminAudit` or `exerciseSchedules`. This explains
the reported grievance and patient-assignment permission failures: assignment
and audit writes are atomic. The rules in this directory include those matches
and the new schedule-series permissions, but have not been deployed.

The live project has billing disabled and the Cloud Functions API disabled.
Scheduled activation, server push delivery, report aggregation, history routing
after transfers and administrator-created doctor accounts require the functions
to be deployed. Billing and API enablement require the project owner's approval.

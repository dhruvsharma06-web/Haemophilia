# Admin feedback changes

Source: `origin/claude/review-feedback-2026-10-30` at `d3d8893`.
Working branch: `codex/admin-feedback-fixes`.

- Manage Users filters: all users, assigned patients, unassigned patients, doctors, pending doctors, admins. A patient waiting for assignment remains a patient account.
- Wrong-portal and invalid-credential errors use the same English/Hindi message. Role routing remains enforced; failed login signs out.
- Patients cannot be promoted to clinicians/admins. Clinicians can switch only between doctor and pending doctor. This is enforced in controls, transaction logic and Firestore rules. Patient assignments still allow Unassigned.
- Grievances have a live red open-ticket count. Updated rules support resolving and reopening from either the owner or admin, including legacy tickets and atomic admin notifications.
- Doctor registration uploads PDF/JPG/PNG documents under `doctor_documents/<uid>/`. Admins can open them in the review dialog. Existing filename-only submissions need re-upload through Registration documents on the pending-approval screen. Upload failure preserves registration and permits retry.

Validation: 209 Flutter tests passed; active app/test analysis has no issues. All 30 Firestore emulator tests passed, including cross-family role restrictions, legacy grievance resolution, admin notification batching, and owner reopening/resolution. Android debug and admin web release builds succeeded.

Firebase deployment requires CLI authentication with project deployment permissions. From `haemophilia_app`:

```powershell
npx firebase-tools login
npx firebase-tools deploy --project haemophilia-physiotherapy-ai --only firestore:rules,storage,hosting:admin
```

Admin hosting target: https://haemophilia-physiotherapy-ai-admin.web.app
Local web output: `haemophilia_app/build/admin_web`.
Local APK: `haemophilia_app/build/app/outputs/flutter-apk/app-debug.apk`.

Deployment update, 1 November 2026: Firebase CLI authentication succeeded. Firestore rules compiled and were released; the admin hosting deployment completed successfully. Storage rules deployment was blocked because Firebase Storage has not been set up for this project. The Storage API was enabled by the deployment CLI, but no bucket was created. Complete Storage setup in Firebase Console, then deploy `--only storage` before testing doctor document uploads.

Live Firebase login, document uploads and grievance writes need end-to-end verification after the rules are deployed. No production records were changed by the emulator tests.

The updated debug app was installed and launched on Samsung SM-S938B on 1 November 2026. The patient login screen was visually verified. Flutter replaced the previous differently signed installation; local sign-in state was reset. The phone also reports an existing native-library 16 KB page alignment compatibility warning (including MediaPipe); this was dismissed for testing and is not fixed by these admin changes.

On Windows, `pub get` initially stopped before generating Android plugin registration because desktop symlink support is unavailable. Temporarily disabling Windows/Linux desktop targets for `pub get`, then restoring those settings, generated the required plugin registration and fixed startup. For future setup, enable Windows Developer Mode or use that same temporary-target workaround; do not treat a partially failed `pub get` as a complete setup.

# Firebase rules for the clinical workflow

Deploy these two rule files in Firebase Console before testing doctor/admin access.

- `firestore.rules` → Firestore Database → Rules
- `storage.rules` → Storage → Rules

The rules implement:

- Patient: own profile, own assessments, own messages.
- Doctor: assigned patients only; assessment review; doctor feedback; assigned-patient messages.
- Admin: user/role/doctor-assignment management and full clinical-data access.
- Error images: patient upload; assigned doctor/admin read.

For the admin workflow, an existing account can be promoted from `patient` to `doctor` and a patient can then be assigned to that doctor. Creating Firebase Authentication accounts programmatically should be done server-side later; the current admin UI intentionally manages existing accounts only.

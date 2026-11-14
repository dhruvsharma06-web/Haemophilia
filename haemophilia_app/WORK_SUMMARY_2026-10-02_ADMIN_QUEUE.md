# Admin assignment and new patient queue

- Added a **New patients** dashboard section for active patients without an
  assigned doctor. It sorts recent registrations first, shows patient ID and
  screening details, and offers a direct doctor assignment action. A live badge
  shows the waiting count in the admin navigation.
- The existing **Manage Users**, **Doctor approvals** and **Grievances** sections
  remain available. The admin app bar title now fits on a phone.
- Added a server notification trigger for newly registered patients. When the
  Firebase Functions code is deployed, it creates one notification per active
  administrator and the existing push dispatcher sends it to admin devices.
  The in-app badge works from the user stream without Cloud Functions.
- Assignment rejects stale queue cards if another administrator already
  assigned the patient. Permission failures now identify Firebase access
  settings instead of telling the administrator to contact an administrator.
- The live assignment failure is caused by a missing `adminAudit` match in the
  deployed Firestore rules. A minimal additive change is documented in
  `firebase/ASSIGNMENT_HOTFIX.md`; it has not been deployed.

The live project had billing and Cloud Functions disabled at the last inspection.
Admin phone push therefore needs a separately authorized Functions deployment
and billing setup. The rule change requires specific approval to use the saved
Firebase login and update production access controls. No patient records were
changed during this work.

## Logo cutout and stopping point

The supplied red logo was processed with the built-in image generation tool as
a transparent background extraction. The selected 1254 × 1254 PNG has alpha 0
at every corner and alpha 254 in a solid red emblem area. It replaces both app
image assets. Launcher icons were regenerated for Android, iOS, web, Windows
and macOS. Android's adaptive icon and iOS's required opaque icon use the app's
`#F5F7F8` background; the in-app logo itself is transparent.

Dart static analysis reported no issues and Python function sources parsed
successfully. The user asked to leave tunneling, app launch and APK generation
for later, so the in-progress APK build was stopped. The previous temporary
tunnel and backend processes were stopped. The previously shared APK is from
the earlier build and does not include these changes.

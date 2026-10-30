# Minimal live rule change for admin patient assignment

On 2 October 2026, the deployed Firestore rules allowed administrators to update
`users/{patientId}` and `exerciseAssignments/{patientId}`, but had no match for
`adminAudit/{id}`. `AdminService.manageUser` writes the patient and an audit
record in one transaction. Firestore rejects the whole transaction when the
audit write is denied.

Add this match inside `match /databases/{database}/documents` in the **current
live rules**, then compile and deploy that edited ruleset:

```firebase
match /adminAudit/{id} {
  allow read: if isAdmin();
  allow create: if isAdmin()
    && request.resource.data.actorId == request.auth.uid
    && request.resource.data.userId is string
    && request.resource.data.action == 'manage_user';
  allow update, delete: if false;
}
```

This is an additive fix for the live rules observed on 2 October 2026. Fetch
the current release again and check its diff before deployment: the release may
have changed since that inspection. The comprehensive `firebase/firestore.rules`
source in this repository has broader changes and needs a coordinated rollout.

The desktop automatic approval review blocked access to saved Firebase CLI
credentials while preparing this fix. No live rules were read or deployed in
that attempt. Deployment needs specific authorization to use the existing
Firebase login and to change production access controls.

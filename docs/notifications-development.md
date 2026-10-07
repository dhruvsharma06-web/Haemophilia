# Development notifications — 6 October 2026

## App

The inbox and badge query unread records only. Opening an alert or choosing
**Mark all as read** marks records read and dismisses their matching Android
tray notification. The app saves doctor/patient message alerts, administrator
replies and immediate assignment alerts atomically with the triggering write.
The server uses the same deterministic record IDs, preventing duplicate alerts
and preserving read status across retries.

Android's `haemophilia_notifications` channel uses high importance, sound,
vibration and private lock-screen visibility. Server payloads use high delivery
priority and generic copy without medical details or message content. The device
must grant notification permission. A force-stopped app and operating-system
notification restrictions can prevent display.

Every unfinished session expires one hour after its original scheduled start,
including paused and in-progress sessions. The app and Firestore permissions
cap older longer windows at one hour. The patient sees a countdown; expired
assignments are archived and cannot be resumed. Session push TTL ends with that
deadline. Cancelled sessions are terminal too.

## Server

Firebase project `haemophilia-physiotherapy-ai` currently has billing disabled
and the Cloud Functions API disabled. Notification handler source is ready for
Cloud Functions if the project later moves to an appropriate plan.

For the existing development trial, `firebase/functions/vm_worker.py` can run
the same notification handlers on the existing Google Cloud VM. It uses
Firestore listeners, a persistent SQLite retry queue, deterministic alerts, and
scheduled-session activation every 30 seconds. It uses the attached VM identity;
no private key or personal OAuth credential is copied to the VM or app. The
notification service exposes no HTTP endpoint.

Installation alone does not activate the worker. Explicit access approval is
required for:

- Existing VM identity: `746404934351-compute@developer.gserviceaccount.com`.
- Firebase project grants: `roles/datastore.user` and
  `roles/firebasecloudmessaging.admin`.
- VM scopes: add `https://www.googleapis.com/auth/datastore` and
  `https://www.googleapis.com/auth/firebase.messaging`, preserving current scopes.
- A brief VM stop/start to change those scopes. Preserve/promote the existing
  external IP first, so installed APKs retain their backend address.

After approved configuration, enable/start `haemophilia-notifications.service`
and confirm its log says **Notification worker ready**. Verify phone delivery
with notification permission granted and a real session/message, including a
locked phone. Do not run a Cloud Functions dispatcher and the VM dispatcher
simultaneously; use one server runtime.

The worker shares the existing VM's 90-day trial lifecycle. This does not make
the VM permanently free or move Firebase to paid billing.

## Shoulder previews and wireframe

Confirmed assisted-shoulder errors now expose their annotated image during the
live repetition and at completion. Saved images have random unique filenames.
Practice previews travel in memory and are not written as practice records or
image files. The socket sends a new live preview once, rather than repeating a
large inline image in every frame response.

Wireframe rendering interpolates over measured response intervals and limits
camera frames in flight to two, reducing stale buffered movement. Rendering is
isolated from the widget tree. Exercise model weights, features and decision
thresholds are unchanged. Smoothness still needs a real-phone review.

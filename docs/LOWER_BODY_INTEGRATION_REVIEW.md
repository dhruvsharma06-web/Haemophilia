# Lower-body integration review — 13 October 2026

Source: `feat/hemophysio-integration-handoff` at `d90ff41d826a1967229b090791aa9dfecc89f675`.
Integrated onto current release `76e7f49`, on `codex/lower-body-integration`.

## Included

- Heel slide, mini squat, seated knee extension, straight leg raise, terminal knee extension and squat.
- Doctor assignment and patient practice catalog, demonstrations and Hindi text.
- Shared live/video backend dispatch and server-version checks before starting the new exercises.
- Preserved the latest elbow models, session expiry/cancellation, reports, messaging, approvals and existing backend configuration.

## Review fixes

- Avoided replacing the current app with the source branch's older main-based version.
- Replaced reused arm demonstrations with lower-body diagrams.
- Reject missing, low-visibility, non-finite and degenerate driver joints; discard partial repetitions after tracking loss or long camera gaps.
- Require a starting position before counting; bound active repetition buffers and use timestamps for live duration.
- Removed fabricated fallback smoothness and unsupported validation labels.
- Retained pinned dependencies. The supplied sklearn 1.9.0 RF bundles are incompatible with the current sklearn 1.6.1 environment used by the existing assisted-elbow model. They are preserved, but mismatched inference is explicitly unavailable; lower-body counting and feedback use the supplied experimental movement rules.

## Evidence and limits

- 44 backend tests passed, including six synthetic movement cycles and tracking-loss regressions.
- 56 Flutter tests passed, including new diagrams, localization and existing workflows.
- 23 Firestore permission tests and 24 Python workflow tests passed.
- Flutter analysis passed; release APK built with versionCode 202610131.
- These are engineering checks, not clinical validation or an unseen-patient accuracy study. The source model card reports a single participant, zero F1 for mini-squat and seated-extension labels, and label leakage for one straight-leg-raise label. Thresholds remain provisional. No claim of universal accuracy is made.
- New lower-body tracking follows the supplied left-leg driver. Real-camera evaluation across people, views and prescribed ranges remains necessary.
- Cloud notification worker activation remains a separate IAM/scopes dependency; this release does not grant new cloud permissions.

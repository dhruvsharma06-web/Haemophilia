# Somaiya HemoPhysio — work report

Date: 3 October 2026

## Delivery status

The changes below are implemented in the local source on `codex/patient-workflow-fixes`. No commit, push, Firebase deployment, VM update, app launch, or APK build was performed for this delivery. The installed APK and deployed services still use their previous versions.

## Changes by request

| Request | Local result |
| --- | --- |
| 1. Session timing | Doctors can assign immediately or schedule recurring sessions, including multiple times per day. Immediate assignments are available for 24 hours. Scheduled occurrences expire at the next occurrence that day or midnight. |
| 2. Admin rejection | Admin can reject patient and doctor accounts with a reason. Access is disabled and the account gate displays the stored reason. |
| 3. Password validation | Registration requires at least eight characters with a letter and a digit. Validation also runs in the registration service and doctor-account function source. |
| 4. Mobile validation | Indian mobile numbers and explicitly prefixed international numbers are validated in registration, doctor creation, and profile editing. |
| 5, 19. Admin welcome | The welcome card is displayed on the three administrative list pages: New patients, Manage users, and Doctor approvals. |
| 6. Doctor approval | Approval checks professional registration details. Only active, approved doctors can receive patients and publish sessions. |
| 7, 8. Remove patients/doctors | Admin can remove access with a reason and an audit record. Removal disables the account and retains historical records. The confirmation explains transferring a doctor's patients first. |
| 9. Messaging | Patient/doctor pairing and active-account checks are enforced. The latest 200 messages are loaded in chronological order, messages have a 2,000-character limit, and initialization failures are handled. |
| 10. Notification card | A notification inbox with readable cards, dates, unread state, mark-as-read, and navigation is available to all roles. Assignment notifications are created when a session becomes available. Actual phone push delivery remains a later deployment/device check. |
| 12, 15. Exercise wireframe | Existing wireframes use interpolated landmark rendering at a 50 ms interval for smoother display. This increases visual updates; it does not increase AI inference or camera capture frequency. Shoulder rotation no longer shows the work-in-progress label. |
| 13, 23. Independent practice | Practice opens without requiring an assigned doctor or admin approval. The client does not create session/history records. The live-backend practice flag disables saved artifacts. The backend source change must be deployed later for that server behavior. |
| 14. Wi-Fi connectivity | Live assessment has bounded reconnect attempts, stalled-frame detection, a retry control, and a limit on in-flight frames. API requests have timeouts. Physical Wi-Fi and camera behavior still need phone verification. |
| 16. Assessment smoothness | Landmark interpolation repaints separately from metric updates and prevents an unbounded queue on slow connections. Completed local repetition counts are retained during reconnect attempts. |
| 17. Animation page | Demonstrations repaint inside isolated canvases. Phase text updates only when needed. Scrubbing, speed, pause/play, replay, and wrapping controls support smaller screens. |
| 18. Text session feedback | Reports generate brief and detailed feedback for patients and doctors in English and Hindi. Text uses recorded repetition totals, targets, form flags, and session status. This is structured natural-language generation, not a newly trained NLP model. It does not infer pain, bleeding, clinical improvement, or treatment safety from camera metrics. |
| 20. Screening review | Patients can expand their saved screening answers, result, and recommended action on the dashboard. Doctors retain access to the patient screening card. |
| 21. Doctor session assignment | An Assign now option writes an immediately available prescription. Publishing schedules remains available. Unstarted assignments can be cancelled after confirmation. Active and paused work is protected from accidental replacement. |
| 22. Patient assigned sessions | Due-session activation is transactional and checks the current doctor relationship, approval, published schedule, due time, and expiry. The dashboard no longer hides assignments because of a stale doctor ID. Upcoming and previous sessions have a separate panel. |
| 24. Contact Admin | Doctors use the same Help/Contact Admin page and complaint questions as patients. |
| 25. Complaint identity | Tickets and messages store and display the submitter/sender name and role. Ticket headers show email and identity; older records can fall back to an ID. Dates include day, month, year, and time. |
| 26. Previous/expired sessions | Expired schedules cannot be activated. Previous occurrences are listed separately. New prescriptions do not overwrite active or paused sessions. |
| 27. Doctor recent sessions | The recent panel shows completed prescribed sessions from the last seven days, up to ten entries, with empty/error states. Practice is excluded. Paused sessions remain visible beyond the former 24-hour cutoff. |

## Firebase access changes

- Rules cover patient schedule reads and exact, atomic activation of due prescriptions.
- Patient activation cannot change the prescribed exercises, activate an unpublished/expired schedule, replay an activated occurrence, or replace paused work.
- Due notification writes must correspond to the prescription activated in that transaction.
- Users cannot clear administrator rejection/removal fields themselves.
- Practice records cannot be created as saved assessment sessions.
- Messaging rules check allowed relationships and message length.

These rules and Cloud Functions changes are local. The current production Firebase errors cannot be considered resolved in the installed app until the matching rules/functions and updated app are deployed and checked with the real accounts.

## Verification

- Flutter analysis of `lib` and `test`: no issues.
- Flutter tests: 43 passed, including responsive English/Hindi screens, validation, feedback generation, and report/workflow regressions.
- Firestore emulator permission tests: 19 passed, including denied unauthorized writes and due-session activation guards.
- Server workflow unit tests: 14 passed.
- Git whitespace check: passed.

These checks do not replace live phone, camera, Firebase-account, or network verification. This report does not claim that every possible runtime error has been eliminated.

## Deferred until the next work session

1. Review and deploy the matching Firestore rules and Cloud Functions.
2. Deploy the live-backend practice change to the VM.
3. Build/install an updated APK and verify immediate and scheduled assignments with actual admin, doctor, and patient accounts.
4. Verify physical camera/Wi-Fi behavior, notification delivery, and practice producing no saved history/artifacts.
5. Additional exercise changes and email/SMS two-factor authentication remain future work.

Work stops after this report. No deployment or APK work is started.

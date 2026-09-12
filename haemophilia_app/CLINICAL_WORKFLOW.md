# Clinical workflow implementation

## Included
- Doctor dashboard with assigned patient list.
- Doctor patient profile with session history and aggregate statistics.
- Rep-by-rep clinical review.
- Error-posture image upload to Firebase Storage when an error frame is available.
- Doctor feedback on individual incorrect reps.
- Doctor/patient messaging threads.
- Patient dashboard link for doctor messages.
- Admin user management: promote existing accounts and assign patients to doctors.
- Role-aware Firestore and Storage rules.

## Data model
Existing patient assessment documents remain at:
`users/{patientUid}/assessments/{assessmentId}`

Each assessment has a `sessionId`, so the existing session grouping remains the source of truth. New fields include `errorFrameUrl`, and optional doctor feedback fields.

Messages use:
`users/{patientUid}/messages/{messageId}`

Error images use:
`assessment_errors/{patientUid}/{sessionId}/rep_{n}.jpg`

## Important
The AI/assessment pipeline was not changed. The live WebSocket, 20 FPS setting, MediaPipe processing, LSTM model, scoring, and form-detection logic remain untouched.

Before testing doctor/admin access, publish the included Firebase rules.

# On-device exercise assessment

The `codex/on-device-angle-assessment` branch assesses live exercise camera frames on Android. The camera provides YUV frames to `LocalPoseBridge`, which uses the bundled ML Kit pose detector to find 33 joints. `ExerciseRulesAssessment` then checks joint angles, movement stages, posture, return to the start, and repetition timing. The Flutter screen draws the wireframe and feedback. Normal live frames are not uploaded to the Python backend. An assigned session saves completed repetition data and selected error review images to the existing Firebase history; an unassigned practice session does not save history.

This uses a pretrained general pose detector for joint locations. It does not train or run a separate exercise classifier. The former server assessment remains on `codex/server-assessment-baseline` and is not called by the current live assessment screens. Other app features may still use Firebase or the backend.

## Current tracking presets

The app displays these values before and during an exercise. `Start` and `target` are observed camera angles, in degrees. `ROM` is the minimum excursion for an accepted repetition. A repetition also requires a return to the starting range, stable tracking, and no sustained posture error.

| Exercise | Start | Target | Minimum ROM | Return to own start | Camera view |
| --- | ---: | ---: | ---: | ---: | --- |
| Assisted shoulder flexion | both shoulders ≤40° | both shoulders ≥150° | 75° | within 10° | Front |
| Shoulder rotation | within 8° of observed start | both forearms move ≥20° | 15° | within 4° | Front |
| Assisted elbow flexion | active elbow ≥150° | active elbow ≤90° | 50° | within 8° | Front |
| Elbow flexion and extension | both elbows ≥155° | both elbows ≤90° | 50° | within 8° | Front oblique |
| Heel slide | knee ≥170° | knee ≤90° | 15° | within 10° | Side |
| Mini squat | knee ≥165° | knee ≤130° | 15° | within 8° | Front or side |
| Seated knee extension | knee ≤95° | knee ≥160° | 15° | within 10° | Side |
| Straight leg raise | hip ≥172° | hip ≤140° | 15° | within 10° | Side |
| Terminal knee extension | knee ≤145° | knee ≥170° | 15° | within 6° | Side |
| Squat | knee ≥155° | knee ≤120° | 15° | within 10° | Front or side |

These are provisional software presets, not clinical prescriptions or proof of safe movement. Most joint angles are 2D screen projections and change with camera placement. Elbow joint angles use ML Kit's estimated x/y/z positions to avoid a forearm pointing toward the camera collapsing to a degenerate 2D angle. Estimated depth is also imperfect. Shoulder rotation uses a relative forearm x/z orientation proxy from the pose detector; it cannot measure clinical axial shoulder rotation reliably. Occlusion, unusual anatomy, support devices, and changes in camera orientation can also affect the result. The patient should use the range prescribed by their clinician and stop for pain or bleeding. No diagnostic or clinical accuracy claim is made for the descriptive movement score.

The rule engine rejects frames with missing or degenerate required joints, resets partial movements after a long tracking gap, and counts only a completed outward and return cycle. A valid starting position must be stable for 0.3 seconds. Targets need a 0.2-second continuous hold, with a documented 2° margin for pose jitter. Both arms must meet their individual target in bilateral exercises; an average cannot hide one incomplete arm. Returning must reach the start range and the patient's own starting angle, then hold for 0.2 seconds. A causal angle filter and a 0.3-second posture-error confirmation ignore brief noise. After movement starts, a confirmed error stays incorrect for that repetition even if posture is later corrected. A stalled partial return is flagged and does not complete a correct repetition.

Assisted elbow flexion alternates left and right after an accepted supported repetition; an incorrect repetition retries the same side. Ordinary elbow flexion uses both arms together, with the upper arms beside the torso, matching the previous tutorial. One camera frame is processed at a time; excess frames are dropped. For an incorrect repetition, the app stores at most one local JPEG review frame from the first sustained error or the completed repetition. Feedback includes a specific error code and the movement stage where the first error occurred. Tapping the live feedback opens the full text and target instructions.

The prototype score follows the former shoulder assessment's structure: 45% form, 35% target-range completion, and 20% pace. Form combines posture (75%) and return completion (25%). Smoothness is displayed separately because pose noise can affect it. Incorrect repetitions are capped at 55/100, or 50/100 when the target was not held. History stores the component scores, target status, incorrect stage, left/right peaks, thresholds, and feedback. These scores describe the observed movement and are not model probabilities.

## Review evidence and remaining validation

- All 80 Flutter regression tests passed, including 21 exercise-rule tests and narrow English/Hindi tutorial layout checks. Static analysis found no issues in the changed assessment, tutorial, history, and report files.
- Tests cover all 10 clean synthetic movement cycles, incomplete range/return, one-arm-only elbow movement, a single-frame target spike, sustained versus brief posture errors, loss of tracking, alternation with support, and degenerate joint geometry. These tests verify state transitions and data shape; they do not establish accuracy on patients.
- On the connected CPH2691 phone, one short practice run before the v2 rule changes reported 60 processed pose frames averaging 29 ms each at a 66 ms dispatch interval. Two of 365 sampled UI frames exceeded 16.7 ms, with a worst sampled frame of 25.7 ms. The user confirmed the wireframe and feedback appeared smoothly. The detector and frame pipeline remain the same; the final v2 exercise rules still need filmed checks on real movements.
- Each exercise still needs filmed validation with varied participants, cameras, lighting, viewpoints, and range limitations before clinical use. Check false rep counts and missed reps as well as smoothness. Clinicians should review and approve exercise thresholds and feedback wording.

Android release builds need `android/app/proguard-rules.pro`: WorkManager's Room 2.2 generated database is created by reflection, so its constructor must survive R8 shrinking. Without this rule, the release APK crashes before `MainActivity` starts.

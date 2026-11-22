# Elbow flexion and extension software checks — 10 November 2026




## Working-arm and patient-feedback refinement — 22 November 2026

The user confirmed that outward shoulder movement works as demonstrated in the
tutorial. That counting path is retained. App coordination now compares direction
and timing (maximum 0.6-second onset/return lag), with both arms still required to
reach and hold their own target and return. Unequal camera amplitudes alone no
longer fail the repetition. Sequential starts still fail the regression tests.
Elbow image projection quality uses the lateral forearm component, avoiding a
false reliable bend estimate for a forearm aimed toward the camera.

The assisted-elbow trace showed the opposite supporting arm sometimes bending
first. A provisional role can be corrected from torso-relative crossing geometry
and support proximity. An already held target with observed support is protected
from role changes. There is no forced alternation. Each arm uses its own steady
resting angle with sufficient prescribed available ROM; it does not have to match
a fixed 150-degree estimate. The prescribed flexion target/minimum ROM remain.
Tiny movements under half the minimum ROM (bounded to 15–30 degrees) do not count.

Contact evidence has entry/exit hysteresis: ratios 1.25/1.75 held for 0.12/0.25
seconds. Sustained unsupported cycles still fail. These are camera proximity
suggestions: support_contact_verified remains false, since pose cannot establish
physical contact or assistance force.

Replay of the captured numeric trace produced 10 shoulder cycles (9 meeting the
rules) and 12 assisted-elbow cycles (11 meeting the rules), including completed
right-arm cycles. These are deterministic replay results, not labelled accuracy
percentages or clinical validation. The incomplete target was retained as
incorrect. The rebuilt normal app was installed and opened at 15:50 IST. The fresh live
phone trial logged two correct right-arm cycles (about 83 and 78 degrees of
measured ROM) and one correct left-arm cycle (about 90 degrees). Another cycle
was rejected for missing target hold/support; it was not forced to correct.
No pose-processing exception appeared in that trial. The user replied Right.
All 253 Flutter tests pass, analysis reports no issues, and the original elbow
engine still matches origin/main. These checks verify the exercised software
paths; they do not establish 100% accuracy across patients.
Personal traces and screenshots remain in ignored scratch storage, outside Git.

## Latest phone-feedback follow-up — 22 November 2026

The next phone trial showed that most assisted-elbow failures were SUPPORT_MISSING,
not failure to reach the target. Some completed records contained TARGET_NOT_HELD
and target_reached=true together: a temporary reversal had latched a target error
before the person subsequently reached it. This early latch is removed for
assisted elbow; the final cycle decides target completion. Hand-support evidence
is assessed over meaningful bending, requiring 60% coverage, rather than letting
a short initial or transitional contact estimate poison the full cycle.
Unsupported and below-target cycles still fail the regression tests.

Both affected exercises now use the bundled official MediaPipe Pose Landmarker
full float16 v1 model in VIDEO mode with monotonic timestamps. Its source URL and
SHA-256 are in calibration/pose-landmarker-full.json. The phone confirmed the
full model and VIDEO output without the earlier camera-format exception.
Assisted elbow uses world-coordinate joint angles; the user reported approximately
80% accuracy in this trial. That is user feedback, not a measured accuracy score.
Forced alternation was then removed: a successful repetition no longer instructs
the counter to track the opposite arm while the person continues with the same
supported arm. Selection follows observed support and movement. Existing
prescribed targets remain in use.

The shoulder trial still failed. Logs showed calibration waiting on noisy depth
and raw angle winding beyond a full turn during ordinary movement. App mode now
uses visible lateral forearm movement normalized to torso size and a calibrated
world arm/torso length ratio, producing a bounded camera movement proxy.
Calibration holds an image-space neutral pose and averages the neutral values.
Both paired movement patterns count after return to the held starting position;
the start need not be exactly the middle of a side-to-side sweep. App return
band is 10 degrees, minimum counted paired excursion is 15 degrees, and the
20-degree movement target and timed holds remain explicit in the threshold panel.
Image-observable elbow angles and corroborated torso changes reduce false depth
errors. Legacy report rules remain available separately and are unchanged.

The debug build can capture bounded numeric joint traces with
--dart-define=POSE_DIAGNOSTICS=true. IMAGE and WORLD lines are separated to avoid
Android truncation; no face points or account identifiers are included. Traces
are local debug output, not production test records. A reconstructed trace with
hip midpoint at the MediaPipe-defined origin helped investigate counting but is
not an independent pose-accuracy reference. The prior screen recording still
contains overlays and is not treated as a labelled validation set.

The original Elbow Flexion & Extension engine still matches origin/main. Assisted
Shoulder Flexion with Bar remains the reference, with its detector/rules unchanged.
All 248 Flutter tests pass, analysis reports no issues, and the rebuilt app was
installed and opened on SM-S938B at 15:30 IST. The first new live frames reached
CENTRE after calibration. Completed live shoulder repetitions and grading still
need confirmation; automated passes do not establish 100% measurement accuracy.

## Recording and live-count follow-up — 22 November 2026

The supplied 36.9-second screen recording showed assisted-elbow neutral arms
reported around 120 degrees and the wrong default working side. The elbow
angle for this exercise now uses aspect-corrected image XY, matching its frontal
view and avoiding ML Kit depth distortion. The independent world-elbow engine
still matches origin/main exactly. A neutral start can be established before
support arrives, and the supported working arm is selected before a cycle.
Support uses distance to the forearm segment, including contact near the elbow
or wrist and optional nearby hand tips, scaled to forearm/torso length.
Missing supporting elbows/hips do not invalidate the visible working arm.
The common onset, timed target/return holds, counters and palette remain shared
with Assisted Shoulder Flexion with Bar. That reference exercise was not changed.

The first updated live trial logged three assisted-elbow and two shoulder
repetitions; the user confirmed that both began detecting repetitions, but
reported excessive incorrect labels. This is evidence of live counting, not
confirmation of form accuracy. Subsequent shoulder changes distinguish paired
side-to-side azimuth from independent outward rotation. The selected pattern
stays locked until tracking resets. Upper-arm grading combines the frontal
image angle and world-angle change from a held neutral pose, rather than
penalizing a static model depth offset. Genuine visible lift and changes from
neutral remain errors. Live wireframe warnings use the shared amber adjustment
state before a sustained active-cycle error turns red. Completed shoulder form
retains the documented repetition-level persistence rule.

All 233 Flutter tests pass, including pose-to-preview pixel mapping, both
shoulder protocols, reflected world coordinates, repeated counts, loss of
tracking, neutral depth offset versus visible arm lift, arm selection, support
near the wrist, and rejection of unsupported/incomplete cycles. These fixtures
are engineering checks, not a measured joint-angle reference. Re-estimating
MediaPipe landmarks from the screen recording produced unstable poses with
UI/wireframe overlays and did not establish a successful real-video replay;
that attempt is not counted as validation of the native camera input.

The final debug APK built successfully, analysis reported no issues, and ADB
confirmed replacement installation on SM-S938B at 14:20 IST on 22 November 2026.
The normal app opened successfully and user data was retained. The latest
grading/calibration changes require another manual trial. Debug
REP_METRICS now records completed-rep error codes and target/ROM/duration so
remaining incorrect labels can be investigated individually. Diagnostics do not
log images or account details. Local verification logs: recording-full-tests.log,
recording-analyze.log, recording-build.log (ignored by Git).

## Independent exercise follow-up — 22 November 2026

At the user's request, `lib/services/elbow_world_assessment.dart` was restored
byte-for-byte from `origin/main`. Git comparison reports no differences. No
changes to that exercise's thresholds, counters or scoring are part of the
assisted-elbow/shoulder follow-up. Native RGB frame decoding remains necessary
for the existing world-pose engine to accept camera frames.

Assisted elbow now requires only the working shoulder, elbow, wrist, hip and
supporting wrist. Unused supporting-side elbow/hip occlusion no longer resets
the cycle; actual working-joint visibility and hand support checks remain.
New synthetic tests complete supported cycles on both arms with those unrelated
joints occluded.

Shoulder rotation accepts overlapping, small, interpolated centre crossings
between samples. Large pose jumps and tracking gaps still cannot establish a
crossing. Instantaneous left/right angle fields no longer switch to full
excursion on a completion frame. Previous steady-calibration and re-arm fixes
remain. The source targets are unchanged.

The wireframe is now a child of CameraPreview and shares its viewport. Pixel
tests verify portrait mapping and front-camera mirroring. Actual overlay/body
alignment during user movement still needs live visual confirmation.

All 220 Flutter tests passed and app/test/tool analysis found no issues. The
normal app was rebuilt and installed preserving user data. Debug-only
`EXERCISE_DIAGNOSTIC` lines expose exercise, angle source, stage, expected arm,
angles, count, feedback and required-joint visibility, without images or account
information. Awaiting the user's live trial; these synthetic tests do not prove
real-person accuracy or fix a calibration gate that hasn't been measured.

The first live trial still failed: wrist confidence around 0.64–0.65 kept
resetting shoulder tracking at the draft 0.7 gate, and assisted elbow remained
at its support/starting-position gate. The shoulder visibility gate is now 0.5,
matching the independent world-elbow gate; missing or lower-confidence joints
are still rejected. This engineering change is recorded in the shoulder
calibration JSON. Angular targets were not changed.

MediaPipe frames are now physically rotated upright in RGB before inference,
with ImageProcessingOptions rotation set to zero. This removes ambiguity about
whether normalized output points belong to the sensor image or upright preview;
the Flutter painter alone applies front-camera mirroring. Assisted elbow can
select an initially supported right arm when Left is not supported at rest.
After the first repetition its existing alternation behavior is preserved.
The regression tests retain unsupported-cycle rejection and add the supported
right-arm start. A second normal-app build was installed and opened after these
changes. Awaiting the user's check of actual overlay alignment and completed
repetitions; do not interpret the synthetic passes as live confirmation.

After physically rotating MediaPipe RGB input upright, the live shoulder trial
reported required-joint visibility mostly 0.95–0.99 rather than repeated tracking
loss. It remained in POSITIONING at elbow-bend/upper-arm gates; no completed
shoulder repetition was verified. Calibration feedback now translates those
codes to actionable instructions, and expanded shoulder statistics include
measured left/right elbow bend and upper-arm angles. Logs include bend, upper
arm, sideways lean and wand tilt measurements for further diagnosis.

The assisted-elbow trial reported support-distance ratios around 1.8–2.1 while
the retained gate is 0.8; it did not count a supported cycle. It is not declared
fixed on real movement. Those failures need comparison with a visible manual
trial rather than simply relaxing support requirements. The final normal app
with the added posture guidance was installed; data was preserved.

## Runtime follow-up — 22 November 2026

The phone exposed a native defect not covered by Dart rule fixtures: MediaPipe
PoseLandmarker rejected the NV21 MPImage with `Unsupported MediaPipe Image image
format: 4`. Both shoulder rotation and elbow flexion/extension share this path.
The Android bridge now converts packed NV21 to RGB on its worker thread before
calling MediaPipe, retaining the camera rotation and world-coordinate rules.
Images close in a `finally` block. Missing optional landmark presence values
are no longer fabricated as zero; real reported low confidence is still rejected.

Verified on Samsung SM-S938B: blank-frame native calls succeeded in all four
rotations for both ML Kit and MediaPipe (eight checks). Live frames processed
through shoulder rotation, elbow flexion/extension and assisted shoulder flexion
without the unsupported-format exception. The elbow reached READY with valid
joints; the shoulder pass did not obtain enough valid full-body joints to
verify calibration or a completed repetition. No completed real-person rep
count or technique-accuracy claim is made from these transport checks.

The initial live diagnostic was blocked by Android camera policy; the user
unlocked/enabled camera access and the rerun processed frames. The diagnostic
entrypoint `haemophilia_app/tool/pose_device_check.dart` initializes no Firebase
services and writes no production records. Results are in ignored
`pose-device-results.log`. All 214 Flutter tests passed and app/test/tool
analysis reported no issues after the runtime fix.

## Result

No failures found in the exercised automated paths. This is software verification,
not a claim that the app measures an individual person's technique accurately.
The active Android exercise uses `ElbowWorldAssessment` through
`ExerciseRulesAssessment`, with MediaPipe world-coordinate pose landmarks.
The server's elbow LSTM tests cover a separate legacy path.

## Verified

| Aspect | Evidence |
| --- | --- |
| Targets and source | Constants match the supplied calibration JSON; correct world-pose backend selected; no image-angle fallback |
| Complete repetitions | Both arms meet their own flexion, range and return requirements; counters and serialized output verified |
| Incorrect movements | Individual target misses, insufficient range, bilateral discrepancies and incomplete return tested |
| Timing | Extension/flexion/return holds, elapsed-time smoothing, varying cadence, timeout and bounded traces tested |
| Tracking interruptions | Missing/invalid joints, low confidence, degenerate vectors, timestamp reversal/duplication, large gaps and resets tested without phantom reps |
| Repetition stability | Added ten-cycle count/serialization regression and subsequent idle-jitter check; exactly ten completed reps |
| Geometry | Added rigid rotation, translation and scale invariance check for world-coordinate angles |
| UI and session flow | Focused tests cover native channel selection, English/Hindi threshold panels, assignment timing, expiry and resume guards |
| Saved-result fields | Reviewed mapping of score, angle traces, per-arm metrics, thresholds, provenance, target and return details into assessment history; live authenticated writes not performed |
| Build | Debug APK built; bundled pose task, arm64 MediaPipe/Flutter libraries and plugin registration verified |

49 focused Flutter tests passed before the additions. The expanded full Flutter
suite passed all 211 tests; active app/test analysis found no issues. All 16
backend elbow integration/model tests also passed.

## Limits requiring manual verification

- No labelled real-person video replay or measured joint-angle reference was
  supplied. False-positive/negative rates and clinical accuracy are unverified.
- Source thresholds are asymmetric and labelled `person_specific_candidate`,
  derived from 22 approved source repetitions; they are not universal targets.
  No thresholds were changed for this review.
- Both arms must be trackable. Occlusion, camera view, lighting and inference
  speed need checking on the actual phone during a session.
- Live account login, camera-session behavior, persisted history and doctor
  reports require an authenticated manual session. No production test records
  were created during this review.
- The earlier phone installation displayed a native-library 16 KB compatibility
  warning. APK packaging checks do not establish that warning is fixed.

## Manual feedback checklist

Use the app's existing exercise instructions and assigned limits. Check whether
displayed left/right angles follow movement, completed reps count once, stopping
or losing tracking avoids extra reps, and pause/resume preserves completed
progress. After saving, check history and report details.

For each issue, record phone orientation/camera, displayed stage, expected versus
actual count, feedback text, and whether it happens consistently. A short
consented recording is useful for later reproducible software analysis.

Logs: `elbow-focused-tests.log`, `elbow-full-tests.log`, `elbow-analyze.log`,
`elbow-backend-tests.log`, `elbow-build.log` in the repository root (ignored).

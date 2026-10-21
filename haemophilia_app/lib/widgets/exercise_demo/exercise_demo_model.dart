import 'package:flutter/material.dart';

import '../../utils/exercise_utils.dart';
import 'shoulder_flexion_painter.dart';
import 'shoulder_rotation_painter.dart';
import 'elbow_flexion_painter.dart';
import 'assisted_elbow_flexion_painter.dart';
import 'lower_body_painter.dart';

/// Represents a single movement phase of an exercise demonstration.
class ExercisePhase {
  final int phaseNumber;
  final String title;
  final String description;
  final double startProgress;
  final double endProgress;

  const ExercisePhase({
    required this.phaseNumber,
    required this.title,
    required this.description,
    required this.startProgress,
    required this.endProgress,
  });

  bool contains(double progress) {
    return progress >= startProgress && progress <= endProgress;
  }
}

/// Configuration and asset metadata for an exercise visual demonstration.
class ExerciseDemoConfig {
  final String exerciseId;
  final String displayName;
  final bool isWorkInProgress;
  final List<ExercisePhase> phases;
  final List<String> keyTips;
  final CustomPainter Function(double progress, {bool isDark}) painterBuilder;

  const ExerciseDemoConfig({
    required this.exerciseId,
    required this.displayName,
    required this.isWorkInProgress,
    required this.phases,
    required this.keyTips,
    required this.painterBuilder,
  });

  ExercisePhase getPhaseForProgress(double progress) {
    for (final phase in phases) {
      if (phase.contains(progress)) {
        return phase;
      }
    }
    return phases.isNotEmpty
        ? phases.first
        : const ExercisePhase(
            phaseNumber: 1,
            title: 'Starting Position',
            description: 'Begin in standard ready position.',
            startProgress: 0.0,
            endProgress: 1.0,
          );
  }
}

/// Registry mapping exercise identifiers to demonstration configurations.
class ExerciseDemoRegistry {
  static ExerciseDemoConfig get(String? exerciseIdOrName) {
    final raw = exerciseIdOrName ?? '';
    final canonical = normalizeExerciseId(raw);

    switch (canonical) {
      case kAssistedShoulderFlexion:
        return _assistedShoulderFlexionConfig;

      case kShoulderRotation:
        return _shoulderRotationConfig;

      case kAssistedElbowFlexionV5:
      case kAssistedElbowFlexion:
        return _assistedElbowFlexionConfig;

      case kElbowFlexionExtension:
        return _elbowFlexionConfig;

      case kHeelSlide:
        return _heelSlideConfig;

      case kMiniSquat:
        return _miniSquatConfig;

      case kSeatedKneeExtension:
        return _seatedKneeExtensionConfig;

      case kStraightLegRaise:
        return _straightLegRaiseConfig;

      case kTerminalKneeExtension:
        return _terminalKneeExtensionConfig;

      case kSquat:
        return _squatConfig;

      default:
        return _createWipFallbackConfig(raw);
    }
  }

  // ============================================================
  // 1. ASSISTED SHOULDER FLEXION WITH BAR (VALIDATED / PRIMARY)
  // ============================================================

  static final ExerciseDemoConfig _assistedShoulderFlexionConfig =
      ExerciseDemoConfig(
        exerciseId: kAssistedShoulderFlexion,
        displayName: 'Assisted Shoulder Flexion with Bar',
        isWorkInProgress: false,
        phases: const [
          ExercisePhase(
            phaseNumber: 1,
            title: 'Starting Position',
            description: 'Hold the bar horizontally with both hands at thigh level. Keep your back straight, chest open, and shoulders relaxed.',
            startProgress: 0.0,
            endProgress: 0.15,
          ),
          ExercisePhase(
            phaseNumber: 2,
            title: 'Upward Movement',
            description: 'Slowly raise both arms forward and upward together. Keep elbows straight and use the unaffected arm to guide the movement.',
            startProgress: 0.15,
            endProgress: 0.50,
          ),
          ExercisePhase(
            phaseNumber: 3,
            title: 'Overhead Position',
            description: 'Hold briefly at the comfortable top position. Maintain an upright posture and avoid arching your lower back.',
            startProgress: 0.50,
            endProgress: 0.60,
          ),
          ExercisePhase(
            phaseNumber: 4,
            title: 'Downward Movement',
            description: 'Lower the bar smoothly along the same arc with steady control. Do not let the arms drop suddenly.',
            startProgress: 0.60,
            endProgress: 0.95,
          ),
          ExercisePhase(
            phaseNumber: 5,
            title: 'Return to Start',
            description: 'Pause momentarily in the starting position before beginning the next repetition.',
            startProgress: 0.95,
            endProgress: 1.0,
          ),
        ],
        keyTips: const [
          'Keep both hands evenly spaced on the bar.',
          'Maintain steady breathing — inhale on lift, exhale on lower.',
          'Do not lean back or shrug your shoulders.',
          'Stop if you experience sharp joint pain.',
        ],
        painterBuilder: (progress, {bool isDark = true}) =>
            ShoulderFlexionPainter(progress: progress, isDark: isDark),
      );

  // ============================================================
  // 2. SHOULDER ROTATION (WORK IN PROGRESS)
  // ============================================================

  static final ExerciseDemoConfig _shoulderRotationConfig = ExerciseDemoConfig(
    exerciseId: kShoulderRotation,
    displayName: 'Shoulder Rotation',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description: 'Stand upright facing forward with elbows bent at 90° tucked closely against your torso, forearms pointing straight forward.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Outward Rotation',
        description: 'Slowly rotate both forearms outward away from the midline while keeping elbows pinned firmly against your sides.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Peak External Rotation',
        description: 'Hold momentarily at your comfortable, pain-free outward rotation limit without twisting your torso.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Inward Return',
        description: 'Smoothly rotate forearms back toward the center with steady, controlled motion.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Return to Start',
        description: 'Pause momentarily in the neutral starting position before beginning the next repetition.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Keep elbows firmly pinned against your ribs throughout the entire movement.',
      'Maintain an upright posture without leaning or twisting your chest.',
      'Work strictly within your comfortable, pain-free range of motion.',
      'Follow your clinician’s guidance on repetition targets and pacing.',
    ],
    painterBuilder: (progress, {bool isDark = true}) =>
        ShoulderRotationPainter(progress: progress, isDark: isDark),
  );

  // ============================================================
  // 3. ASSISTED ELBOW FLEXION (PROVISIONAL TRACKING GUIDANCE)
  // ============================================================

  static final ExerciseDemoConfig _assistedElbowFlexionConfig =
      ExerciseDemoConfig(
        exerciseId: kAssistedElbowFlexion,
        displayName: 'Assisted Elbow Flexion',
        isWorkInProgress: false,
        phases: const [
          ExercisePhase(
            phaseNumber: 1,
            title: 'Starting Position',
            description: 'Keep active arm relaxed at your side with the opposite hand gently supporting under the wrist or forearm.',
            startProgress: 0.0,
            endProgress: 0.20,
          ),
          ExercisePhase(
            phaseNumber: 2,
            title: 'Assisted Bending',
            description: 'Use your supporting hand to guide and gently assist bending the recovering elbow upward.',
            startProgress: 0.20,
            endProgress: 0.50,
          ),
          ExercisePhase(
            phaseNumber: 3,
            title: 'Peak Flexion',
            description: 'Pause briefly at the top position where the hand approaches shoulder height without strain.',
            startProgress: 0.50,
            endProgress: 0.60,
          ),
          ExercisePhase(
            phaseNumber: 4,
            title: 'Controlled Lowering',
            description: 'Carefully lower the forearm back down with the supporting hand guiding the descent smoothly.',
            startProgress: 0.60,
            endProgress: 0.95,
          ),
          ExercisePhase(
            phaseNumber: 5,
            title: 'Return to Start',
            description: 'Fully relax at the starting extension before beginning the next repetition.',
            startProgress: 0.95,
            endProgress: 1.0,
          ),
        ],
        keyTips: const [
          'Use your opposite hand to take weight off the recovering joint.',
          'Keep the upper arm still and avoid swinging your elbow forward.',
          'Move slowly and stop immediately if sharp discomfort occurs.',
          'Follow your clinician’s guidance on repetition targets and pacing.',
        ],
        painterBuilder: (progress, {bool isDark = true}) =>
            AssistedElbowFlexionPainter(progress: progress, isDark: isDark),
      );

  // ============================================================
  // 4. ELBOW FLEXION & EXTENSION (PROVISIONAL TRACKING GUIDANCE)
  // ============================================================

  static final ExerciseDemoConfig _elbowFlexionConfig = ExerciseDemoConfig(
    exerciseId: kElbowFlexionExtension,
    displayName: 'Elbow Flexion & Extension',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description: 'Keep both upper arms beside your torso. Meet the separately shown left and right extension thresholds and wait for Ready.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Bending (Flexion)',
        description: 'Curl both forearms toward your shoulders. Keep both upper arms beside your torso and avoid swinging.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Peak Flexion',
        description: 'Reach each arm’s separately shown flexion target and hold briefly. These person-specific references do not replace your clinician’s comfortable range.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Straightening (Extension)',
        description: 'Straighten both elbows together with control. Meet each arm’s shown extension and return-error limits.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Return to Start',
        description: 'Pause at the starting position until Ready appears. An incorrect repetition must be retried.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Keep both upper arms beside your torso.',
      'Perform movement smoothly without swinging.',
      'Work within comfortable pain-free range.',
      'Follow your clinician’s guidance on repetition targets and pacing.',
    ],
    painterBuilder: (progress, {bool isDark = true}) =>
        ElbowFlexionPainter(progress: progress, isDark: isDark),
  );

  // ============================================================
  // 5. HEEL SLIDE
  // ============================================================

  static final ExerciseDemoConfig _heelSlideConfig = ExerciseDemoConfig(
    exerciseId: kHeelSlide,
    displayName: 'Heel Slide',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description:
            'Lie supine on a flat surface with both legs extended relaxed.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Sliding Inward',
        description: 'Slowly bend your knee, sliding your heel smoothly toward your buttocks.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Peak Knee Flexion',
        description: 'Hold momentarily at your comfortable flexion limit without hip lifting.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Controlled Return',
        description: 'Smoothly slide your heel back down until your knee is fully extended.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Rest at Extension',
        description: 'Pause briefly in the neutral starting position before next repetition.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Keep heel in light, continuous contact with the treatment surface.',
      'Do not lift your pelvis off the mat.',
      'Work strictly within comfortable, pain-free range of motion.',
    ],
    painterBuilder: (progress, {bool isDark = true}) => LowerBodyPainter(
      exercise: kHeelSlide,
      progress: progress,
      isDark: isDark,
    ),
  );

  // ============================================================
  // 6. MINI SQUAT
  // ============================================================

  static final ExerciseDemoConfig _miniSquatConfig = ExerciseDemoConfig(
    exerciseId: kMiniSquat,
    displayName: 'Mini Squat',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description: 'Stand upright with feet shoulder-width apart and toes pointing slightly outward.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Shallow Squat',
        description: 'Bend both knees gently toward the shown target within your comfortable range, keeping them aligned with your feet.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Bottom Hold',
        description: 'Hold momentarily ensuring heels remain firmly planted on the floor.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Return to Stand',
        description: 'Drive through your heels to return smoothly to an upright standing posture.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Full Extension',
        description:
            'Stand tall with knees unlocked before beginning next rep.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Avoid letting knees cave inward or bow outward.',
      'Keep your chest lifted and avoid excessive forward torso lean.',
      'Keep heels pressed firmly into the ground.',
    ],
    painterBuilder: (progress, {bool isDark = true}) => LowerBodyPainter(
      exercise: kMiniSquat,
      progress: progress,
      isDark: isDark,
    ),
  );

  // ============================================================
  // 7. SEATED KNEE EXTENSION
  // ============================================================

  static final ExerciseDemoConfig
  _seatedKneeExtensionConfig = ExerciseDemoConfig(
    exerciseId: kSeatedKneeExtension,
    displayName: 'Seated Knee Extension',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description: 'Sit upright in a firm chair with back supported and knees bent at 90 degrees.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Straightening Leg',
        description: 'Slowly straighten your knee, lifting your lower leg toward horizontal.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Terminal Extension',
        description:
            'Hold at full pain-free extension, engaging the quadriceps muscle.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Controlled Lowering',
        description:
            'Lower foot back down under control to the resting position.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Rest Position',
        description: 'Pause before starting the next repetition.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Maintain an upright spine without slouching or rocking backward.',
      'Do not lift your thigh off the chair surface.',
      'Achieve steady, controlled terminal extension.',
    ],
    painterBuilder: (progress, {bool isDark = true}) => LowerBodyPainter(
      exercise: kSeatedKneeExtension,
      progress: progress,
      isDark: isDark,
    ),
  );

  // ============================================================
  // 8. STRAIGHT LEG RAISE
  // ============================================================

  static final ExerciseDemoConfig _straightLegRaiseConfig = ExerciseDemoConfig(
    exerciseId: kStraightLegRaise,
    displayName: 'Straight Leg Raise',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description: 'Lie flat on back with opposite knee bent and foot flat on the floor.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Straight Leg Lift',
        description: 'Keep the lifting knee straight and raise the leg to about 40 degrees, within your prescribed comfortable range.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Peak Elevation',
        description: 'Hold momentarily at the top height, keeping your pelvis flat on the mat.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Slow Descent',
        description: 'Lower your straight leg steadily back to the surface.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Neutral Rest',
        description: 'Pause briefly before starting the next repetition.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Keep the exercising knee completely straight throughout the lift.',
      'Do not lift your head or arch your lower back off the floor.',
      'Move with a slow, controlled cadence.',
    ],
    painterBuilder: (progress, {bool isDark = true}) => LowerBodyPainter(
      exercise: kStraightLegRaise,
      progress: progress,
      isDark: isDark,
    ),
  );

  // ============================================================
  // 9. TERMINAL KNEE EXTENSION
  // ============================================================

  static final ExerciseDemoConfig _terminalKneeExtensionConfig =
      ExerciseDemoConfig(
        exerciseId: kTerminalKneeExtension,
        displayName: 'Terminal Knee Extension',
        isWorkInProgress: false,
        phases: const [
          ExercisePhase(
            phaseNumber: 1,
            title: 'Starting Position',
            description: 'Lie on back with a bolster or rolled towel supporting under the knee.',
            startProgress: 0.0,
            endProgress: 0.20,
          ),
          ExercisePhase(
            phaseNumber: 2,
            title: 'Heel Elevation',
            description: 'Straighten your knee by lifting your heel off the mat while keeping thigh firmly on bolster.',
            startProgress: 0.20,
            endProgress: 0.50,
          ),
          ExercisePhase(
            phaseNumber: 3,
            title: 'Peak Lockout',
            description: 'Hold at maximum terminal knee extension, activating the inner quadriceps (VMO).',
            startProgress: 0.50,
            endProgress: 0.60,
          ),
          ExercisePhase(
            phaseNumber: 4,
            title: 'Controlled Descent',
            description: 'Lower the heel back to the bed smoothly.',
            startProgress: 0.60,
            endProgress: 0.95,
          ),
          ExercisePhase(
            phaseNumber: 5,
            title: 'Rest',
            description: 'Pause momentarily before the next repetition.',
            startProgress: 0.95,
            endProgress: 1.0,
          ),
        ],
        keyTips: const [
          'Keep the back of your thigh pressed firmly against the bolster.',
          'Only the lower leg and heel should move.',
          'Focus on full, pain-free knee extension.',
        ],
        painterBuilder: (progress, {bool isDark = true}) => LowerBodyPainter(
          exercise: kTerminalKneeExtension,
          progress: progress,
          isDark: isDark,
        ),
      );

  // ============================================================
  // 10. SQUAT
  // ============================================================

  static final ExerciseDemoConfig _squatConfig = ExerciseDemoConfig(
    exerciseId: kSquat,
    displayName: 'Squat',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description: 'Stand with feet shoulder-width apart, arms forward for balance, chest high.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Descent',
        description: 'Hinge hips back and bend knees, sitting down and back with knees tracking over toes.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Bottom Depth',
        description: 'Pause briefly at the shown partial-squat depth within your comfortable range, keeping your heels grounded.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Ascent',
        description: 'Push through heels and midfoot to return upward with upright torso.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Stand Tall',
        description: 'Finish upright with hips and knees extended before the next repetition.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Push knees outward to prevent valgus cave.',
      'Keep chest up and avoid excessive forward torso lean.',
      'Keep whole foot flat and grounded throughout.',
    ],
    painterBuilder: (progress, {bool isDark = true}) =>
        LowerBodyPainter(exercise: kSquat, progress: progress, isDark: isDark),
  );

  // ============================================================
  // WIP FALLBACK CONFIG
  // ============================================================

  static ExerciseDemoConfig _createWipFallbackConfig(String rawName) {
    final displayName = getExerciseDisplayName(rawName);
    return ExerciseDemoConfig(
      exerciseId: rawName.toLowerCase().replaceAll(' ', '_'),
      displayName: displayName,
      isWorkInProgress: true,
      phases: const [
        ExercisePhase(
          phaseNumber: 1,
          title: 'Starting Position',
          description:
              'Assume a relaxed, upright posture facing the camera directly.',
          startProgress: 0.0,
          endProgress: 0.25,
        ),
        ExercisePhase(
          phaseNumber: 2,
          title: 'Exercise Movement',
          description: 'Perform the prescribed movement smoothly through your safe range of motion.',
          startProgress: 0.25,
          endProgress: 0.75,
        ),
        ExercisePhase(
          phaseNumber: 3,
          title: 'Return to Rest',
          description: 'Return with control to starting position and prepare for next rep.',
          startProgress: 0.75,
          endProgress: 1.0,
        ),
      ],
      keyTips: const [
        'Move with smooth, steady speed.',
        'Follow your doctor’s personalized range instructions.',
        'Follow your clinician’s guidance on repetition targets and pacing.',
      ],
      painterBuilder: (progress, {bool isDark = true}) =>
          ShoulderRotationPainter(progress: progress, isDark: isDark),
    );
  }
}

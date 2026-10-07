import 'package:flutter/material.dart';
import '../../utils/exercise_utils.dart';
import 'shoulder_flexion_painter.dart';
import 'shoulder_rotation_painter.dart';
import 'elbow_flexion_painter.dart';
import 'assisted_elbow_flexion_painter.dart';

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

      case kAssistedElbowFlexion:
        return _assistedElbowFlexionConfig;

      case kElbowFlexionExtension:
        return _elbowFlexionConfig;

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
        description:
            'Hold the bar horizontally with both hands at thigh level. Keep your back straight, chest open, and shoulders relaxed.',
        startProgress: 0.0,
        endProgress: 0.15,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Upward Movement',
        description:
            'Slowly raise both arms forward and upward together. Keep elbows straight and use the unaffected arm to guide the movement.',
        startProgress: 0.15,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Overhead Position',
        description:
            'Hold briefly at the comfortable top position. Maintain an upright posture and avoid arching your lower back.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Downward Movement',
        description:
            'Lower the bar smoothly along the same arc with steady control. Do not let the arms drop suddenly.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Return to Start',
        description:
            'Pause momentarily in the starting position before beginning the next repetition.',
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
  // 2. SHOULDER ROTATION
  // ============================================================

  static final ExerciseDemoConfig _shoulderRotationConfig = ExerciseDemoConfig(
    exerciseId: kShoulderRotation,
    displayName: 'Shoulder Rotation',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description:
            'Stand facing the camera with both hands on the bar. Hold it at centre briefly before starting.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Rotate to One Side',
        description:
            'Move the bar slowly to one side while keeping your elbows near your torso.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Side Position',
        description:
            'Hold momentarily at your comfortable, pain-free outward rotation limit without twisting your torso.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Return to Centre',
        description:
            'Smoothly rotate forearms back toward the center with steady, controlled motion.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Return to Start',
        description:
            'Centre to one side to centre is one repetition. Repeat on either side.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'One repetition: centre to one side to centre.',
      'Keep elbows firmly pinned against your ribs throughout the entire movement.',
      'Maintain an upright posture without leaning or twisting your chest.',
      'Work strictly within your comfortable, pain-free range of motion.',
      'Follow your clinician’s guidance on repetition targets and pacing.',
    ],
    painterBuilder: (progress, {bool isDark = true}) =>
        ShoulderRotationPainter(progress: progress, isDark: isDark),
  );

  // ============================================================
  // 3. ASSISTED ELBOW FLEXION (CLINICALLY VALIDATED)
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
        description:
            'Keep active arm relaxed at your side with the opposite hand gently supporting under the wrist or forearm.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Assisted Bending',
        description:
            'Use your supporting hand to guide and gently assist bending the recovering elbow upward.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Peak Flexion',
        description:
            'Pause briefly at the top position where the hand approaches shoulder height without strain.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Controlled Lowering',
        description:
            'Carefully lower the forearm back down with the supporting hand guiding the descent smoothly.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Return to Start',
        description:
            'Fully relax at the starting extension before beginning the next repetition.',
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
  // 4. ELBOW FLEXION & EXTENSION (CLINICALLY VALIDATED)
  // ============================================================

  static final ExerciseDemoConfig _elbowFlexionConfig = ExerciseDemoConfig(
    exerciseId: kElbowFlexionExtension,
    displayName: 'Elbow Flexion & Extension',
    isWorkInProgress: false,
    phases: const [
      ExercisePhase(
        phaseNumber: 1,
        title: 'Starting Position',
        description:
            'Hold arm at side with elbow extended, palm facing forward.',
        startProgress: 0.0,
        endProgress: 0.20,
      ),
      ExercisePhase(
        phaseNumber: 2,
        title: 'Bending (Flexion)',
        description:
            'Smoothly bend the elbow upward, keeping upper arm still against torso.',
        startProgress: 0.20,
        endProgress: 0.50,
      ),
      ExercisePhase(
        phaseNumber: 3,
        title: 'Peak Flexion',
        description:
            'Briefly hold at top with hand approaching shoulder height.',
        startProgress: 0.50,
        endProgress: 0.60,
      ),
      ExercisePhase(
        phaseNumber: 4,
        title: 'Straightening (Extension)',
        description:
            'Lower forearm back down with steady control to starting position.',
        startProgress: 0.60,
        endProgress: 0.95,
      ),
      ExercisePhase(
        phaseNumber: 5,
        title: 'Return to Start',
        description: 'Pause briefly before beginning next repetition.',
        startProgress: 0.95,
        endProgress: 1.0,
      ),
    ],
    keyTips: const [
      'Keep upper arm locked beside your torso.',
      'Perform movement smoothly without swinging.',
      'Work within comfortable pain-free range.',
      'Follow your clinician’s guidance on repetition targets and pacing.',
    ],
    painterBuilder: (progress, {bool isDark = true}) =>
        ElbowFlexionPainter(progress: progress, isDark: isDark),
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
          description:
              'Perform the prescribed movement smoothly through your safe range of motion.',
          startProgress: 0.25,
          endProgress: 0.75,
        ),
        ExercisePhase(
          phaseNumber: 3,
          title: 'Return to Rest',
          description:
              'Return with control to starting position and prepare for next rep.',
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

import 'package:flutter/material.dart';
import '../../utils/exercise_utils.dart';
import 'shoulder_flexion_painter.dart';
import 'elbow_flexion_painter.dart';

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
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    // 1. Production Ready: Assisted Shoulder Flexion with Bar
    if (normalized == 'assisted_shoulder_flexion' ||
        normalized == 'assisted_shoulder_flexion_with_bar' ||
        normalized.startsWith('assisted_shoulder_flexion') ||
        normalized.contains('shoulder_flexion')) {
      return _assistedShoulderFlexionConfig;
    }

    // 2. Work in Progress: Elbow Flexion & Extension
    if (normalized.contains('elbow')) {
      return _elbowFlexionConfig;
    }

    // 3. Fallback for WIP or unknown exercises
    return _createWipFallbackConfig(raw);
  }

  // ============================================================
  // ASSISTED SHOULDER FLEXION WITH BAR (PRIORITY 1)
  // ============================================================

  static final ExerciseDemoConfig _assistedShoulderFlexionConfig =
      ExerciseDemoConfig(
    exerciseId: 'assisted_shoulder_flexion',
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
  // ELBOW FLEXION & EXTENSION (WIP)
  // ============================================================

  static final ExerciseDemoConfig _elbowFlexionConfig = ExerciseDemoConfig(
    exerciseId: 'elbow_flexion',
    displayName: 'Elbow Flexion & Extension',
    isWorkInProgress: true,
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
        'Clinical validation is currently in progress.',
      ],
      painterBuilder: (progress, {bool isDark = true}) =>
          ShoulderFlexionPainter(progress: progress, isDark: isDark),
    );
  }
}

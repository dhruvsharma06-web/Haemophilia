import 'package:flutter/material.dart';

import 'app_localizations.dart';

// Canonical exercise identifiers
const String kAssistedShoulderFlexion = 'assisted_shoulder_flexion';
const String kShoulderRotation = 'shoulder_rotation';
const String kAssistedElbowFlexion = 'assisted_elbow_flexion';
const String kElbowFlexionExtension = 'elbow_flexion_extension';

/// Metadata for an exercise in the Haemophilia physiotherapy catalog.
class ExerciseMetadata {
  final String id;
  final String displayName;
  final String shortName;
  final String targetJoint;
  final String description;
  final IconData icon;
  final bool isWorkInProgress;
  final String statusLabel;

  const ExerciseMetadata({
    required this.id,
    required this.displayName,
    required this.shortName,
    required this.targetJoint,
    required this.description,
    required this.icon,
    required this.isWorkInProgress,
    required this.statusLabel,
  });
}

/// Catalog of all 4 supported exercises
const List<ExerciseMetadata> kAllExercises = [
  ExerciseMetadata(
    id: kAssistedShoulderFlexion,
    displayName: 'Assisted Shoulder Flexion with Bar',
    shortName: 'Shoulder Flexion',
    targetJoint: 'Shoulders',
    description: 'Two-handed bar elevation exercise targeting shoulder mobility and joint preservation.',
    icon: Icons.accessibility_new_rounded,
    isWorkInProgress: false,
    statusLabel: 'Clinically Validated',
  ),
  ExerciseMetadata(
    id: kShoulderRotation,
    displayName: 'Shoulder Rotation',
    shortName: 'Shoulder Rotation',
    targetJoint: 'Rotator Cuff',
    description: 'Bilateral internal and external rotation with elbows flexed 90° pinned to torso.',
    icon: Icons.rotate_right_rounded,
    isWorkInProgress: true,
    statusLabel: 'Exercise demo available',
  ),
  ExerciseMetadata(
    id: kAssistedElbowFlexion,
    displayName: 'Assisted Elbow Flexion',
    shortName: 'Assisted Elbow',
    targetJoint: 'Elbow Joint',
    description: 'Supported elbow bending using contralateral hand guidance to protect recovering joints.',
    icon: Icons.pan_tool_outlined,
    isWorkInProgress: false,
    statusLabel: 'Clinically Validated',
  ),
  ExerciseMetadata(
    id: kElbowFlexionExtension,
    displayName: 'Elbow Flexion & Extension',
    shortName: 'Elbow Flex / Ext',
    targetJoint: 'Elbow Joint',
    description: 'Smooth, controlled elbow bending and extension throughout comfortable pain-free range.',
    icon: Icons.fitness_center_rounded,
    isWorkInProgress: false,
    statusLabel: 'Clinically Validated',
  ),
];

/// Normalizes an exercise name or ID to one of the 4 canonical identifiers.
String normalizeExerciseId(String? exercise) {
  if (exercise == null || exercise.trim().isEmpty) return kAssistedShoulderFlexion;
  final normalized = exercise.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

  if (normalized == 'assisted_shoulder_flexion' ||
      normalized == 'assisted_shoulder_flexion_with_bar' ||
      normalized.startsWith('assisted_shoulder_flexion') ||
      normalized.contains('shoulder_flexion')) {
    return kAssistedShoulderFlexion;
  }

  if (normalized == 'shoulder_rotation' ||
      normalized.contains('rotation')) {
    return kShoulderRotation;
  }

  if (normalized == 'assisted_elbow_flexion' ||
      normalized.contains('assisted_elbow')) {
    return kAssistedElbowFlexion;
  }

  if (normalized == 'elbow_flexion' ||
      normalized == 'elbow_flexion_extension' ||
      normalized.contains('elbow')) {
    return kElbowFlexionExtension;
  }

  return normalized;
}

/// Returns true if the exercise is Work In Progress (not yet fully production-ready / validated).
/// Production-ready: Assisted Shoulder Flexion, Assisted Elbow Flexion, Elbow Flexion & Extension.
/// Shoulder Rotation remains Work In Progress (to be provided later).
bool isWorkInProgressExercise(String? exerciseName) {
  if (exerciseName == null || exerciseName.trim().isEmpty) return false;
  final canonical = normalizeExerciseId(exerciseName);

  if (canonical == kAssistedShoulderFlexion ||
      canonical == kAssistedElbowFlexion ||
      canonical == kElbowFlexionExtension) {
    return false;
  }

  // Work In Progress: Shoulder Rotation
  return true;
}

/// Standard display name for an exercise
String getExerciseDisplayName(String? exercise) {
  if (exercise == null || exercise.trim().isEmpty) return 'Exercise';
  final canonical = normalizeExerciseId(exercise);

  switch (canonical) {
    case kAssistedShoulderFlexion:
      return 'Assisted Shoulder Flexion with Bar';
    case kShoulderRotation:
      return 'Shoulder Rotation';
    case kAssistedElbowFlexion:
      return 'Assisted Elbow Flexion';
    case kElbowFlexionExtension:
      return 'Elbow Flexion & Extension';
    default:
      return exercise;
  }
}

/// Standard icon for an exercise
IconData getExerciseIcon(String? exercise) {
  final canonical = normalizeExerciseId(exercise);
  switch (canonical) {
    case kAssistedShoulderFlexion:
      return Icons.accessibility_new_rounded;
    case kShoulderRotation:
      return Icons.rotate_right_rounded;
    case kAssistedElbowFlexion:
      return Icons.pan_tool_outlined;
    case kElbowFlexionExtension:
      return Icons.fitness_center_rounded;
    default:
      return Icons.fitness_center_rounded;
  }
}

/// Reusable preview badge widget.
Widget buildWipBadge({
  bool isDark = false,
  bool compact = false,
}) {
  final backgroundColor = isDark
      ? Colors.amber.withValues(alpha: 0.18)
      : const Color(0xFFFFF3E0); // Orange shade 50
  final borderColor = isDark
      ? Colors.amberAccent.withValues(alpha: 0.65)
      : const Color(0xFFFFB74D); // Orange shade 300
  final textColor = isDark
      ? Colors.amberAccent
      : const Color(0xFFE65100); // Orange shade 900
  final iconColor = isDark
      ? Colors.amberAccent
      : const Color(0xFFE65100);

  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 8,
      vertical: compact ? 2 : 4,
    ),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: borderColor,
        width: 1.0,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.play_circle_outline_rounded,
          size: compact ? 11 : 13,
          color: iconColor,
        ),
        SizedBox(width: compact ? 3 : 5),
        Text(
          tr('Preview exercise'),
          style: TextStyle(
            color: textColor,
            fontSize: compact ? 9.5 : 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            shadows: isDark
                ? const [Shadow(color: Colors.black, blurRadius: 4)]
                : null,
          ),
        ),
      ],
    ),
  );
}

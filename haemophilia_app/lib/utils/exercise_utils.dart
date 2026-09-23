import 'package:flutter/material.dart';

/// Returns true if the exercise is Work In Progress (not yet fully production-ready / validated).
/// Currently, only "Assisted Shoulder Flexion with Bar" is production-ready.
/// "Elbow Flexion & Extension" and "Shoulder Rotation" are Work In Progress.
bool isWorkInProgressExercise(String? exerciseName) {
  if (exerciseName == null || exerciseName.trim().isEmpty) return false;
  final normalized = exerciseName.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

  // Production-ready: Assisted Shoulder Flexion (with Bar)
  if (normalized == 'assisted_shoulder_flexion' ||
      normalized == 'assisted_shoulder_flexion_with_bar' ||
      normalized.startsWith('assisted_shoulder_flexion')) {
    return false;
  }

  // Work In Progress: Elbow Flexion, Shoulder Rotation, and any other non-validated exercise
  if (normalized.contains('elbow_flexion') ||
      normalized.contains('shoulder_rotation') ||
      normalized.contains('elbow') ||
      normalized.contains('rotation')) {
    return true;
  }

  return true;
}

/// Standard display name for an exercise
String getExerciseDisplayName(String? exercise) {
  if (exercise == null || exercise.trim().isEmpty) return 'Exercise';
  final normalized = exercise.trim().toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

  if (normalized == 'assisted_shoulder_flexion' ||
      normalized == 'assisted_shoulder_flexion_with_bar') {
    return 'Assisted Shoulder Flexion with Bar';
  }
  if (normalized == 'elbow_flexion' ||
      normalized.contains('elbow')) {
    return 'Elbow Flexion & Extension';
  }
  if (normalized == 'shoulder_rotation' ||
      normalized.contains('rotation')) {
    return 'Shoulder Rotation';
  }
  return exercise;
}

/// Reusable "WORK IN PROGRESS" badge widget
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
          Icons.construction_rounded,
          size: compact ? 11 : 13,
          color: iconColor,
        ),
        SizedBox(width: compact ? 3 : 5),
        Text(
          'WORK IN PROGRESS',
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

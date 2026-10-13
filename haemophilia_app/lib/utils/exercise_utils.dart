import 'package:flutter/material.dart';

import 'app_localizations.dart';

// Canonical exercise identifiers - Upper Body (existing)
const String kAssistedShoulderFlexion = 'assisted_shoulder_flexion';
const String kShoulderRotation = 'shoulder_rotation';
const String kAssistedElbowFlexion = 'assisted_elbow_flexion';
const String kAssistedElbowFlexionV5 = 'assisted_elbow_flexion_v5';
const String kElbowFlexionExtension = 'elbow_flexion_extension';

// Canonical exercise identifiers - Lower Body (integrated)
const String kHeelSlide = 'heel_slide';
const String kMiniSquat = 'mini_squat';
const String kSeatedKneeExtension = 'seated_knee_extension';
const String kStraightLegRaise = 'straight_leg_raise';
const String kTerminalKneeExtension = 'terminal_knee_extension';
const String kSquat = 'squat';

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

/// Catalog of supported exercises and model variants
const List<ExerciseMetadata> kAllExercises = [
  // Upper-body exercises
  ExerciseMetadata(
    id: kAssistedShoulderFlexion,
    displayName: 'Assisted Shoulder Flexion with Bar',
    shortName: 'Shoulder Flexion',
    targetJoint: 'Shoulders',
    description: 'Two-handed bar elevation exercise targeting shoulder mobility and joint preservation.',
    icon: Icons.accessibility_new_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kShoulderRotation,
    displayName: 'Shoulder Rotation',
    shortName: 'Shoulder Rotation',
    targetJoint: 'Rotator Cuff',
    description: 'Bilateral internal and external rotation with elbows flexed 90° pinned to torso.',
    icon: Icons.rotate_right_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kAssistedElbowFlexionV5,
    displayName: 'Assisted Elbow Flexion',
    shortName: 'Assisted Elbow',
    targetJoint: 'Elbow Joint',
    description: 'Alternate left and right with opposite-hand support. Joint angles and opposite-hand support are tracked on your phone.',
    icon: Icons.pan_tool_outlined,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kElbowFlexionExtension,
    displayName: 'Elbow Flexion & Extension',
    shortName: 'Elbow Flex / Ext',
    targetJoint: 'Elbow Joint',
    description: 'Smooth, controlled elbow bending and extension throughout comfortable pain-free range.',
    icon: Icons.fitness_center_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  // Lower-body exercises
  ExerciseMetadata(
    id: kHeelSlide,
    displayName: 'Heel Slide',
    shortName: 'Heel Slide',
    targetJoint: 'Knee / Hip Joint',
    description: 'Supine knee flexion and extension sliding the heel along the surface to restore knee range of motion.',
    icon: Icons.airline_seat_legroom_extra_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kMiniSquat,
    displayName: 'Mini Squat',
    shortName: 'Mini Squat',
    targetJoint: 'Knee / Quads',
    description: 'Controlled shallow squat with knee angle, heel position, and visible knee alignment feedback.',
    icon: Icons.downhill_skiing_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kSeatedKneeExtension,
    displayName: 'Seated Knee Extension',
    shortName: 'Seated Knee Ext',
    targetJoint: 'Quadriceps / Knee',
    description: 'Seated knee extension with knee angle and visible torso movement feedback.',
    icon: Icons.event_seat_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kStraightLegRaise,
    displayName: 'Straight Leg Raise',
    shortName: 'Straight Leg Raise',
    targetJoint: 'Hip Flexors / Quads',
    description: 'Straight leg elevation with hip angle and lifting-knee position feedback.',
    icon: Icons.accessibility_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kTerminalKneeExtension,
    displayName: 'Terminal Knee Extension',
    shortName: 'Terminal Knee Ext',
    targetJoint: 'Knee / VMO',
    description: 'Supine knee extension over a bolster to isolate terminal vastus medialis obliquus extension.',
    icon: Icons.airline_seat_flat_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
  ExerciseMetadata(
    id: kSquat,
    displayName: 'Squat',
    shortName: 'Squat',
    targetJoint: 'Lower Body / Hips / Knees',
    description: 'Squat with knee angle, visible knee alignment, torso movement, and heel position feedback.',
    icon: Icons.directions_run_rounded,
    isWorkInProgress: false,
    statusLabel: 'On-device angle rules',
  ),
];

/// Normalizes an exercise name or ID while preserving model variants.
String normalizeExerciseId(String? exercise) {
  if (exercise == null || exercise.trim().isEmpty) {
    return kAssistedShoulderFlexion;
  }
  final normalized = exercise
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_');

  // Lower-body exercises
  if (normalized == 'heel_slide' ||
      normalized == 'heel_slides' ||
      normalized.contains('heel_slide')) {
    return kHeelSlide;
  }

  if (normalized == 'mini_squat' ||
      normalized == 'mini_squats' ||
      normalized.contains('mini_squat')) {
    return kMiniSquat;
  }

  if (normalized == 'seated_knee_extension' ||
      normalized == 'seated_knee_extensions' ||
      normalized == 'seated_leg_extension' ||
      normalized == 'seated_leg_extensions' ||
      (normalized.contains('seated') && normalized.contains('knee'))) {
    return kSeatedKneeExtension;
  }

  if (normalized == 'straight_leg_raise' ||
      normalized == 'straight_leg_raises' ||
      normalized == 'slr' ||
      (normalized.contains('straight') && normalized.contains('leg'))) {
    return kStraightLegRaise;
  }

  if (normalized == 'terminal_knee_extension' ||
      normalized == 'terminal_knee_extensions' ||
      normalized == 'tke' ||
      (normalized.contains('terminal') && normalized.contains('knee'))) {
    return kTerminalKneeExtension;
  }

  if (normalized == 'squat' ||
      normalized == 'squats' ||
      normalized.contains('squat')) {
    return kSquat;
  }

  // Upper-body exercises
  if (normalized == 'assisted_shoulder_flexion' ||
      normalized == 'assisted_shoulder_flexion_with_bar' ||
      normalized.startsWith('assisted_shoulder_flexion') ||
      normalized.contains('shoulder_flexion')) {
    return kAssistedShoulderFlexion;
  }

  if (normalized == 'shoulder_rotation' || normalized.contains('rotation')) {
    return kShoulderRotation;
  }

  if (normalized == kAssistedElbowFlexionV5 ||
      normalized == 'assisted_elbow_flexion_(updated_model)') {
    return kAssistedElbowFlexionV5;
  }

  if (normalized == 'assisted_elbow_flexion' ||
      normalized.contains('assisted_elbow')) {
    return kAssistedElbowFlexionV5;
  }

  if (normalized == 'elbow_flexion' ||
      normalized == 'elbow_flexion_extension' ||
      normalized.contains('elbow')) {
    return kElbowFlexionExtension;
  }

  return normalized;
}

/// Returns true if an exercise is an unlisted fallback without a demonstration.
bool isWorkInProgressExercise(String? exerciseName) {
  if (exerciseName == null || exerciseName.trim().isEmpty) return false;
  final canonical = normalizeExerciseId(exerciseName);

  if (kAllExercises.any((exercise) => exercise.id == canonical)) return false;

  // Legacy aliases remain supported.
  if (canonical == kAssistedShoulderFlexion ||
      canonical == kAssistedElbowFlexion ||
      canonical == kAssistedElbowFlexionV5 ||
      canonical == kElbowFlexionExtension) {
    return false;
  }

  if (canonical == kShoulderRotation) return false;

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
    case kAssistedElbowFlexionV5:
      return 'Assisted Elbow Flexion';
    case kAssistedElbowFlexion:
      return 'Assisted Elbow Flexion';
    case kElbowFlexionExtension:
      return 'Elbow Flexion & Extension';
    case kHeelSlide:
      return 'Heel Slide';
    case kMiniSquat:
      return 'Mini Squat';
    case kSeatedKneeExtension:
      return 'Seated Knee Extension';
    case kStraightLegRaise:
      return 'Straight Leg Raise';
    case kTerminalKneeExtension:
      return 'Terminal Knee Extension';
    case kSquat:
      return 'Squat';
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
    case kAssistedElbowFlexionV5:
    case kAssistedElbowFlexion:
      return Icons.pan_tool_outlined;
    case kElbowFlexionExtension:
      return Icons.fitness_center_rounded;
    case kHeelSlide:
      return Icons.airline_seat_legroom_extra_rounded;
    case kMiniSquat:
      return Icons.downhill_skiing_rounded;
    case kSeatedKneeExtension:
      return Icons.event_seat_rounded;
    case kStraightLegRaise:
      return Icons.accessibility_rounded;
    case kTerminalKneeExtension:
      return Icons.airline_seat_flat_rounded;
    case kSquat:
      return Icons.directions_run_rounded;
    default:
      return Icons.fitness_center_rounded;
  }
}

/// Reusable preview badge widget.
Widget buildWipBadge({bool isDark = false, bool compact = false}) {
  final backgroundColor = isDark
      ? Colors.amber.withValues(alpha: 0.18)
      : const Color(0xFFFFF3E0); // Orange shade 50
  final borderColor = isDark
      ? Colors.amberAccent.withValues(alpha: 0.65)
      : const Color(0xFFFFB74D); // Orange shade 300
  final textColor = isDark
      ? Colors.amberAccent
      : const Color(0xFFE65100); // Orange shade 900
  final iconColor = isDark ? Colors.amberAccent : const Color(0xFFE65100);

  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 8,
      vertical: compact ? 2 : 4,
    ),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: borderColor, width: 1.0),
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

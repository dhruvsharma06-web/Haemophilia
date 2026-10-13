import 'package:flutter/material.dart';

import '../utils/app_localizations.dart';

/// Optional metrics never turn missing values into zero or AI confidence.
class RepMovementStats extends StatelessWidget {
  final Map<String, dynamic> rep;
  const RepMovementStats({super.key, required this.rep});

  double? number(String key, [String? alternate]) {
    final value = rep[key] ?? rep[alternate];
    final result = value is num ? value.toDouble() : double.tryParse('$value');
    return result != null && result.isFinite ? result : null;
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final minimum = number('minimumAngle', 'minimum_angle');
    final maximum = number('maximumAngle', 'maximum_angle');
    final smoothness = number('smoothness');
    final completion = number('returnCompletion', 'return_completion');
    final speed = number('angularSpeed', 'angular_speed');
    final hand = rep['hand']?.toString();
    final components = rep['scoreComponents'] ?? rep['score_components'];
    double? component(String key) {
      final value = components is Map ? components[key] : null;
      return value is num && value.isFinite ? value.toDouble() : null;
    }

    final values = <String, String>{
      if (hand != null) 'Arm': tr(hand),
      if (minimum != null && maximum != null)
        'Angle range':
            '${minimum.toStringAsFixed(0)}°–${maximum.toStringAsFixed(0)}°',
      if (smoothness != null)
        'Smoothness': '${smoothness.toStringAsFixed(0)}/100',
      if (completion != null) 'Return': '${completion.toStringAsFixed(0)}%',
      if (speed != null) 'Angular speed': '${speed.toStringAsFixed(0)}°/s',
      for (final entry in {
        'range': 'Range score',
        'posture': 'Posture score',
        'pace': 'Pace score',
      }.entries)
        if (component(entry.key) case final value?)
          entry.value: '${value.toStringAsFixed(0)}/100',
      if (rep['targetReached'] != null || rep['target_reached'] != null)
        'Target held': tr(
          (rep['targetReached'] ?? rep['target_reached']) == true
              ? 'Yes'
              : 'No',
        ),
      if ((rep['incorrectStep'] ?? rep['incorrect_step']) != null)
        'Incorrect step': tr(
          (rep['incorrectStep'] ?? rep['incorrect_step']).toString(),
        ),
    };
    if (values.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final entry in values.entries)
              Text(
                '${tr(entry.key)}: ${entry.value}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        if (rep['scoreKind'] == 'descriptive_movement_quality' ||
            rep['score_kind'] == 'descriptive_movement_quality' ||
            rep['scoreKind'] == 'descriptive_movement_control' ||
            rep['score_kind'] == 'descriptive_movement_control')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr(
                'Movement scores describe the recorded range, posture, return, and pace. They are provisional tracking feedback.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

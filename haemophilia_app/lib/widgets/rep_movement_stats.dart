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
    final values = <String, String>{
      if (hand != null) 'Arm': tr(hand),
      if (minimum != null && maximum != null)
        'Angle range':
            '${minimum.toStringAsFixed(0)}°–${maximum.toStringAsFixed(0)}°',
      if (smoothness != null)
        'Smoothness': '${smoothness.toStringAsFixed(0)}/100',
      if (completion != null) 'Return': '${completion.toStringAsFixed(0)}%',
      if (speed != null) 'Angular speed': '${speed.toStringAsFixed(0)}°/s',
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
        if (rep['scoreKind'] == 'descriptive_movement_control' ||
            rep['score_kind'] == 'descriptive_movement_control')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr(
                'Control and smoothness describe recorded movement; they are not AI confidence or medical scores.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

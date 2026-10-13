import 'package:flutter/material.dart';

import '../services/exercise_rules.dart';
import '../utils/app_localizations.dart';

String localizedThresholds(ExerciseRule rule) {
  if (rule.relative) {
    return '${tr(rule.joint)}: ${tr('Movement from start')} ≥${rule.target.toStringAsFixed(0)}°; '
        '${tr('Return within')} ${rule.start.toStringAsFixed(0)}°.';
  }
  final restSign = rule.increasing ? '≤' : '≥';
  final targetSign = rule.increasing ? '≥' : '≤';
  return '${tr(rule.joint)}: ${tr('Start')} $restSign${rule.start.toStringAsFixed(0)}° → '
      '${tr('Target')} $targetSign${rule.target.toStringAsFixed(0)}° → '
      '${tr('Return')} $restSign${rule.start.toStringAsFixed(0)}°.';
}

class ExerciseThresholds extends StatelessWidget {
  final String exercise;
  final bool dark;
  const ExerciseThresholds({
    super.key,
    required this.exercise,
    this.dark = false,
  });
  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final rule = ExerciseRule.forExercise(exercise);
    final color = dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final restSign = rule.increasing ? '≤' : '≥';
    final targetSign = rule.increasing ? '≥' : '≤';
    final both = rule.usesBothArms ? '${tr('Both arms')}: ' : '';
    final start = rule.relative
        ? '${tr('Neutral position')}; ${tr('Return within')} ${rule.start.toStringAsFixed(0)}°'
        : '$both${tr(rule.joint)} $restSign${rule.start.toStringAsFixed(0)}°';
    final target = rule.relative
        ? '$both${tr('Movement from start')} ≥${rule.target.toStringAsFixed(0)}°'
        : '$both${tr(rule.joint)} $targetSign${rule.target.toStringAsFixed(0)}°';
    Widget step(int number, String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.teal.withValues(alpha: .15),
            child: Text(
              '$number',
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(title),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color.withValues(alpha: .85),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: dark ? .12 : .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Angle targets and stages'),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr(rule.cameraView),
            style: TextStyle(color: color.withValues(alpha: .8), fontSize: 12),
          ),
          step(1, 'Ready', '$start · ${tr('Keep still until Ready appears.')}'),
          step(2, 'Move', rule.postureGuidance.map(tr).join(' ')),
          step(
            3,
            'Target and hold',
            '$target · ${tr('Hold briefly')} (${ExerciseRule.targetHoldSeconds} s)',
          ),
          step(
            4,
            'Return to start',
            '$start · ${tr('Return within')} ${rule.returnBand.toStringAsFixed(0)}° ${tr('of your own starting angle and pause briefly.')}',
          ),
          if (rule.joint == 'Elbow angle' || rule.joint == 'Knee angle')
            Text(
              tr(
                'A straighter elbow or knee reads near 180°; bending makes the angle smaller.',
              ),
              style: TextStyle(
                color: color.withValues(alpha: .8),
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            tr(
              'A 2° tracking margin tolerates tiny camera-angle changes. The target must still be held.',
            ),
            style: TextStyle(color: color.withValues(alpha: .8), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'A brief wobble is tolerated. A sustained movement error makes the current repetition incorrect; reset and retry.',
            ),
            style: TextStyle(color: color.withValues(alpha: .8), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'These are provisional tracking settings. Follow your doctor’s comfortable range; stop if painful or bleeding.',
            ),
            style: TextStyle(color: color.withValues(alpha: .75), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

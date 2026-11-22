import 'package:flutter/material.dart';

import '../services/exercise_rules.dart';
import '../services/elbow_world_assessment.dart';
import '../services/shoulder_rotation_assessment.dart';
import '../utils/exercise_utils.dart';
import '../utils/app_localizations.dart';

String localizedThresholds(ExerciseRule rule) {
  if (rule.id == kElbowFlexionExtension ||
      rule.id == kShoulderRotation ||
      rule.id == kAssistedElbowFlexionV5) {
    if (AppLocaleService.isHindi) {
      if (rule.id == kAssistedElbowFlexionV5) {
        return 'आरामदायक शुरुआती स्थिति में स्थिर रहें। सहारे से कोहनी को दिखाए लक्ष्य '
            '(≤${rule.target.toStringAsFixed(0)}°) तक मोड़ें और फिर अपने शुरुआती कोण से '
            '${rule.returnBand.toStringAsFixed(0)}° के भीतर वापस लाएं।';
      }
      if (rule.id == kShoulderRotation) {
        return 'कोहनियां 60–120° के बीच मोड़कर शुरुआती स्थिति में स्थिर रहें। दोनों अग्रबाहुओं को '
            '${ShoulderRotationAssessment.extremeDegrees.toStringAsFixed(0)}° तक साथ हिलाएं '
            'और ${ShoulderRotationAssessment.extremeHoldSeconds} सेकंड रुकें। फिर शुरुआत से '
            '${ShoulderRotationAssessment.appReturnBandDegrees.toStringAsFixed(0)}° के भीतर लौटें '
            'और ${ShoulderRotationAssessment.appReturnHoldSeconds} सेकंड रुकें। '
            'गति और वापसी से एक दोहराव पूरा होता है। कैमरे के माप अनुमान हैं।';
      }
      return 'दोनों बांहों के लक्ष्य अलग हैं। बाईं: शुरुआत ≥${ElbowWorldAssessment.leftExtensionMin.toStringAsFixed(2)}°, '
          'मोड़ ≤${ElbowWorldAssessment.leftFlexionMax.toStringAsFixed(2)}°, '
          'गति की सीमा ≥${ElbowWorldAssessment.leftRomMin.toStringAsFixed(2)}°। '
          'दाईं: शुरुआत ≥${ElbowWorldAssessment.rightExtensionMin.toStringAsFixed(2)}°, '
          'मोड़ ≤${ElbowWorldAssessment.rightFlexionMax.toStringAsFixed(2)}°, '
          'गति की सीमा ≥${ElbowWorldAssessment.rightRomMin.toStringAsFixed(2)}°। '
          'लक्ष्य और वापसी पर ${ElbowWorldAssessment.targetHoldSeconds} सेकंड रुकें। '
          'वापसी बाईं ओर ${ElbowWorldAssessment.leftReturnErrorMax.toStringAsFixed(2)}° और '
          'दाईं ओर ${ElbowWorldAssessment.rightReturnErrorMax.toStringAsFixed(2)}° के भीतर हो।';
    }
    return rule.thresholdSummary;
  }
  final both = rule.usesBothArms ? '${tr('Both arms')}: ' : '';
  if (rule.relative) {
    return '$both${tr(rule.joint)}: ${tr('Movement from start')} ≥${rule.target.toStringAsFixed(0)}°; '
        '${tr('Return within')} ${rule.returnBand.toStringAsFixed(0)}°.';
  }
  final restSign = rule.increasing ? '≤' : '≥';
  final targetSign = rule.increasing ? '≥' : '≤';
  return '$both${tr(rule.joint)}: ${tr('Start')} $restSign${rule.start.toStringAsFixed(0)}° → '
      '${tr('Target')} $targetSign${rule.target.toStringAsFixed(0)}° → '
      '${tr('Return')} $restSign${rule.start.toStringAsFixed(0)}°.';
}

class ExerciseThresholds extends StatelessWidget {
  final String exercise;
  final bool dark;
  final bool compact;
  final ExerciseRule? ruleOverride;
  const ExerciseThresholds({
    super.key,
    required this.exercise,
    this.dark = false,
    this.compact = false,
    this.ruleOverride,
  });
  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final standard = ExerciseRule.forExercise(exercise);
    final rule = ruleOverride?.id == standard.id ? ruleOverride! : standard;
    final color = dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    if (rule.id == kElbowFlexionExtension) {
      return Container(
        padding: EdgeInsets.all(compact ? 10 : 14),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: dark ? .12 : .06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Angle targets and stages'),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              localizedThresholds(rule),
              style: TextStyle(color: color, fontSize: compact ? 11.5 : 12.5),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Camera measurements are estimates. Follow your prescribed comfortable range; stop if painful.',
              ),
              style: TextStyle(
                color: color.withValues(alpha: .75),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    if (rule.id == kShoulderRotation) {
      return Container(
        padding: EdgeInsets.all(compact ? 10 : 14),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: dark ? .12 : .06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Angle targets and stages'),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              localizedThresholds(rule),
              style: TextStyle(color: color, fontSize: compact ? 11.5 : 12.5),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Camera measurements are estimates. Follow your prescribed comfortable range; stop if painful.',
              ),
              style: TextStyle(
                color: color.withValues(alpha: .75),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizedThresholds(rule),
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${tr('Hold briefly')} (${ExerciseRule.targetHoldSeconds} s) · ${tr('Return within')} ${rule.returnBand.toStringAsFixed(0)}° · ${tr('Tracking margin')} ±${ExerciseRule.angleMargin.toStringAsFixed(0)}°',
              style: TextStyle(
                color: color.withValues(alpha: .75),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      );
    }
    final restSign = rule.increasing ? '≤' : '≥';
    final targetSign = rule.increasing ? '≥' : '≤';
    final both = rule.usesBothArms ? '${tr('Both arms')}: ' : '';
    final start = rule.id == kAssistedElbowFlexionV5
        ? tr('Your comfortable, steady starting position')
        : rule.relative
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

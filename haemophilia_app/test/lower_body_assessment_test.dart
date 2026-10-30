import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/lower_body_assessment.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';

/// Normalized ML Kit landmarks backed by a 1000 x 1000 synthetic image.
/// The active leg uses two equal 200 px segments, so its measured joint angle
/// follows [degrees]. The second leg remains visible to exercise leg selection.
List<Map<String, dynamic>> _pose(String exercise, double degrees) {
  final points = List.generate(
    33,
    (_) => <String, dynamic>{'x': .5, 'y': .5, 'z': 0.0, 'visibility': .1},
  );
  void put(int index, double x, double y, {double z = 0}) {
    points[index] = <String, dynamic>{
      'x': x / 1000,
      'y': y / 1000,
      'z': z / 1000,
      'visibility': .99,
    };
  }

  final radians = degrees * math.pi / 180;
  put(0, 350, 200);
  put(7, 350, 250);
  put(11, 350, 350);
  put(12, 650, 350, z: 200); // A side view for squat-specific form checks.
  put(23, 350, 500);
  put(24, 650, 500);
  put(25, 500, 500);
  put(26, 650, 650);
  put(27, 500 - 200 * math.cos(radians), 500 + 200 * math.sin(radians));
  put(28, 650, 850);
  put(29, 500 - 200 * math.cos(radians), 510 + 200 * math.sin(radians));
  put(30, 650, 860);

  if (exercise == kSeatedKneeExtension) {
    // The seated upright-head cue compares the nose with shoulder centre.
    put(0, 500, 200);
  }

  if (exercise == kHeelSlide) {
    // A supine leg with the heel sliding on a fixed-height surface. The
    // hip-to-heel distance shrinks as the knee bends while both stay planted.
    const thigh = 200.0;
    final hipToHeel = 2 * thigh * math.sin(radians / 2);
    final half = hipToHeel / 2;
    final kneeDrop = math.sqrt(thigh * thigh - half * half);
    put(11, 250, 350);
    put(23, 250, 500);
    put(25, 250 + half, 500 + kneeDrop);
    put(27, 250 + hipToHeel, 500);
    put(29, 250 + hipToHeel, 510);
  } else if (exercise == kStraightLegRaise) {
    // Hip flexion changes while the knee and ankle remain collinear.
    final raise = (180 - degrees) * math.pi / 180;
    final dx = 200 * math.cos(raise);
    final dy = -200 * math.sin(raise);
    put(0, 100, 500);
    put(11, 150, 500);
    put(23, 350, 500);
    put(25, 350 + dx, 500 + dy);
    put(27, 350 + 2 * dx, 500 + 2 * dy);
  } else if (exercise == kMiniSquat || exercise == kSquat) {
    // The feet stay on the floor and the hips descend as the knees bend.
    final kneeX = 650 - 200 * math.sin(radians);
    final kneeY = 700 + 200 * math.cos(radians);
    final hipY = kneeY - 200;
    put(0, kneeX, hipY - 220);
    put(7, kneeX, hipY - 220);
    put(11, kneeX, hipY - 150);
    put(12, kneeX + 100, hipY - 150, z: 200);
    put(23, kneeX, hipY);
    put(24, kneeX + 100, hipY);
    put(25, kneeX, kneeY);
    put(26, kneeX + 100, kneeY);
    put(27, 650, 700);
    put(28, 750, 700);
    put(29, 650, 710);
    put(30, 750, 710);
  }
  return points;
}

List<Map<String, dynamic>> _cycle(
  LowerBodyAssessment assessment,
  String exercise,
  double rest,
  double peak, {
  double startTime = 0,
}) {
  final angles = <double>[
    ...List.filled(8, rest),
    for (var i = 1; i <= 16; i++) rest + (peak - rest) * i / 16,
    ...List.filled(6, peak),
    for (var i = 1; i <= 16; i++) peak + (rest - peak) * i / 16,
    ...List.filled(8, rest),
  ];
  final completed = <Map<String, dynamic>>[];
  for (var i = 0; i < angles.length; i++) {
    final state = assessment.update(
      _pose(exercise, angles[i]),
      1000,
      1000,
      startTime + i * .08,
    );
    final rep = state['completed_rep'];
    if (rep is Map<String, dynamic>) completed.add(rep);
  }
  return completed;
}

void main() {
  const profiles =
      <
        ({
          String id,
          double rest,
          double peak,
          double shallow,
          double enter,
          double exit,
          double target,
        })
      >[
        (
          id: kHeelSlide,
          rest: 178,
          peak: 88,
          shallow: 120,
          enter: 150,
          exit: 170,
          target: 90,
        ),
        (
          id: kMiniSquat,
          rest: 178,
          peak: 130,
          shallow: 140,
          enter: 150,
          exit: 165,
          target: 130,
        ),
        (
          id: kSeatedKneeExtension,
          rest: 85,
          peak: 165,
          shallow: 125,
          enter: 100,
          exit: 95,
          target: 160,
        ),
        (
          id: kStraightLegRaise,
          rest: 178,
          peak: 140,
          shallow: 155,
          enter: 165,
          exit: 172,
          target: 140,
        ),
        (
          id: kTerminalKneeExtension,
          rest: 140,
          peak: 175,
          shallow: 160,
          enter: 155,
          exit: 145,
          target: 170,
        ),
        // The source squat's 105-degree entry follows its 120-degree target.
        // The adapter uses 145 degrees to begin assessment before target depth.
        (
          id: kSquat,
          rest: 175,
          peak: 120,
          shallow: 135,
          enter: 145,
          exit: 155,
          target: 120,
        ),
      ];

  for (final profile in profiles) {
    test('${profile.id}: clean held target uses source threshold profile', () {
      final assessment = LowerBodyAssessment(profile.id);
      final reps = _cycle(assessment, profile.id, profile.rest, profile.peak);
      expect(reps, hasLength(1));
      final rep = reps.single;
      expect(rep['form'], 'correct', reason: '${rep['feedback_details']}');
      expect(rep['target_reached'], true);
      expect(rep['hand'], 'Left');
      expect(rep['assessment_method'], 'on_device_angle_rules');
      expect(rep['score_kind'], 'rule_heuristic_not_accuracy');
      expect(rep['clinically_validated'], false);
      expect(assessment.repCount, 1);
      expect(assessment.correctCount, 1);
      final thresholds = rep['thresholds'] as Map<String, dynamic>;
      expect(thresholds['source'], 'backend/app/config/exercises.json');
      expect(thresholds['enter'], profile.enter);
      expect(thresholds['exit'], profile.exit);
      expect(thresholds['depthTarget'], profile.target);
      expect(rep['required_target'], profile.target);
      expect(thresholds['angleMargin'], 2.0);
      if (profile.id == kMiniSquat) {
        expect(thresholds['localExcessDepthLimit'], 120.0);
      }
    });

    test('${profile.id}: movement short of target is an incorrect rep', () {
      final assessment = LowerBodyAssessment(profile.id);
      final reps = _cycle(
        assessment,
        profile.id,
        profile.rest,
        profile.shallow,
      );
      expect(reps, hasLength(1));
      final rep = reps.single;
      expect(rep['form'], 'incorrect');
      expect(rep['target_reached'], false);
      expect(
        rep['error_codes'],
        contains(anyOf('INSUFFICIENT_DEPTH', 'SLIDE_INSUFFICIENT')),
      );
      final codes = (rep['error_codes'] as List).cast<String>();
      expect(codes.length, codes.toSet().length);
      expect(assessment.repCount, 1);
      expect(assessment.correctCount, 0);
    });
  }

  test('mini squat below the local depth limit is incorrect', () {
    final assessment = LowerBodyAssessment(kMiniSquat);
    final rep = _cycle(assessment, kMiniSquat, 178, 110).single;
    expect(rep['target_reached'], true);
    expect(rep['form'], 'incorrect');
    expect(rep['error_codes'], contains('SQUAT_TOO_DEEP'));
  });

  test('a long tracking gap discards an active movement', () {
    final assessment = LowerBodyAssessment(kHeelSlide);
    for (var i = 0; i < 8; i++) {
      assessment.update(_pose(kHeelSlide, 178), 1000, 1000, i * .08);
    }
    for (var i = 8; i < 16; i++) {
      assessment.update(_pose(kHeelSlide, 88), 1000, 1000, i * .08);
    }
    final afterGap = assessment.update(_pose(kHeelSlide, 178), 1000, 1000, 2.1);
    expect(afterGap['completed_rep'], isNull);
    expect(assessment.repCount, 0);
    expect(_cycle(assessment, kHeelSlide, 178, 88, startTime: 3), hasLength(1));
    expect(assessment.repCount, 1);
  });

  test('an obscured required knee discards an active movement', () {
    final assessment = LowerBodyAssessment(kStraightLegRaise);
    for (var i = 0; i < 8; i++) {
      assessment.update(_pose(kStraightLegRaise, 178), 1000, 1000, i * .08);
    }
    for (var i = 8; i < 16; i++) {
      assessment.update(_pose(kStraightLegRaise, 140), 1000, 1000, i * .08);
    }
    final obscured = _pose(kStraightLegRaise, 140);
    obscured[25]['visibility'] = .1;
    final lost = assessment.update(obscured, 1000, 1000, 1.28);
    expect(lost['tracking_valid'], false);
    expect(lost['landmarks'], hasLength(33));
    expect(assessment.repCount, 0);
    expect(
      _cycle(assessment, kStraightLegRaise, 178, 140, startTime: 2),
      hasLength(1),
    );
  });
}

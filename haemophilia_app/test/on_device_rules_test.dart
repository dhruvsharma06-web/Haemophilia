import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/utils/wireframe_style.dart';

List<Map<String, dynamic>> pose(
  String id,
  double degrees, {
  String hand = 'Left',
  bool support = true,
  double? rightDegrees,
  bool rightLeg = false,
}) {
  final p = List.generate(
    33,
    (_) => <String, dynamic>{'x': .5, 'y': .2, 'z': 0.0, 'visibility': .99},
  );
  void put(int i, double x, double y, [double z = 0]) {
    p[i] = {'x': x / 1000, 'y': y / 1000, 'z': z / 1000, 'visibility': .99};
  }

  put(11, 350, 150);
  put(12, 650, 150);
  put(23, 350, 500);
  put(24, 650, 500);
  put(13, 350, 350);
  put(14, 650, 350);
  put(15, 350, 550);
  put(16, 650, 550);
  put(25, 350, 650);
  put(26, 650, 650);
  put(27, 350, 850);
  put(28, 650, 850);
  put(29, 350, 860);
  put(30, 650, 860);
  final a = degrees * math.pi / 180;
  if (id == kAssistedShoulderFlexion) {
    put(13, 350 - 200 * math.sin(a), 150 + 200 * math.cos(a));
    put(14, 650 + 200 * math.sin(a), 150 + 200 * math.cos(a));
    put(15, 350 - 250 * math.sin(a), 150 + 250 * math.cos(a));
    put(16, 650 + 250 * math.sin(a), 150 + 250 * math.cos(a));
    for (final i in [11, 12, 13, 14, 15, 16, 23, 24]) {
      p[i]['y'] = (p[i]['y'] as double) + .35;
    }
  } else if (id == kShoulderRotation) {
    put(15, 350 - 100 * math.sin(a), 350, -100 * math.cos(a));
    put(16, 650 + 100 * math.sin(a), 350, -100 * math.cos(a));
  } else if (id == kAssistedElbowFlexionV5 || id == kElbowFlexionExtension) {
    if (id == kElbowFlexionExtension) {
      for (final right in [false, true]) {
        final x = right ? 650.0 : 350.0;
        final theta =
            (right ? rightDegrees ?? degrees : degrees) * math.pi / 180;
        put(right ? 14 : 13, x, 350);
        put(
          right ? 16 : 15,
          x + (right ? 1 : -1) * 130 * math.sin(theta),
          350 - 130 * math.cos(theta),
        );
      }
      return p;
    }
    final right = id == kElbowFlexionExtension || hand == 'Right';
    final x = right ? 650.0 : 350.0,
        elbow = right ? 14 : 13,
        wrist = right ? 16 : 15;
    put(elbow, x, 350);
    put(wrist, x + 130 * math.sin(a), 350 - 130 * math.cos(a));
    if (id == kAssistedElbowFlexionV5 && support) {
      put(
        right ? 15 : 16,
        (x + (p[wrist]['x'] as double) * 1000) / 2,
        (350 + (p[wrist]['y'] as double) * 1000) / 2,
      );
    }
  } else if (id == kStraightLegRaise) {
    put(11, 100, 500);
    put(23, 350, 500);
    final r = (180 - degrees) * math.pi / 180;
    put(25, 350 + 220 * math.cos(r), 500 - 220 * math.sin(r));
    put(27, 350 + 440 * math.cos(r), 500 - 440 * math.sin(r));
  } else {
    put(11, 300, 150);
    put(23, 300, 350);
    put(25, 500, 350);
    put(27, 500 - 200 * math.cos(a), 350 + 200 * math.sin(a));
    put(29, 700, 600);
  }
  if (rightLeg) {
    for (final i in [11, 23, 25, 27, 29, 31]) {
      p[i + 1] = {...p[i], 'x': 1 - (p[i]['x'] as double)};
      p[i]['visibility'] = .1;
    }
  }
  return p;
}

List<Map<String, dynamic>> cycle(
  ExerciseRulesAssessment e,
  String id,
  double rest,
  double peak, {
  double time = 0,
  String hand = 'Left',
  bool support = true,
  bool rightLeg = false,
}) {
  final reps = <Map<String, dynamic>>[];
  final values = [
    ...List.filled(8, rest),
    for (var i = 1; i <= 16; i++) rest + (peak - rest) * i / 16,
    ...List.filled(5, peak),
    for (var i = 1; i <= 16; i++) peak + (rest - peak) * i / 16,
    ...List.filled(8, rest),
  ];
  var frameIndex = 0;
  for (final v in values) {
    final s = e.updateWithWorldFixture(
      pose(
        id,
        v,
        hand: hand,
        support: support || frameIndex < 8,
        rightLeg: rightLeg,
      ),
      1000,
      1000,
      time,
    );
    if (s['completed_rep'] is Map) {
      reps.add(Map<String, dynamic>.from(s['completed_rep'] as Map));
    }
    time += .08;
    frameIndex++;
  }
  return reps;
}

extension WorldPoseFixture on ExerciseRulesAssessment {
  Map<String, dynamic> updateWithWorldFixture(
    List<Map<String, dynamic>> landmarks,
    double width,
    double height,
    double time,
  ) => update(
    landmarks,
    width,
    height,
    time,
    worldLandmarks: rule.id == kElbowFlexionExtension ? landmarks : null,
    angleSource: rule.id == kElbowFlexionExtension
        ? 'pose_world_landmarks'
        : null,
  );
}

void main() {
  for (final item in <(String, double, double)>[
    (kAssistedShoulderFlexion, 20, 160),
    (kShoulderRotation, 0, 40),
    (kAssistedElbowFlexionV5, 150, 80),
    (kElbowFlexionExtension, 160, 65),
    (kHeelSlide, 178, 80),
    (kMiniSquat, 178, 125),
    (kSeatedKneeExtension, 85, 170),
    (kStraightLegRaise, 178, 130),
    (kTerminalKneeExtension, 140, 178),
    (kSquat, 175, 95),
  ]) {
    test('${item.$1}: one complete movement produces one rule result', () {
      final e = ExerciseRulesAssessment(item.$1);
      final reps = cycle(e, item.$1, item.$2, item.$3);
      expect(reps, hasLength(1));
      expect(reps.single['form'], 'correct');
      expect(reps.single['duration'], greaterThan(.8));
      expect(reps.single['range_of_motion'], greaterThanOrEqualTo(15));
      expect(reps.single.containsKey('confidence'), false);
    });
    test('${item.$1}: valid ready and movement use a green wireframe', () {
      final e = ExerciseRulesAssessment(item.$1);
      Map<String, dynamic>? state;
      for (var i = 0; i < 8; i++) {
        state = e.updateWithWorldFixture(pose(item.$1, item.$2), 1000, 1000, i * .08);
      }
      expect(state!['state'], 'READY');
      expect(wireframeColor(state['form']), Colors.greenAccent);
      for (var i = 1; i <= 12; i++) {
        state = e.updateWithWorldFixture(
          pose(item.$1, item.$2 + (item.$3 - item.$2) * i / 16),
          1000,
          1000,
          .64 + i * .08,
        );
      }
      expect(wireframeColor(state!['form']), Colors.greenAccent);
    });
    if (!ExerciseRule.forExercise(item.$1).isUpperBody) {
      test('${item.$1}: visible right leg can complete a repetition', () {
        final e = ExerciseRulesAssessment(item.$1);
        final reps = cycle(e, item.$1, item.$2, item.$3, rightLeg: true);
        expect(reps, hasLength(1));
        expect(reps.single['form'], 'correct');
        expect(reps.single['hand'], 'Right');
      });
    }
  }
  test('overly deep mini squat is incorrect despite reaching its target', () {
    final e = ExerciseRulesAssessment(kMiniSquat);
    final r = cycle(e, kMiniSquat, 178, 110).single;
    expect(r['form'], 'incorrect');
    expect(r['error_codes'], contains('SQUAT_TOO_DEEP'));
    expect(r['target_reached'], true);
    expect(r['score'], lessThanOrEqualTo(55));
  });
  test('the source mini squat target is accepted at 130 degrees', () {
    final e = ExerciseRulesAssessment(kMiniSquat);
    expect(cycle(e, kMiniSquat, 178, 130).single['form'], 'correct');
  });
  test(
    'bilateral extension above both candidate thresholds completes',
    () {
      final e = ExerciseRulesAssessment(kElbowFlexionExtension);
      expect(
        cycle(e, kElbowFlexionExtension, 155, 65).single['form'],
        'correct',
      );
    },
  );
  for (final item in [
    (kHeelSlide, 178.0, 80.0),
    (kSeatedKneeExtension, 85.0, 175.0),
    (kStraightLegRaise, 178.0, 130.0),
    (kTerminalKneeExtension, 140.0, 178.0),
  ]) {
    test(
      '${item.$1}: movement selects the right leg when both are visible',
      () {
        final e = ExerciseRulesAssessment(item.$1);
        final values = [
          ...List.filled(8, item.$2),
          for (var i = 1; i <= 16; i++) item.$2 + (item.$3 - item.$2) * i / 16,
          ...List.filled(8, item.$3),
          for (var i = 1; i <= 16; i++) item.$3 + (item.$2 - item.$3) * i / 16,
          ...List.filled(10, item.$2),
        ];
        final reps = <Map>[];
        for (var i = 0; i < values.length; i++) {
          final p = pose(item.$1, item.$2);
          final moving = pose(item.$1, values[i]);
          for (final j in [11, 23, 25, 27, 29, 31]) {
            p[j + 1] = {...moving[j], 'x': 1 - (moving[j]['x'] as double)};
          }
          final state = e.updateWithWorldFixture(p, 1000, 1000, i * .08);
          if (state['completed_rep'] is Map) reps.add(state['completed_rep']);
        }
        expect(reps, hasLength(1));
        expect(reps.single['hand'], 'Right');
        expect(reps.single['form'], 'correct');
      },
    );
  }
  test('bilateral return must reach each arm’s own starting angle', () {
    final e = ExerciseRulesAssessment(kElbowFlexionExtension);
    final values = [
      ...List.filled(8, 175.0),
      for (var i = 1; i <= 16; i++) 175.0 - 110 * i / 16,
      ...List.filled(6, 65.0),
      for (var i = 1; i <= 16; i++) 65.0 + 100 * i / 16,
      ...List.filled(40, 165.0),
    ];
    Map<String, dynamic>? rep;
    for (var i = 0; i < values.length; i++) {
      final returning = i >= 30;
      final s = e.updateWithWorldFixture(
        pose(
          kElbowFlexionExtension,
          values[i],
          rightDegrees: returning ? math.min(175, values[i] + 10) : null,
        ),
        1000,
        1000,
        i * .08,
      );
      if (s['completed_rep'] is Map) {
        rep = Map<String, dynamic>.from(s['completed_rep'] as Map);
      }
    }
    expect(e.repCount, 1);
    expect(e.correctCount, 0);
    // The left arm settles at 165, which clears its extension floor but sits
    // 10 deg from its own 175 deg start, beyond the 7.76 deg return limit. The
    // completed repetition is therefore incorrect; the live state has already
    // reset to POSITIONING by the end of the trailing frames.
    expect(rep, isNotNull);
    expect(rep!['form'], 'incorrect');
    expect(rep['error_codes'], contains('LEFT_INCOMPLETE_RETURN'));
  });
  test('all exercises reject a completed shallow movement', () {
    for (final rule in ExerciseRule.catalog) {
      final rest = rule.relative ? 0.0 : rule.start;
      final peak = rule.increasing ? rest + 12 : rest - 12;
      final e = ExerciseRulesAssessment(rule.id);
      final r = cycle(e, rule.id, rest, peak);
      expect(r, hasLength(1), reason: rule.id);
      expect(r.single['form'], 'incorrect', reason: rule.id);
      expect(e.correctCount, 0, reason: rule.id);
      expect(r.single['score'], lessThanOrEqualTo(50), reason: rule.id);
    }
  });
  test(
    'partial skeleton remains visible while a required joint is missing',
    () {
      final e = ExerciseRulesAssessment(kStraightLegRaise);
      final p = pose(kStraightLegRaise, 178);
      p[25]['visibility'] = .1;
      p[26]['visibility'] = .1;
      final s = e.updateWithWorldFixture(p, 1000, 1000, 0);
      expect(s['tracking_valid'], false);
      expect(s['landmarks'], hasLength(33));
      expect(wireframeColor(s['form']), Colors.blueGrey.shade300);
    },
  );
  test('incomplete cycles and noise cannot count', () {
    final e = ExerciseRulesAssessment(kHeelSlide);
    for (var i = 0; i < 100; i++) {
      e.updateWithWorldFixture(pose(kHeelSlide, 177 + (i % 2)), 1000, 1000, i * .08);
    }
    for (var i = 100; i < 120; i++) {
      e.updateWithWorldFixture(pose(kHeelSlide, 80), 1000, 1000, i * .08);
    }
    expect(e.repCount, 0);
  });
  test('tracking loss discards a partial repetition', () {
    final e = ExerciseRulesAssessment(kHeelSlide);
    for (var i = 0; i < 8; i++) {
      e.updateWithWorldFixture(pose(kHeelSlide, 178), 1000, 1000, i * .08);
    }
    for (var i = 8; i < 18; i++) {
      e.updateWithWorldFixture(pose(kHeelSlide, 80), 1000, 1000, i * .08);
    }
    final p = pose(kHeelSlide, 80);
    p[25]['visibility'] = .1;
    e.updateWithWorldFixture(p, 1000, 1000, 1.5);
    for (var i = 20; i < 30; i++) {
      e.updateWithWorldFixture(pose(kHeelSlide, 178), 1000, 1000, i * .08);
    }
    expect(e.repCount, 0);
    expect(cycle(e, kHeelSlide, 178, 80, time: 3), hasLength(1));
  });
  test('assisted elbow alternates only after supported accepted cycles', () {
    final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5);
    expect(
      cycle(e, kAssistedElbowFlexionV5, 150, 80).single['form'],
      'correct',
    );
    expect(e.hand, 'Right');
    expect(
      cycle(
        e,
        kAssistedElbowFlexionV5,
        150,
        80,
        time: 5,
        hand: 'Right',
        support: false,
      ).single['form'],
      'incorrect',
    );
    expect(e.hand, 'Right');
    expect(
      cycle(
        e,
        kAssistedElbowFlexionV5,
        150,
        80,
        time: 10,
        hand: 'Right',
      ).single['form'],
      'correct',
    );
    expect(e.hand, 'Left');
  });
  test('shallow range produces an incorrect completed repetition', () {
    final e = ExerciseRulesAssessment(kHeelSlide);
    final r = cycle(e, kHeelSlide, 178, 130).single;
    expect(r['form'], 'incorrect');
    expect(e.correctCount, 0);
    expect(r['error_codes'], contains('TARGET_NOT_HELD'));
    expect(r['score'], lessThanOrEqualTo(50));
  });
  test('degenerate joints and long gaps cannot bridge a cycle', () {
    expect(ExerciseRulesAssessment.angle([0, 0], [0, 0], [1, 1]), isNull);
    final e = ExerciseRulesAssessment(kHeelSlide);
    for (var i = 0; i < 8; i++) {
      e.updateWithWorldFixture(pose(kHeelSlide, 178), 1000, 1000, i * .08);
    }
    e.updateWithWorldFixture(pose(kHeelSlide, 80), 1000, 1000, .8);
    e.updateWithWorldFixture(pose(kHeelSlide, 80), 1000, 1000, 1);
    e.updateWithWorldFixture(pose(kHeelSlide, 178), 1000, 1000, 10);
    expect(e.repCount, 0);
  });
  test(
    'bilateral elbow rejects one moving arm after a valid ready position',
    () {
      final e = ExerciseRulesAssessment(kElbowFlexionExtension);
      final reps = <Map<String, dynamic>>[];
      final values = [
        ...List.filled(8, 160.0),
        for (var i = 1; i <= 16; i++) 160.0 - 80 * i / 16,
        ...List.filled(6, 80.0),
        for (var i = 1; i <= 16; i++) 80.0 + 80 * i / 16,
        ...List.filled(10, 160.0),
      ];
      for (var i = 0; i < values.length; i++) {
        final s = e.updateWithWorldFixture(
          pose(kElbowFlexionExtension, values[i], rightDegrees: 160),
          1000,
          1000,
          i * .08,
        );
        if (s['completed_rep'] is Map) {
          reps.add(Map<String, dynamic>.from(s['completed_rep']));
        }
      }
      expect(reps, hasLength(1));
      expect(reps.single['form'], 'incorrect');
      expect(reps.single['score'], lessThanOrEqualTo(50));
      expect(e.correctCount, 0);
    },
  );
  test('one-frame target spike is not accepted as a held target', () {
    final e = ExerciseRulesAssessment(kAssistedShoulderFlexion);
    final values = [
      ...List.filled(8, 20.0),
      for (var i = 1; i <= 16; i++) 20.0 + 125 * i / 16,
      165.0,
      145.0,
      for (var i = 1; i <= 16; i++) 145.0 - 125 * i / 16,
      ...List.filled(10, 20.0),
    ];
    Map<String, dynamic>? rep;
    for (var i = 0; i < values.length; i++) {
      final s = e.updateWithWorldFixture(
        pose(kAssistedShoulderFlexion, values[i]),
        1000,
        1000,
        i * .08,
      );
      if (s['completed_rep'] is Map) {
        rep = Map<String, dynamic>.from(s['completed_rep']);
      }
    }
    expect(rep, isNotNull);
    expect(rep!['target_reached'], false);
    expect(rep['form'], 'incorrect');
    expect(rep['score'], lessThanOrEqualTo(50));
  });
  test('sustained error stays incorrect after posture is corrected', () {
    final e = ExerciseRulesAssessment(kAssistedShoulderFlexion);
    var t = 0.0;
    for (var i = 0; i < 8; i++, t += .08) {
      e.updateWithWorldFixture(pose(kAssistedShoulderFlexion, 20), 1000, 1000, t);
    }
    for (var i = 1; i <= 16; i++, t += .08) {
      final p = pose(kAssistedShoulderFlexion, 20 + 140 * i / 16);
      if (i >= 4 && i <= 10) {
        for (final j in [11, 12, 13, 14, 15, 16]) {
          p[j]['x'] = (p[j]['x'] as double) + .08;
        }
      }
      final s = e.updateWithWorldFixture(p, 1000, 1000, t);
      if (i == 16) {
        expect(s['form'], 'incorrect');
        expect(s['feedback'], 'Keep your torso steady.');
        expect(s['incorrect_step'], 'RAISING');
      }
    }
  });
  test('brief posture wobble does not mark a repetition incorrect', () {
    final e = ExerciseRulesAssessment(kAssistedShoulderFlexion);
    final values = [
      ...List.filled(8, 20.0),
      for (var i = 1; i <= 16; i++) 20.0 + 140 * i / 16,
      ...List.filled(6, 160.0),
      for (var i = 1; i <= 16; i++) 160.0 - 140 * i / 16,
      ...List.filled(10, 20.0),
    ];
    Map<String, dynamic>? rep;
    for (var i = 0; i < values.length; i++) {
      final p = pose(kAssistedShoulderFlexion, values[i]);
      if (i == 16) {
        for (final j in [11, 12, 13, 14, 15, 16]) {
          p[j]['x'] = (p[j]['x'] as double) + .08;
        }
      }
      final s = e.updateWithWorldFixture(p, 1000, 1000, i * .08);
      if (s['completed_rep'] is Map) {
        rep = Map<String, dynamic>.from(s['completed_rep']);
      }
    }
    expect(rep, isNotNull);
    expect(rep!['form'], 'correct');
    expect(rep['score'], greaterThan(80));
  });
  test(
    'partial return does not complete a rep and is flagged when stalled',
    () {
      final e = ExerciseRulesAssessment(kAssistedShoulderFlexion);
      final values = [
        ...List.filled(8, 20.0),
        for (var i = 1; i <= 16; i++) 20.0 + 140 * i / 16,
        ...List.filled(6, 160.0),
        for (var i = 1; i <= 16; i++) 160.0 - 110 * i / 16,
        ...List.filled(40, 50.0),
      ];
      Map<String, dynamic>? state;
      for (var i = 0; i < values.length; i++) {
        state = e.updateWithWorldFixture(
          pose(kAssistedShoulderFlexion, values[i]),
          1000,
          1000,
          i * .08,
        );
      }
      expect(e.repCount, 0);
      expect(state!['form'], 'incorrect');
      expect(state['error_type'], 'INCOMPLETE_RETURN');
    },
  );
  test('small shoulder rotation requires a close return to neutral', () {
    final e = ExerciseRulesAssessment(kShoulderRotation);
    final values = [
      ...List.filled(8, 0.0),
      for (var i = 1; i <= 16; i++) 40.0 * i / 16,
      ...List.filled(6, 40.0),
      for (var i = 1; i <= 16; i++) 40.0 - 34 * i / 16,
      ...List.filled(40, 6.0),
    ];
    Map<String, dynamic>? state;
    for (var i = 0; i < values.length; i++) {
      state = e.updateWithWorldFixture(pose(kShoulderRotation, values[i]), 1000, 1000, i * .08);
    }
    expect(e.repCount, 0);
    expect(state!['error_type'], 'INCOMPLETE_RETURN');
  });
  test('inward rotation cannot receive an outward-rotation correct score', () {
    final e = ExerciseRulesAssessment(kShoulderRotation);
    final rep = cycle(e, kShoulderRotation, 0, -40).single;
    expect(rep['form'], 'incorrect');
    expect(rep['error_codes'], contains('ROTATION_DIRECTION'));
    expect(rep['target_reached'], false);
    expect(rep['score'], lessThanOrEqualTo(50));
  });
  test('outward rotation remains correct with mirrored camera coordinates', () {
    final e = ExerciseRulesAssessment(kShoulderRotation);
    final values = [
      ...List.filled(8, 0.0),
      for (var i = 1; i <= 16; i++) 40.0 * i / 16,
      ...List.filled(8, 40.0),
      for (var i = 1; i <= 16; i++) 40.0 - 40.0 * i / 16,
      ...List.filled(10, 0.0),
    ];
    Map<String, dynamic>? rep;
    for (var i = 0; i < values.length; i++) {
      final p = pose(kShoulderRotation, values[i]);
      for (final joint in p) {
        joint['x'] = 1 - (joint['x'] as double);
      }
      final state = e.updateWithWorldFixture(p, 1000, 1000, i * .08);
      if (state['completed_rep'] is Map) {
        rep = Map<String, dynamic>.from(state['completed_rep']);
      }
    }
    expect(rep, isNotNull);
    expect(rep!['form'], 'correct');
  });
}

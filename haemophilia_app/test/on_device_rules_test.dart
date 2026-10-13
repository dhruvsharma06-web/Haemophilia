import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';

List<Map<String, dynamic>> pose(
  String id,
  double degrees, {
  String hand = 'Left',
  bool support = true,
  double? rightDegrees,
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
    final s = e.update(
      pose(id, v, hand: hand, support: support || frameIndex < 8),
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

void main() {
  for (final item in <(String, double, double)>[
    (kAssistedShoulderFlexion, 20, 160),
    (kShoulderRotation, 0, 40),
    (kAssistedElbowFlexionV5, 150, 80),
    (kElbowFlexionExtension, 160, 90),
    (kHeelSlide, 178, 80),
    (kMiniSquat, 178, 120),
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
  }
  test('incomplete cycles and noise cannot count', () {
    final e = ExerciseRulesAssessment(kHeelSlide);
    for (var i = 0; i < 100; i++) {
      e.update(pose(kHeelSlide, 177 + (i % 2)), 1000, 1000, i * .08);
    }
    for (var i = 100; i < 120; i++) {
      e.update(pose(kHeelSlide, 80), 1000, 1000, i * .08);
    }
    expect(e.repCount, 0);
  });
  test('tracking loss discards a partial repetition', () {
    final e = ExerciseRulesAssessment(kHeelSlide);
    for (var i = 0; i < 8; i++) {
      e.update(pose(kHeelSlide, 178), 1000, 1000, i * .08);
    }
    for (var i = 8; i < 18; i++) {
      e.update(pose(kHeelSlide, 80), 1000, 1000, i * .08);
    }
    final p = pose(kHeelSlide, 80);
    p[25]['visibility'] = .1;
    e.update(p, 1000, 1000, 1.5);
    for (var i = 20; i < 30; i++) {
      e.update(pose(kHeelSlide, 178), 1000, 1000, i * .08);
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
      e.update(pose(kHeelSlide, 178), 1000, 1000, i * .08);
    }
    e.update(pose(kHeelSlide, 80), 1000, 1000, .8);
    e.update(pose(kHeelSlide, 80), 1000, 1000, 1);
    e.update(pose(kHeelSlide, 178), 1000, 1000, 10);
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
        final s = e.update(
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
      final s = e.update(
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
      e.update(pose(kAssistedShoulderFlexion, 20), 1000, 1000, t);
    }
    for (var i = 1; i <= 16; i++, t += .08) {
      final p = pose(kAssistedShoulderFlexion, 20 + 140 * i / 16);
      if (i >= 4 && i <= 10) {
        for (final j in [11, 12, 13, 14, 15, 16]) {
          p[j]['x'] = (p[j]['x'] as double) + .08;
        }
      }
      final s = e.update(p, 1000, 1000, t);
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
      final s = e.update(p, 1000, 1000, i * .08);
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
        state = e.update(
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
      state = e.update(pose(kShoulderRotation, values[i]), 1000, 1000, i * .08);
    }
    expect(e.repCount, 0);
    expect(state!['error_type'], 'INCOMPLETE_RETURN');
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';

({List<Map<String, dynamic>> image, List<Map<String, dynamic>> world}) frame(
  double angle, {
  bool right = false,
  bool support = true,
}) {
  final w = List.generate(
    33,
    (_) => <String, dynamic>{'x': 0.0, 'y': 0.0, 'z': 0.0, 'visibility': .99},
  );
  void put(int i, double x, double y, double z) {
    w[i] = {'x': x, 'y': y, 'z': z, 'visibility': .99};
  }

  for (final r in [false, true]) {
    final x = r ? .2 : -.2;
    put(r ? 12 : 11, x, -.5, 0);
    put(r ? 14 : 13, x, -.2, 0);
    put(r ? 24 : 23, x, 0, 0);
    final a = (r == right ? angle : 170) * math.pi / 180;
    put(r ? 16 : 15, x, -.2 - .25 * math.cos(a), -.25 * math.sin(a));
  }
  final image = w
      .map(
        (p) => <String, dynamic>{
          'x': .5 + (p['x'] as double) * .8,
          'y': .8 + (p['y'] as double),
          'z': 0.0,
          'visibility': .99,
        },
      )
      .toList();
  if (support) {
    final e = image[right ? 14 : 13], wr = image[right ? 16 : 15];
    final ew = w[right ? 14 : 13], ww = w[right ? 16 : 15];
    w[right ? 15 : 16] = {
      for (final key in ['x', 'y', 'z'])
        key: ((ew[key] as num) + (ww[key] as num)) / 2,
      'visibility': .99,
    };
    image[right ? 15 : 16] = {
      'x': ((e['x'] as double) + (wr['x'] as double)) / 2,
      'y': ((e['y'] as double) + (wr['y'] as double)) / 2,
      'z': 0.0,
      'visibility': .99,
    };
  }
  return (image: image, world: w);
}

List<Map<String, dynamic>> run(
  ExerciseRulesAssessment engine,
  List<double> values, {
  bool right = false,
  bool Function(int)? supported,
  double start = 0,
  double supportImageOffset = 0,
}) {
  final completed = <Map<String, dynamic>>[];
  for (var i = 0; i < values.length; i++) {
    final p = frame(
      values[i],
      right: right,
      support: supported?.call(i) ?? true,
    );
    if (i >= 12 && supportImageOffset != 0) {
      p.image[right ? 15 : 16]['x'] =
          (p.image[right ? 15 : 16]['x'] as num) + supportImageOffset;
    }
    final state = engine.update(
      p.image,
      1000,
      1000,
      start + i * .08,
      worldLandmarks: p.world,
      angleSource: 'pose_world_landmarks',
    );
    if (state['completed_rep'] case final Map<String, dynamic> rep) {
      completed.add(rep);
    }
  }
  return completed;
}

List<double> movement({double peak = 50, double rest = 170}) => [
  ...List.filled(12, rest),
  for (var i = 1; i <= 25; i++) rest - (rest - peak) * i / 25,
  ...List.filled(8, peak),
  for (var i = 1; i <= 25; i++) peak + (rest - peak) * i / 25,
  ...List.filled(12, rest),
];
void main() {
  test('right-arm readiness uses its own steady resting angle', () {
    final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5);
    final reps = run(e, movement(rest: 145, peak: 60), right: true);
    expect(reps, hasLength(1));
    expect(reps.single['hand'], 'Right');
    expect(reps.single['form'], 'correct');
  });
  test('provisional support-arm movement is corrected when the right working arm becomes clear', () {
    final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5);
    run(e, [
      ...List.filled(12, 170.0),
      for (var i = 1; i <= 8; i++) 170 - 40 * i / 8,
    ], supported: (_) => false);
    final reps = run(e, movement(), right: true, start: 2);
    expect(reps, hasLength(1));
    expect(reps.single['hand'], 'Right');
    expect(reps.single['form'], 'correct');
  });
  test(
    'stable right-arm support tolerates a small estimated wrist-position shift',
    () {
      final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5, hand: 'Right');
      final reps = run(e, movement(), right: true, supportImageOffset: .09);
      expect(reps, hasLength(1));
      expect(reps.single['form'], 'correct');
    },
  );

  for (final right in [false, true]) {
    test(
      'world flexion handles foreshortened ${right ? 'right' : 'left'} arm and a moving support hand',
      () {
        final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5);
        final reps = run(e, movement(), right: right);
        expect(reps, hasLength(1));
        expect(reps.single['hand'], right ? 'Right' : 'Left');
        expect(reps.single['form'], 'correct');
        expect(reps.single['angle_source'], 'pose_world_landmarks');
        expect(reps.single['range_of_motion'], closeTo(120, 2));
      },
    );
  }
  test('support added after neutral and brief contact loss do not poison a complete cycle', () {
    final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5);
    final reps = run(
      e,
      movement(),
      supported: (i) => i >= 15 && !(i >= 36 && i <= 38),
    );
    expect(reps, hasLength(1));
    expect(reps.single['form'], 'correct');
  });
  test('unsupported world movement still fails and partial flexion misses its target', () {
    final unsupported = run(
      ExerciseRulesAssessment(kAssistedElbowFlexionV5),
      movement(),
      supported: (_) => false,
    );
    expect(unsupported.single['error_codes'], contains('SUPPORT_MISSING'));
    final partial = run(
      ExerciseRulesAssessment(kAssistedElbowFlexionV5),
      movement(peak: 115),
    );
    expect(partial.single['error_codes'], contains('TARGET_NOT_HELD'));
  });
  test('a reversal before the eventual held target is not a permanent failed-target error', () {
    final e = ExerciseRulesAssessment(kAssistedElbowFlexionV5);
    final values = [
      ...List.filled(12, 170.0),
      for (var i = 1; i <= 20; i++) 170 - 65 * i / 20,
      ...List.filled(5, 105.0),
      ...List.filled(6, 120.0),
      for (var i = 1; i <= 20; i++) 120 - 70 * i / 20,
      ...List.filled(8, 50.0),
      for (var i = 1; i <= 25; i++) 50 + 120 * i / 25,
      ...List.filled(12, 170.0),
    ];
    final reps = run(e, values);
    expect(reps, hasLength(1));
    expect(reps.single['target_reached'], true);
    expect(reps.single['error_codes'], isNot(contains('TARGET_NOT_HELD')));
  });
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/elbow_world_assessment.dart';

List<Map<String, dynamic>> _world(double left, double right) {
  final points = List.generate(33, (index) => <String, dynamic>{});
  for (final shoulder in [11, 12]) {
    final offset = shoulder == 11 ? -.3 : .3;
    final radians = (shoulder == 11 ? left : right) * math.pi / 180;
    points[shoulder] = {'x': offset + .3, 'y': .2, 'z': 0.0, 'visibility': .99};
    points[shoulder + 2] = {'x': offset, 'y': .2, 'z': 0.0, 'visibility': .99};
    points[shoulder + 4] = {
      'x': offset + .3 * math.cos(radians),
      'y': .2,
      'z': .3 * math.sin(radians),
      'visibility': .99,
    };
  }
  return points;
}

class _Driver {
  final engine = ElbowWorldAssessment();
  final double cadence;
  double time = 0;
  double left = 170;
  double right = 170;
  Map<String, dynamic> state = {};
  final List<Map<String, dynamic>> completed = [];

  _Driver({this.cadence = .04});

  void sample(double nextLeft, double nextRight) {
    time += cadence;
    left = nextLeft;
    right = nextRight;
    state = engine.update(
      [],
      640,
      480,
      time,
      worldLandmarks: _world(left, right),
      angleSource: ElbowWorldAssessment.source,
    );
    if (state['completed_rep'] case final Map<String, dynamic> rep) {
      completed.add(rep);
    }
  }

  void hold(double seconds, double nextLeft, double nextRight) {
    final frames = (seconds / cadence).ceil();
    for (var frame = 0; frame < frames; frame++) {
      sample(nextLeft, nextRight);
    }
  }

  void move(double seconds, double nextLeft, double nextRight) {
    final initialLeft = left;
    final initialRight = right;
    final frames = (seconds / cadence).ceil();
    for (var frame = 1; frame <= frames; frame++) {
      sample(
        initialLeft + (nextLeft - initialLeft) * frame / frames,
        initialRight + (nextRight - initialRight) * frame / frames,
      );
    }
  }

  void cycle({
    double initialLeft = 170,
    double initialRight = 170,
    double targetLeft = 65,
    double targetRight = 85,
    double? finalLeft,
    double? finalRight,
  }) {
    hold(.6, initialLeft, initialRight);
    move(1.2, targetLeft, targetRight);
    hold(.7, targetLeft, targetRight);
    move(1.2, finalLeft ?? initialLeft, finalRight ?? initialRight);
    hold(2.6, finalLeft ?? initialLeft, finalRight ?? initialRight);
  }
}

void main() {
  test('exact candidate thresholds and public summary', () {
    expect(ElbowWorldAssessment.thresholds, {
      'left': {
        'extension_min_deg': 152.59284378588075,
        'flexion_max_deg': 70.75558628426776,
        'rom_min_deg': 87.9257364170231,
        'return_error_max_deg': 7.763461670817362,
      },
      'right': {
        'extension_min_deg': 153.6168987049523,
        'flexion_max_deg': 91.96654666142514,
        'rom_min_deg': 70.01687215785255,
        'return_error_max_deg': 8.541307073061384,
      },
      'bilateral': {
        'maximum_angle_difference_deg': 34.758123896484435,
        'rom_difference_max_deg': 31.302325022900295,
      },
    });
    expect(ElbowWorldAssessment.thresholdSummary, contains('70.76'));
    expect(ElbowWorldAssessment.thresholdSummary, contains('0.2s'));
    expect(
      ElbowWorldAssessment.thresholdSummary,
      contains('Not clinically validated'),
    );
  });

  test('unequal bilateral targets succeed with serializable UI statistics', () {
    final driver = _Driver()..cycle();
    expect(driver.engine.repCount, 1);
    expect(driver.engine.correctCount, 1);
    final rep = driver.completed.single;
    expect(rep['form'], 'correct');
    expect(rep['required_left_target'], ElbowWorldAssessment.leftFlexionMax);
    expect(rep['required_right_target'], ElbowWorldAssessment.rightFlexionMax);
    expect(rep['assessment_method'], 'on_device_angle_rules');
    expect(rep['score_kind'], 'descriptive_movement_quality');
    expect(rep['clinically_validated'], false);
    expect(rep['calibration_status'], 'person_specific_candidate');
    expect(
      rep['calibration_source_session_id'],
      ElbowWorldAssessment.sourceSessionId,
    );
    expect(rep['arm_metrics']['left']['range_of_motion'], closeTo(105, .1));
    expect(rep['arm_metrics']['right']['range_of_motion'], closeTo(85, .1));
    expect(
      rep['left_range_of_motion'],
      greaterThan(rep['right_range_of_motion']),
    );
    expect(rep['smoothness'], inInclusiveRange(95, 100));
    expect(rep['angular_speed'], greaterThan(0));
    expect((rep['angle_trace'] as List).length, inInclusiveRange(3, 240));
    for (final component in ['form', 'posture', 'pace', 'range', 'return']) {
      expect(rep['score_components'][component], isA<num>());
    }
    expect(() => jsonEncode(rep), returnsNormally);
    expect(driver.state['rep_count'], 1);
    expect(driver.state['correct_reps'], 1);
  });

  for (final side in ['left', 'right']) {
    test('$side target miss counts incorrect exactly once on return', () {
      final driver = _Driver()
        ..cycle(
          targetLeft: side == 'left' ? 75 : 65,
          targetRight: side == 'right' ? 96 : 85,
        );
      final rep = driver.completed.single;
      expect(
        rep['error_codes'],
        contains('${side.toUpperCase()}_TARGET_NOT_HELD'),
      );
      expect(rep['score'], lessThanOrEqualTo(50));
      expect(rep['feedback'], isNot(contains('TARGET_NOT_HELD')));
      expect(rep['feedback_details'], everyElement(isA<String>()));
      driver.hold(4, 170, 170);
      expect(driver.engine.repCount, 1);
      expect(driver.engine.correctCount, 0);
      expect(driver.completed, hasLength(1));
    });
  }

  test('targets alone do not bypass per-arm ROM', () {
    final driver = _Driver()
      ..cycle(
        initialLeft: 153,
        initialRight: 154,
        targetLeft: 70,
        targetRight: 91,
      );
    final rep = driver.completed.single;
    expect(rep['target_reached'], true);
    expect(
      rep['error_codes'],
      containsAll(['LEFT_INSUFFICIENT_ROM', 'RIGHT_INSUFFICIENT_ROM']),
    );
    expect(driver.engine.correctCount, 0);
  });

  test(
    'ROM difference gates a cycle with acceptable instantaneous differences',
    () {
      final driver = _Driver()
        ..cycle(
          initialLeft: 178,
          initialRight: 154,
          targetLeft: 65,
          targetRight: 80,
        );
      final rep = driver.completed.single;
      expect(rep['error_codes'], ['BILATERAL_ROM_DIFFERENCE']);
      expect(rep['bilateral_metrics']['max_angle_difference'], lessThan(35));
      expect(driver.engine.correctCount, 0);
    },
  );

  test('transient angle asymmetry remains an error after symmetric return', () {
    final driver = _Driver();
    driver.hold(.6, 170, 170);
    driver.move(1, 65, 110);
    driver.hold(.5, 65, 110);
    driver.move(.6, 65, 85);
    driver.hold(.6, 65, 85);
    driver.move(1.2, 170, 170);
    driver.hold(2.6, 170, 170);
    expect(driver.completed.single['error_codes'], [
      'BILATERAL_ANGLE_DIFFERENCE',
    ]);
  });

  test('return error gates even above extension threshold', () {
    final driver = _Driver()..cycle(finalLeft: 160, finalRight: 160);
    expect(
      driver.completed.single['error_codes'],
      containsAll(['LEFT_INCOMPLETE_RETURN', 'RIGHT_INCOMPLETE_RETURN']),
    );
    expect(driver.engine.correctCount, 0);
    driver.hold(4, 160, 160);
    expect(driver.engine.repCount, 1);
  });

  test(
    'brief return pause does not complete, stable incomplete return does',
    () {
      final driver = _Driver();
      driver.hold(.6, 170, 170);
      driver.move(1, 65, 85);
      driver.hold(.6, 65, 85);
      driver.move(1, 130, 140);
      driver.hold(.8, 130, 140);
      expect(driver.engine.repCount, 0);
      driver.hold(2, 130, 140);
      expect(driver.engine.repCount, 1);
      expect(driver.completed.single['form'], 'incorrect');
      driver.move(1, 170, 170);
      driver.hold(3, 170, 170);
      expect(driver.engine.repCount, 1);
    },
  );

  test('extension and flexion require holds on each arm', () {
    final driver = _Driver();
    driver.hold(.2, 170, 170);
    driver.move(.4, 65, 85);
    driver.hold(.6, 65, 85);
    driver.move(.5, 170, 170);
    driver.hold(.6, 170, 170);
    expect(driver.engine.repCount, 0);
    driver.move(.3, 65, 85);
    driver.move(.3, 170, 170);
    driver.hold(2.6, 170, 170);
    expect(driver.completed.single['target_reached'], false);
  });

  test('world XYZ angles ignore image geometry and aspect ratio', () {
    final engine = ElbowWorldAssessment();
    final world = _world(65, 85);
    final first = engine.update(
      [],
      10,
      2000,
      0,
      worldLandmarks: world,
      angleSource: ElbowWorldAssessment.source,
    );
    final image = _world(140, 170);
    final second = engine.update(
      image,
      2000,
      10,
      .1,
      worldLandmarks: world,
      angleSource: ElbowWorldAssessment.source,
    );
    expect(first['left_angle'], closeTo(65, 1e-10));
    expect(first['right_angle'], closeTo(85, 1e-10));
    expect(second['left_angle'], first['left_angle']);
    expect(second['right_angle'], first['right_angle']);
    expect(second['landmarks'], same(image));
  });

  test('causal filter uses elapsed timestamp with tau 0.08', () {
    final engine = ElbowWorldAssessment();
    engine.update(
      [],
      640,
      480,
      0,
      worldLandmarks: _world(170, 170),
      angleSource: ElbowWorldAssessment.source,
    );
    final state = engine.update(
      [],
      640,
      480,
      .08,
      worldLandmarks: _world(70, 90),
      angleSource: ElbowWorldAssessment.source,
    );
    expect(state['left_angle'], closeTo(70 + 100 * math.exp(-1), 1e-9));
    expect(state['right_angle'], closeTo(90 + 80 * math.exp(-1), 1e-9));
  });

  for (final cadence in [.016, .04, .1, .2]) {
    test('time based cycle works at cadence $cadence', () {
      final driver = _Driver(cadence: cadence)..cycle();
      expect(driver.engine.repCount, 1);
      expect(driver.engine.correctCount, 1);
    });
  }

  test('missing world or wrong source never falls back to image', () {
    for (final source in [
      null,
      'pose_landmarks',
      'mlkit',
      'pose_world_landmarks',
    ]) {
      final state = ElbowWorldAssessment().update(
        _world(170, 170),
        640,
        480,
        0,
        worldLandmarks: source == 'pose_world_landmarks'
            ? null
            : _world(170, 170),
        angleSource: source,
      );
      expect(state['tracking_valid'], false);
      expect(state['form'], 'Waiting');
      expect(state['angle'], isNull);
      expect(state['rep_count'], 0);
    }
  });

  test(
    'invalid world coordinates confidence and degenerate segments reject',
    () {
      final invalid = <List<Map<String, dynamic>>>[
        [],
        _world(170, 170).take(16).toList(),
      ];
      for (final field in ['x', 'y', 'z', 'visibility', 'presence']) {
        for (final value in [null, 'bad', double.nan, double.infinity]) {
          final points = _world(170, 170);
          points[15][field] = value;
          invalid.add(points);
        }
      }
      for (final value in [-1, .49, 1.01]) {
        final points = _world(170, 170);
        points[12]['visibility'] = value;
        invalid.add(points);
      }
      final missingDepth = _world(170, 170);
      missingDepth[16].remove('z');
      invalid.add(missingDepth);
      final degenerate = _world(170, 170);
      degenerate[11] = Map.from(degenerate[13]);
      invalid.add(degenerate);
      for (final points in invalid) {
        final state = ElbowWorldAssessment().update(
          [],
          640,
          480,
          0,
          worldLandmarks: points,
          angleSource: ElbowWorldAssessment.source,
        );
        expect(state['tracking_valid'], false);
        expect(state['angle'], isNull);
      }
    },
  );

  test('invalid dimensions and timestamps reject without counting', () {
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      for (final dimensions in [(invalid, 480.0), (640.0, invalid)]) {
        final state = ElbowWorldAssessment().update(
          [],
          dimensions.$1,
          dimensions.$2,
          0,
          worldLandmarks: _world(170, 170),
          angleSource: ElbowWorldAssessment.source,
        );
        expect(state['tracking_valid'], false);
      }
    }
    for (final invalid in [double.nan, double.infinity]) {
      expect(
        ElbowWorldAssessment().update(
          [],
          640,
          480,
          invalid,
          worldLandmarks: _world(170, 170),
          angleSource: ElbowWorldAssessment.source,
        )['tracking_valid'],
        false,
      );
    }
  });

  for (final interruption in [
    'missing',
    'duplicate',
    'backward',
    'gap',
    'reset',
  ]) {
    test('$interruption interrupts an in-flight rep without a phantom rep', () {
      final driver = _Driver();
      driver.hold(.6, 170, 170);
      driver.move(1, 65, 85);
      driver.hold(.6, 65, 85);
      switch (interruption) {
        case 'missing':
          driver.engine.update([], 640, 480, driver.time + .01);
        case 'duplicate':
        case 'backward':
          driver.engine.update(
            [],
            640,
            480,
            driver.time - (interruption == 'backward' ? .1 : 0),
            worldLandmarks: _world(65, 85),
            angleSource: ElbowWorldAssessment.source,
          );
        case 'gap':
          driver.time += 1;
        case 'reset':
          driver.engine.resetTracking();
      }
      driver.move(1, 170, 170);
      driver.hold(1, 170, 170);
      expect(driver.engine.repCount, 0);
      driver.cycle();
      expect(driver.engine.repCount, 1);
      driver.engine.resetTracking();
      expect(driver.engine.repCount, 1);
      expect(driver.engine.correctCount, 1);
    });
  }

  test('tracking times out and long traces stay bounded', () {
    final driver = _Driver();
    driver.hold(.6, 170, 170);
    driver.move(1, 65, 85);
    driver.hold(46, 65, 85);
    expect(driver.engine.stage, 'POSITIONING');
    driver.move(1, 170, 170);
    driver.hold(1, 170, 170);
    expect(driver.engine.repCount, 0);
    driver.move(1, 65, 85);
    driver.hold(12, 65, 85);
    driver.move(1, 170, 170);
    driver.hold(1, 170, 170);
    final rep = driver.completed.single;
    expect((rep['angle_trace'] as List).length, lessThanOrEqualTo(240));
    expect(rep['score'], lessThan(100));
    expect(rep['speed'], 'Slow');
  });
}

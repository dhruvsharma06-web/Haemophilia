import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/shoulder_rotation_assessment.dart';

/// Builds a world-landmark set for a subject facing the camera.
///
/// The subject's right shoulder sits at world -x, their left at +x, and the
/// forward axis points toward the camera at -z (MediaPipe's convention).
/// [rotationDegrees] swings both forearms together around the vertical axis:
/// positive moves the wand toward the subject's left (+x).
List<Map<String, dynamic>> _world({
  double rotationDegrees = 0,
  double elbowBend = 90,
  double upperArmOffset = 0,
  double sidewaysLean = 0,
  bool rightArmFollows = true,
  bool bilateralExternal = false,
  double rightRotationScale = 1,
}) {
  final points = List.generate(
    33,
    (_) => <String, dynamic>{
      'x': 0.0,
      'y': 0.0,
      'z': 0.0,
      'visibility': .99,
      'presence': .99,
    },
  );
  void put(int index, double x, double y, double z) {
    points[index] = {
      'x': x,
      'y': y,
      'z': z,
      'visibility': .99,
      'presence': .99,
    };
  }

  // Hips and shoulders. A sideways lean shears x with height.
  final lean = sidewaysLean * math.pi / 180;
  put(23, -.17, .90, 0);
  put(24, .17, .90, 0);
  put(11, -.19 + math.sin(lean) * .5, .40, 0);
  put(12, .19 + math.sin(lean) * .5, .40, 0);

  final rotation = rotationDegrees * math.pi / 180;
  final bend = elbowBend * math.pi / 180;
  final arm = upperArmOffset * math.pi / 180;
  // Upper arm hangs down and slightly out; the forearm turns in the
  // horizontal plane by `rotation`.
  for (final (shoulder, elbow, wrist, side) in [
    (11, 13, 15, -1.0),
    (12, 14, 16, 1.0),
  ]) {
    final sx = points[shoulder]['x'] as double;
    final sy = points[shoulder]['y'] as double;
    final ex = sx + side * math.sin(arm) * .30;
    final ey = sy + math.cos(arm) * .30;
    put(elbow, ex, ey, 0);
    final angle = side == 1 && !rightArmFollows
        ? 0.0
        : bilateralExternal && side < 0
        ? -rotation
        : rotation;
    final scaledAngle = angle * (side == 1 ? rightRotationScale : 1);
    // Forearm length grows from the elbow, pointing forward (-z) at neutral
    // and swinging in the horizontal plane as the wand rotates.
    final fore = math.sin(bend) * .28;
    put(
      wrist,
      ex + math.sin(scaledAngle) * fore,
      ey + math.cos(bend) * .28,
      -math.cos(scaledAngle) * fore,
    );
  }
  return points;
}

/// Image-plane landmarks matching the world pose closely enough for the
/// posture checks (upright torso, level wand).
List<Map<String, dynamic>> _image({
  double rotationDegrees = 0,
  double sidewaysLean = 0,
  double wandTilt = 0,
  double upperArmOffset = 0,
  double shoulderScale = 1,
}) {
  final points = List.generate(
    33,
    (_) => <String, dynamic>{
      'x': .5,
      'y': .5,
      'z': 0.0,
      'visibility': .99,
      'presence': .99,
    },
  );
  points[23] = {'x': .50, 'y': .90, 'z': 0.0, 'visibility': .99};
  points[24] = {'x': .50, 'y': .90, 'z': 0.0, 'visibility': .99};
  // Place the shoulder midpoint so the measured (aspect-corrected) angle from
  // vertical equals the requested lean. The check uses pixel deltas, so solve
  // for the horizontal offset that yields that angle at this aspect ratio.
  final leanRadians = sidewaysLean * math.pi / 180;
  final dy = (.90 - .35) * 640;
  final dx = math.tan(leanRadians) * dy;
  final shoulderMidX = .50 + dx / 480;
  points[11] = {
    'x': shoulderMidX - .10 * shoulderScale,
    'y': .35,
    'z': 0.0,
    'visibility': .99,
  };
  points[12] = {
    'x': shoulderMidX + .10 * shoulderScale,
    'y': .35,
    'z': 0.0,
    'visibility': .99,
  };
  points[13] = {'x': .38, 'y': .55, 'z': 0.0, 'visibility': .99};
  points[14] = {'x': .62, 'y': .55, 'z': 0.0, 'visibility': .99};
  if (upperArmOffset != 0) {
    final r = upperArmOffset * math.pi / 180;
    for (final pair in [(11, 13, -1), (12, 14, 1)]) {
      points[pair.$2] = {
        ...points[pair.$2],
        'x':
            (points[pair.$1]['x'] as double) +
            pair.$3 * math.sin(r) * 128 / 480,
        'y': .35 + math.cos(r) * .2,
      };
    }
  }
  final shift = rotationDegrees / 1000;
  final tilt = wandTilt / 1000;
  points[15] = {'x': .40 + shift, 'y': .62 + tilt, 'z': 0.0, 'visibility': .99};
  points[16] = {'x': .60 + shift, 'y': .62 - tilt, 'z': 0.0, 'visibility': .99};
  return points;
}

class _Driver {
  final ShoulderRotationAssessment engine;
  final bool bilateralExternal;
  final bool autoProtocol;
  final bool reflectWorldX;
  final double cadence;
  double time = 0;
  double rotation = 0;
  Map<String, dynamic> state = {};
  final List<Map<String, dynamic>> completed = [];

  _Driver({
    this.cadence = .05,
    this.bilateralExternal = false,
    this.autoProtocol = false,
    this.reflectWorldX = false,
  }) : engine = ShoulderRotationAssessment(
         bilateralExternal: bilateralExternal || autoProtocol,
         autoProtocol: autoProtocol,
       );

  Map<String, dynamic> sample(
    double nextRotation, {
    bool image = true,
    double sidewaysLean = 0,
    double wandTilt = 0,
    double elbowBend = 90,
    double upperArmOffset = 0,
    double? imageUpperArmOffset,
    double depthYaw = 0,
    double shoulderScale = 1,
    bool? externalPose,
    double rightRotationScale = 1,
  }) {
    time += cadence;
    rotation = nextRotation;
    var imagePoints = _image(
      rotationDegrees: image ? nextRotation / 40 : 0,
      sidewaysLean: sidewaysLean,
      wandTilt: wandTilt,
      upperArmOffset: imageUpperArmOffset ?? upperArmOffset,
      shoulderScale: shoulderScale,
    );
    if (autoProtocol) {
      final projected = _world(
        rotationDegrees: image ? nextRotation : 0,
        elbowBend: elbowBend,
        upperArmOffset: imageUpperArmOffset ?? upperArmOffset,
        sidewaysLean: sidewaysLean,
        bilateralExternal: externalPose ?? bilateralExternal,
        rightRotationScale: rightRotationScale,
      );
      imagePoints = projected
          .map(
            (p) => <String, dynamic>{
              'x': .5 + (p['x'] as num) * 600 / 480,
              'y': .1 + (p['y'] as num) * 600 / 640,
              'z': 0.0,
              'visibility': .99,
            },
          )
          .toList();
      for (final i in [11, 12]) {
        imagePoints[i]['x'] =
            .5 + ((imagePoints[i]['x'] as num) - .5) * shoulderScale;
      }
    }
    state = engine.update(
      imagePoints,
      480,
      640,
      time,
      worldLandmarks:
          _world(
                rotationDegrees: nextRotation,
                elbowBend: elbowBend,
                upperArmOffset: upperArmOffset,
                sidewaysLean: sidewaysLean,
                bilateralExternal: externalPose ?? bilateralExternal,
                rightRotationScale: rightRotationScale,
              )
              .map(
                (point) => reflectWorldX
                    ? {...point, 'x': -(point['x'] as num).toDouble()}
                    : point,
              )
              .map((p) {
                final a = depthYaw * math.pi / 180;
                return {
                  ...p,
                  'x':
                      (p['x'] as num) * math.cos(a) +
                      (p['z'] as num) * math.sin(a),
                  'z':
                      -(p['x'] as num) * math.sin(a) +
                      (p['z'] as num) * math.cos(a),
                };
              })
              .toList(),
      angleSource: ShoulderRotationAssessment.source,
    );
    if (state['completed_rep'] case final Map<String, dynamic> rep) {
      completed.add(rep);
    }
    return state;
  }

  void hold(double seconds, double rotation, {double sidewaysLean = 0}) {
    final frames = (seconds / cadence).ceil();
    for (var frame = 0; frame < frames; frame++) {
      sample(rotation, sidewaysLean: sidewaysLean);
    }
  }

  void move(double seconds, double target, {double sidewaysLean = 0}) {
    final start = rotation;
    final frames = (seconds / cadence).ceil();
    for (var frame = 1; frame <= frames; frame++) {
      sample(
        start + (target - start) * frame / frames,
        sidewaysLean: sidewaysLean,
      );
    }
  }

  /// Centre -> +extreme -> centre -> -extreme, which is one repetition.
  void cycle({
    double amplitude = 25,
    double centre = .7,
    double travel = .8,
    double extremeHold = .3,
  }) {
    hold(.8, 0);
    move(travel, amplitude);
    hold(extremeHold, amplitude);
    move(travel, 0);
    hold(centre, 0);
    move(travel, -amplitude);
    hold(extremeHold, -amplitude);
  }
}

void main() {
  test('paired shoulder targets tolerate unequal camera amplitudes without a false coordination failure', () {
    final d = _Driver(bilateralExternal: true, autoProtocol: true);
    d.hold(1, 0);
    for (final a in [
      for (var i = 1; i <= 45; i++) i.toDouble(),
      ...List.filled(10, 45.0),
      for (var i = 44; i >= 0; i--) i.toDouble(),
      ...List.filled(12, 0.0),
    ]) {
      d.sample(a, rightRotationScale: .6);
    }
    expect(d.engine.repCount, 1);
    expect(d.completed.single['form'], 'correct');
  });
  test('sequential shoulder starts still fail coordination despite reaching both targets', () {
    final d = _Driver(bilateralExternal: true, autoProtocol: true);
    d.hold(1, 0);
    for (var i = 1; i <= 30; i++) {
      d.sample(i.toDouble(), rightRotationScale: 0);
    }
    for (var i = 0; i < 12; i++) {
      d.sample(30, rightRotationScale: 0);
    }
    for (var i = 1; i <= 20; i++) {
      d.sample(30, rightRotationScale: i / 20);
    }
    d.hold(.4, 30);
    d.move(1, 0);
    d.hold(.5, 0);
    expect(d.engine.repCount, 1);
    expect(
      d.completed.single['error_codes'],
      contains('BILATERAL_COORDINATION'),
    );
  });

  test('calibration freezes arm scale and computes neutral in the same coordinate scale', () {
    final e = ShoulderRotationAssessment(
      bilateralExternal: true,
      autoProtocol: true,
    );
    Map<String, dynamic> state = {};
    for (var frame = 0; frame < 40; frame++) {
      final w = _world(rotationDegrees: 30, bilateralExternal: true);
      final image = w
          .map(
            (p) => <String, dynamic>{
              'x': .5 + (p['x'] as num) * 600 / 480,
              'y': .1 + (p['y'] as num) * 600 / 640,
              'z': 0.0,
              'visibility': .99,
            },
          )
          .toList();
      final scale = frame.isEven ? .7 : 1.3;
      for (final pair in [(13, 15), (14, 16)]) {
        for (final key in ['x', 'y', 'z']) {
          w[pair.$2][key] =
              (w[pair.$1][key] as num) +
              ((w[pair.$2][key] as num) - (w[pair.$1][key] as num)) * scale;
        }
      }
      state = e.update(
        image,
        480,
        640,
        frame * .05,
        worldLandmarks: w,
        angleSource: ShoulderRotationAssessment.source,
      );
    }
    expect(e.calibrated, true);
    expect(e.repCount, 0);
    expect((state['left_angle'] as num).abs(), lessThan(2));
    expect((state['right_angle'] as num).abs(), lessThan(2));
  });

  test(
    'both app movement patterns expose live target hold before the return',
    () {
      for (final external in [false, true]) {
        final driver = _Driver(bilateralExternal: external, autoProtocol: true);
        driver.hold(1, 0);
        driver.move(1, 30);
        driver.hold(.4, 30);
        expect(driver.state['target_reached'], true);
        expect(driver.state['target_hold_progress'], 1.0);
        expect(driver.engine.repCount, 0);
        driver.move(1, 0);
        driver.hold(.5, 0);
        expect(driver.engine.repCount, 1);
        expect(driver.completed.single['form'], 'correct');
      }
    },
  );

  test(
    'app neutral calibration accepts still hands despite model depth jitter',
    () {
      final driver = _Driver(bilateralExternal: true, autoProtocol: true);
      for (var i = 0; i < 30; i++) {
        driver.sample(i.isEven ? 20 : -20, image: false);
      }
      expect(driver.engine.calibrated, true);
      expect(driver.engine.repCount, 0);
      for (var i = 0; i < 60; i++) {
        driver.sample(i.isEven ? 35 : -35, image: false);
      }
      expect(driver.engine.repCount, 0);
    },
  );
  for (final external in [false, true]) {
    test(
      'app counts a movement and return from a held non-central start, external=$external',
      () {
        final driver = _Driver(bilateralExternal: external, autoProtocol: true);
        final start = external ? 30.0 : -25.0, target = external ? 0.0 : 25.0;
        driver.hold(1, start);
        driver.move(1, target);
        driver.hold(.4, target);
        driver.move(1, start);
        driver.hold(.5, start);
        expect(driver.engine.repCount, 1);
        expect(driver.completed.single['form'], 'correct');
        expect(
          driver.completed.single['angle_source'],
          'image_lateral_with_world_scale',
        );
      },
    );
  }

  for (final confirmed in [false, true]) {
    test(
      'world shoulder-depth noise needs frontal evidence to grade torso twist, evidence=$confirmed',
      () {
        final driver = _Driver(bilateralExternal: true, autoProtocol: true);
        driver.hold(1, 0);
        for (final r in [
          for (var i = 1; i <= 30; i++) i.toDouble(),
          ...List.filled(12, 30.0),
          for (var i = 29; i >= 0; i--) i.toDouble(),
          ...List.filled(12, 0.0),
        ]) {
          driver.sample(r, depthYaw: 30, shoulderScale: confirmed ? .7 : 1);
        }
        expect(driver.completed, hasLength(1));
        expect(
          driver.completed.single['error_codes'],
          confirmed ? contains('TORSO_TWIST') : isNot(contains('TORSO_TWIST')),
        );
      },
    );
  }
  test('outward-return relative motion works with either calibrated sign', () {
    final driver = _Driver(bilateralExternal: true, autoProtocol: true);
    driver.hold(1, 0);
    driver.move(1, -30);
    driver.hold(.4, -30);
    driver.move(1, 0);
    driver.hold(.5, 0);
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'correct');
  });
  test(
    'brief paired tremor is not recorded as an incorrect shoulder repetition',
    () {
      final driver = _Driver(bilateralExternal: true, autoProtocol: true);
      driver.hold(1, 0);
      driver.move(.1, 9);
      driver.hold(.15, 9);
      driver.move(.1, 0);
      driver.hold(.5, 0);
      expect(driver.engine.repCount, 0);
    },
  );
  test('a different shoulder pattern can be chosen after a completed neutral return', () {
    final driver = _Driver(bilateralExternal: true, autoProtocol: true);
    driver.hold(1, 0);
    driver.move(1, 30);
    driver.hold(.4, 30);
    driver.move(1, 0);
    driver.hold(.5, 0);
    for (final r in [
      for (var i = 1; i <= 30; i++) i.toDouble(),
      ...List.filled(10, 30.0),
      for (var i = 29; i >= -30; i--) i.toDouble(),
      ...List.filled(10, -30.0),
      for (var i = -29; i <= 0; i++) i.toDouble(),
      ...List.filled(10, 0.0),
    ]) {
      driver.sample(r, externalPose: false);
    }
    expect(driver.engine.repCount, 3);
    expect(
      driver.completed.last['movement_protocol'],
      'bilateral_sweep_return',
    );
  });

  test('neutral model-depth offset does not grade straight visible upper arms incorrect', () {
    final driver = _Driver(bilateralExternal: true, autoProtocol: true);
    for (final rotation in [
      ...List.filled(20, 0.0),
      for (var i = 1; i <= 30; i++) i.toDouble(),
      ...List.filled(10, 30.0),
      for (var i = 29; i >= 0; i--) i.toDouble(),
      ...List.filled(12, 0.0),
    ]) {
      driver.sample(rotation, upperArmOffset: 30, imageUpperArmOffset: 0);
    }
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'correct');
  });
  test(
    'shoulder live form warns before sustained errors and resets after a cycle',
    () {
      final driver = _Driver(bilateralExternal: true, autoProtocol: true);
      driver.hold(1, 0);
      driver.move(1, 30);
      driver.hold(.3, 30);
      expect(driver.sample(30, upperArmOffset: 30)['form'], 'Adjusting');
      for (var i = 0; i < 24; i++) {
        driver.sample(30, upperArmOffset: 30);
      }
      expect(driver.state['form'], 'incorrect');
      driver.move(1, 0);
      driver.hold(.5, 0);
      expect(driver.completed.single['form'], 'incorrect');
      driver.hold(.5, 0);
      expect(driver.state['form'], 'correct');
    },
  );

  test('auto pattern requires bilateral movement and rejects idle jitter', () {
    final engine = ShoulderRotationAssessment(
      bilateralExternal: true,
      autoProtocol: true,
    );
    for (var frame = 0; frame < 100; frame++) {
      engine.update(
        _image(),
        480,
        640,
        frame * .05,
        worldLandmarks: _world(
          rotationDegrees: frame < 20 ? 0 : 30,
          rightArmFollows: false,
        ),
        angleSource: ShoulderRotationAssessment.source,
      );
    }
    expect(engine.repCount, 0);
  });
  test('repeated outward-return cycles do not double count or survive tracking loss', () {
    final driver = _Driver(bilateralExternal: true, autoProtocol: true);
    driver.hold(1, 0);
    for (var i = 0; i < 3; i++) {
      driver.move(.8, 30);
      driver.hold(.4, 30);
      driver.move(.8, 0);
      driver.hold(.4, 0);
      expect(driver.engine.repCount, i + 1);
    }
    driver.move(.8, 30);
    driver.hold(.4, 30);
    driver.engine.update(
      [],
      480,
      640,
      driver.time + .05,
      worldLandmarks: [],
      angleSource: ShoulderRotationAssessment.source,
    );
    driver.move(.8, 0);
    driver.hold(1, 0);
    expect(driver.engine.repCount, 3);
  });

  test('app recognizes same-direction shoulder sweep independently', () {
    final driver = _Driver(autoProtocol: true);
    driver.cycle();
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'correct');
    expect(
      driver.completed.single['movement_protocol'],
      'bilateral_sweep_return',
    );
  });
  for (final mirrored in [false, true]) {
    test(
      'external protocol follows anatomical sides with world x reflection=$mirrored',
      () {
        final driver = _Driver(
          bilateralExternal: true,
          autoProtocol: true,
          reflectWorldX: mirrored,
        );
        driver.hold(1, 0);
        driver.move(1, 30);
        driver.hold(.5, 30);
        driver.move(1, 0);
        driver.hold(.5, 0);
        expect(driver.engine.repCount, 1);
        expect(driver.completed.single['form'], 'correct');
        expect(
          driver.completed.single['movement_protocol'],
          'bilateral_outward_return',
        );
      },
    );
  }

  test('app tutorial outward rotation and return counts once, without a wand sweep', () {
    final driver = _Driver(bilateralExternal: true);
    driver.hold(1, 0);
    driver.move(1, 30);
    driver.hold(.5, 30);
    expect(driver.engine.repCount, 0);
    driver.move(1, 0);
    driver.hold(.5, 0);
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'correct');
    expect(
      driver.completed.single['movement_protocol'],
      'bilateral_outward_return',
    );
    driver.hold(2, 0);
    expect(driver.engine.repCount, 1);
  });

  test('visible non-ideal upper arms count with form feedback rather than never starting', () {
    final driver = _Driver(bilateralExternal: true);
    for (var i = 0; i < 20; i++) {
      driver.sample(0, upperArmOffset: 30);
    }
    expect(driver.engine.calibrated, true);
    for (final rotation in [
      for (var i = 1; i <= 30; i++) i.toDouble(),
      ...List.filled(12, 30.0),
      for (var i = 29; i >= 0; i--) i.toDouble(),
      ...List.filled(12, 0.0),
    ]) {
      driver.sample(rotation, upperArmOffset: 30);
    }
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'incorrect');
    expect(
      driver.completed.single['error_codes'],
      contains('UPPER_ARM_POSITION'),
    );
  });
  test('visible wrists at phone-measured confidence can calibrate', () {
    final engine = ShoulderRotationAssessment();
    for (var frame = 0; frame < 20; frame++) {
      final points = _world();
      points[13]['visibility'] = .64;
      points[15]['visibility'] = .65;
      final state = engine.update(
        _image(),
        480,
        640,
        frame * .05,
        worldLandmarks: points,
        angleSource: ShoulderRotationAssessment.source,
      );
      expect(state['tracking_valid'], true);
    }
    expect(engine.calibrated, true);
  });
  test('a smooth centre crossing between camera samples completes a cycle', () {
    final driver = _Driver(cadence: .2);
    driver.hold(1, 0);
    driver.move(1, 30);
    driver.hold(.6, 30);
    driver.move(.6, -30);
    driver.hold(.8, -30);
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'correct');
    expect((driver.state['left_angle'] as num).abs(), closeTo(30, .1));
  });
  test('holding the completed extreme cannot arm the next repetition', () {
    final driver = _Driver()..cycle();
    driver.hold(2, -25);
    expect(driver.engine.repCount, 1);
    expect(driver.engine.stage, 'NEED_CENTRE');
    driver.move(.8, 0);
    driver.hold(.7, 0);
    expect(driver.engine.stage, 'CENTRE');
    driver.cycle();
    expect(driver.engine.repCount, 2);
  });

  test(
    'moving forearms cannot be accepted as a steady neutral calibration',
    () {
      final driver = _Driver();
      for (var frame = 0; frame < 25; frame++) {
        driver.sample(frame * 3.0);
      }
      expect(driver.engine.calibrated, false);
      driver.hold(.8, 0);
      expect(driver.engine.calibrated, true);
    },
  );

  test('thresholds match the supplied report exactly', () {
    expect(ShoulderRotationAssessment.elbowBendMin, 60);
    expect(ShoulderRotationAssessment.elbowBendMax, 120);
    expect(ShoulderRotationAssessment.elbowBendTarget, 90);
    expect(ShoulderRotationAssessment.upperArmMax, 20);
    expect(ShoulderRotationAssessment.sidewaysLeanMax, 12);
    expect(ShoulderRotationAssessment.forwardLeanChangeMax, 10);
    expect(ShoulderRotationAssessment.torsoTwistMax, 10);
    expect(ShoulderRotationAssessment.wandLevelMax, 10);
    expect(ShoulderRotationAssessment.failurePersistenceFraction, .2);
    expect(ShoulderRotationAssessment.neutralHoldSeconds, .5);
    expect(ShoulderRotationAssessment.centreBandDegrees, 5);
    expect(ShoulderRotationAssessment.extremeDegrees, 20);
    expect(ShoulderRotationAssessment.extremeHoldSeconds, .15);
    expect(ShoulderRotationAssessment.bilateralMaxDifference, 15);
    expect(ShoulderRotationAssessment.fullExcursionDegrees, 40);
    expect(ShoulderRotationAssessment.visibilityMin, .5);
    expect(
      ShoulderRotationAssessment.provenance,
      'proposed_engineering_settings',
    );
    expect(
      ShoulderRotationAssessment.thresholds['elbow_bend']['status'],
      'existing',
    );
    expect(
      ShoulderRotationAssessment.thresholds['torso_sideways_lean']['status'],
      'existing',
    );
    expect(
      ShoulderRotationAssessment.thresholds['torso_twist']['status'],
      'proposed',
    );
    expect(
      ShoulderRotationAssessment.thresholdSummary,
      allOf(contains('60-120'), contains('Proposed engineering settings')),
    );
    expect(
      () => jsonEncode(ShoulderRotationAssessment.thresholds),
      returnsNormally,
    );
  });

  test('bundled calibration file matches the engine constants', () {
    final reference = jsonDecode(
      File('../docs/calibration/shoulder-rotation.json').readAsStringSync(),
    ) as Map;
    expect(ShoulderRotationAssessment.thresholds, reference['thresholds']);
    expect(ShoulderRotationAssessment.provenance, reference['status']);
    expect(ShoulderRotationAssessment.source, reference['angle_source']);
    expect(reference['provenance_notes'], contains('not degrees'));
  });

  test('a full centre-extreme-centre-opposite cycle counts once', () {
    final driver = _Driver()..cycle();
    expect(driver.engine.repCount, 1);
    expect(driver.engine.correctCount, 1);
    final rep = driver.completed.single;
    expect(rep['form'], 'correct');
    expect(rep['error_codes'], isEmpty);
    expect(rep['hand'], 'Both');
    expect(rep['assessment_method'], 'on_device_angle_rules');
    expect(rep['clinically_validated'], false);
    expect(rep['calibration_status'], 'proposed_engineering_settings');
    expect(rep['left_excursion'], greaterThan(30));
    expect(rep['right_excursion'], greaterThan(30));
    expect(rep['range_of_motion'], greaterThan(30));
    expect(rep['duration'], greaterThan(1));
    expect(rep['score'], isA<num>());
    expect(() => jsonEncode(rep), returnsNormally);
  });

  test('both directions complete a repetition', () {
    for (final first in [1, -1]) {
      final driver = _Driver();
      driver.hold(.8, 0);
      driver.move(.8, first * 25);
      driver.hold(.3, first * 25);
      driver.move(.8, 0);
      driver.hold(.7, 0);
      driver.move(.8, -first * 25);
      driver.hold(.3, -first * 25);
      expect(driver.engine.repCount, 1, reason: 'first=$first');
    }
  });

  test('a single-sided sweep is not a repetition', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.move(.8, 25);
    driver.hold(.5, 25);
    driver.move(.8, 0);
    driver.hold(1.2, 0);
    expect(driver.engine.repCount, 0);
  });

  test('returning through centre and out the same side does not count', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.move(.8, 25);
    driver.hold(.3, 25);
    driver.move(.8, 0);
    driver.hold(.5, 0);
    driver.move(.8, 24);
    driver.hold(.5, 24);
    expect(driver.engine.repCount, 0);
    expect(driver.engine.stage, isNot('BACK_TO_CENTRE'));
  });

  test('a movement below the extreme threshold never starts a cycle', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.move(1.4, 15);
    driver.hold(.5, 15);
    driver.move(1.4, 0);
    driver.hold(.8, 0);
    expect(driver.engine.repCount, 0);
    expect(driver.engine.stage, 'CENTRE');
  });

  test('the extreme needs its hold, not a single spike', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.sample(25); // one frame beyond the threshold
    driver.move(.4, 0);
    driver.hold(.6, 0);
    expect(driver.engine.stage, 'CENTRE');
    expect(driver.engine.repCount, 0);
  });

  test('calibration needs a stable neutral hold', () {
    final engine = ShoulderRotationAssessment();
    var time = 0.0;
    for (var frame = 0; frame < 4; frame++) {
      time += .05;
      final state = engine.update(
        _image(),
        480,
        640,
        time,
        worldLandmarks: _world(),
        angleSource: ShoulderRotationAssessment.source,
      );
      expect(state['form'], 'Waiting');
    }
    expect(engine.calibrated, false);
    for (var frame = 0; frame < 10; frame++) {
      time += .05;
      engine.update(
        _image(),
        480,
        640,
        time,
        worldLandmarks: _world(),
        angleSource: ShoulderRotationAssessment.source,
      );
    }
    expect(engine.calibrated, true);
    expect(engine.stage, 'CENTRE');
  });

  test('a bent or lifted arm prevents calibration instead of guessing', () {
    for (final (label, bend, offset) in [
      ('bent too far', 140.0, 0.0),
      ('too straight', 40.0, 0.0),
      ('upper arm out', 90.0, 30.0),
    ]) {
      final engine = ShoulderRotationAssessment();
      var time = 0.0;
      Map<String, dynamic> state = {};
      for (var frame = 0; frame < 20; frame++) {
        time += .05;
        state = engine.update(
          _image(),
          480,
          640,
          time,
          worldLandmarks: _world(elbowBend: bend, upperArmOffset: offset),
          angleSource: ShoulderRotationAssessment.source,
        );
      }
      expect(engine.calibrated, false, reason: label);
      expect(state['form'], 'Waiting', reason: label);
    }
  });

  test('persistent sideways lean fails the repetition', () {
    final driver = _Driver();
    driver.hold(.8, 0, sidewaysLean: 20);
    driver.move(.8, 25, sidewaysLean: 20);
    driver.hold(.3, 25, sidewaysLean: 20);
    driver.move(.8, 0, sidewaysLean: 20);
    driver.hold(.7, 0, sidewaysLean: 20);
    driver.move(.8, -25, sidewaysLean: 20);
    driver.hold(.3, -25, sidewaysLean: 20);
    // The lean prevents calibration entirely, which the report treats as
    // unassessable rather than incorrect.
    expect(driver.engine.calibrated, false);
    expect(driver.engine.repCount, 0);
  });

  test('a brief lean that clears persistence does not fail the repetition', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.move(.8, 25);
    driver.hold(.3, 25);
    driver.move(.4, 0);
    // One short lean excursion, well under 20 percent of the cycle samples.
    // The cycle runs about 50 samples, so a single leaned frame is 2 percent.
    driver.hold(.05, 0, sidewaysLean: 20);
    driver.move(.4, 0);
    driver.hold(.7, 0);
    driver.move(.8, -25);
    driver.hold(.3, -25);
    final rep = driver.completed.single;
    expect(rep['form'], 'correct');
    expect(rep['error_codes'], isEmpty);
    // The single leaned sample is still reported for tuning, but it is below
    // the 20 percent persistence threshold and must not fail the repetition.
    expect(
      rep['form_failures']['TORSO_SIDEWAYS_LEAN'],
      lessThan(ShoulderRotationAssessment.failurePersistenceFraction),
    );
  });

  test('a sustained lean inside the cycle is recorded as a form failure', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.move(.8, 25);
    driver.hold(.3, 25);
    driver.move(.4, 0);
    driver.hold(.6, 0, sidewaysLean: 20);
    driver.move(.4, 0);
    driver.move(.8, -25);
    driver.hold(.3, -25);
    final rep = driver.completed.single;
    expect(rep['form'], 'incorrect');
    expect(rep['error_codes'], contains('TORSO_SIDEWAYS_LEAN'));
    expect(
      rep['form_failures']['TORSO_SIDEWAYS_LEAN'],
      greaterThanOrEqualTo(
        ShoulderRotationAssessment.failurePersistenceFraction,
      ),
    );
    expect(rep['incorrect_step'], 'ROTATING');
    expect(rep['score'], lessThanOrEqualTo(60));
  });

  test('missing world landmarks stop assessment without falling back', () {
    for (final (label, world, source) in [
      ('null world', null, ShoulderRotationAssessment.source),
      ('null world with image source', null, 'pose_landmarks'),
      ('world but image source', _world(), 'pose_landmarks'),
      ('world but mlkit source', _world(), 'mlkit'),
      ('world but no source', _world(), null),
    ]) {
      final engine = ShoulderRotationAssessment();
      final state = engine.update(
        _image(),
        480,
        640,
        0,
        worldLandmarks: world,
        angleSource: source,
      );
      expect(state['tracking_valid'], false, reason: label);
      expect(state['form'], 'Waiting', reason: label);
      expect(state['rep_count'], 0, reason: label);
      expect(state['landmarks'], hasLength(33), reason: label);
    }
  });

  test('low visibility, non-finite and short landmark lists are rejected', () {
    final cases = <List<Map<String, dynamic>>>[];
    for (final field in ['x', 'y', 'z', 'visibility']) {
      for (final value in [null, 'bad', double.nan, double.infinity]) {
        final points = _world();
        points[15][field] = value;
        cases.add(points);
      }
    }
    for (final value in [.0, .3, .49]) {
      final points = _world();
      points[12]['visibility'] = value;
      cases.add(points);
    }
    cases.add(_world().take(20).toList());
    for (final points in cases) {
      final engine = ShoulderRotationAssessment();
      final state = engine.update(
        _image(),
        480,
        640,
        0,
        worldLandmarks: points,
        angleSource: ShoulderRotationAssessment.source,
      );
      expect(state['tracking_valid'], false);
      expect(state['angle'], isNull);
    }
  });

  test('invalid dimensions and backward timestamps are rejected', () {
    for (final (width, height) in [
      (0.0, 640.0),
      (-1.0, 640.0),
      (480.0, 0.0),
      (double.nan, 640.0),
    ]) {
      final state = ShoulderRotationAssessment().update(
        _image(),
        width,
        height,
        0,
        worldLandmarks: _world(),
        angleSource: ShoulderRotationAssessment.source,
      );
      expect(state['tracking_valid'], false);
    }
    final engine = ShoulderRotationAssessment();
    engine.update(
      _image(),
      480,
      640,
      1,
      worldLandmarks: _world(),
      angleSource: ShoulderRotationAssessment.source,
    );
    final backward = engine.update(
      _image(),
      480,
      640,
      1,
      worldLandmarks: _world(),
      angleSource: ShoulderRotationAssessment.source,
    );
    expect(backward['tracking_valid'], false);
  });

  test('a tracking gap discards the partial sequence and needs centre', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    driver.move(.8, 25);
    driver.hold(.3, 25);
    // A long gap: the incomplete cycle must not be completed on return.
    driver.time += 2;
    driver.sample(25);
    expect(driver.engine.stage, 'NEED_CENTRE');
    driver.move(.8, 0);
    driver.hold(.7, 0);
    expect(driver.engine.repCount, 0);
    expect(driver.engine.stage, 'CENTRE');
    // The abandoned cycle cannot be salvaged by finishing the opposite side.
    // A repetition needs a full centre -> extreme -> centre -> opposite sweep
    // from the new centre, so the -25 excursion alone does not count either.
    driver.move(.8, -25);
    driver.hold(.3, -25);
    expect(driver.engine.repCount, 0);
    driver.move(.8, 0);
    driver.hold(.7, 0);
    driver.move(.8, 25);
    driver.hold(.3, 25);
    expect(driver.engine.repCount, 1);
    expect(driver.completed.single['form'], 'correct');
  });

  test('reset clears counts only when asked', () {
    final driver = _Driver()..cycle();
    expect(driver.engine.repCount, 1);
    driver.engine.resetTracking();
    expect(driver.engine.repCount, 1);
    expect(driver.engine.correctCount, 1);
    expect(driver.engine.calibrated, false);
    expect(driver.engine.stage, 'POSITIONING');
  });

  test('elapsed time rather than sample count drives the holds', () {
    for (final cadence in [.016, .05, .1, .2]) {
      final driver = _Driver(cadence: cadence)..cycle();
      expect(driver.engine.repCount, 1, reason: 'cadence $cadence');
    }
  });

  test('the forearm azimuth is torso relative and sign aligned', () {
    // Same-side wand movement must give both hands the same sign. Calibrate
    // first: before calibration there is no baseline, so no deviation exists.
    final driver = _Driver();
    driver.hold(.8, 0);
    final neutral = driver.sample(0);
    expect(neutral['left_angle'], closeTo(0, 1));
    expect(neutral['right_angle'], closeTo(0, 1));
    final moved = driver.sample(30);
    final left = moved['left_angle'] as double;
    final right = moved['right_angle'] as double;
    expect(left.sign, right.sign);
    expect(left.abs(), greaterThan(10));
    expect(right.abs(), greaterThan(10));
  });

  test('opposite-side wand movement flips both hands together', () {
    final driver = _Driver();
    driver.hold(.8, 0);
    final positive = driver.sample(30);
    final negative = driver.sample(-30);
    final positiveLeft = positive['left_angle'] as double;
    final positiveRight = positive['right_angle'] as double;
    final negativeLeft = negative['left_angle'] as double;
    final negativeRight = negative['right_angle'] as double;
    expect(positiveLeft.sign, isNot(negativeLeft.sign));
    expect(positiveRight.sign, isNot(negativeRight.sign));
    expect(positiveLeft.sign, positiveRight.sign);
    expect(negativeLeft.sign, negativeRight.sign);
  });

  test('score stays descriptive and never claims clinical validation', () {
    final driver = _Driver()..cycle();
    final rep = driver.completed.single;
    expect(rep['score_kind'], 'descriptive_movement_quality');
    expect(rep['clinically_validated'], false);
    expect(rep['experimental'], true);
    expect(
      rep['limitations'],
      contains('not direct anatomical shoulder rotation'),
    );
    expect(rep['score'], inInclusiveRange(0, 100));
  });
}

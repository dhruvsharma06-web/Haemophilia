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
    final angle = side == 1 && !rightArmFollows ? rotation : rotation;
    // Forearm length grows from the elbow, pointing forward (-z) at neutral
    // and swinging in the horizontal plane as the wand rotates.
    final fore = math.sin(bend) * .28;
    put(
      wrist,
      ex + math.sin(angle) * fore,
      ey + math.cos(bend) * .28,
      -math.cos(angle) * fore,
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
    'x': shoulderMidX - .10,
    'y': .35,
    'z': 0.0,
    'visibility': .99,
  };
  points[12] = {
    'x': shoulderMidX + .10,
    'y': .35,
    'z': 0.0,
    'visibility': .99,
  };
  points[13] = {'x': .38, 'y': .55, 'z': 0.0, 'visibility': .99};
  points[14] = {'x': .62, 'y': .55, 'z': 0.0, 'visibility': .99};
  final shift = rotationDegrees / 1000;
  final tilt = wandTilt / 1000;
  points[15] = {'x': .40 + shift, 'y': .62 + tilt, 'z': 0.0, 'visibility': .99};
  points[16] = {'x': .60 + shift, 'y': .62 - tilt, 'z': 0.0, 'visibility': .99};
  return points;
}

class _Driver {
  final engine = ShoulderRotationAssessment();
  final double cadence;
  double time = 0;
  double rotation = 0;
  Map<String, dynamic> state = {};
  final List<Map<String, dynamic>> completed = [];

  _Driver({this.cadence = .05});

  Map<String, dynamic> sample(
    double nextRotation, {
    bool image = true,
    double sidewaysLean = 0,
    double wandTilt = 0,
    double elbowBend = 90,
    double upperArmOffset = 0,
  }) {
    time += cadence;
    rotation = nextRotation;
    state = engine.update(
      _image(
        rotationDegrees: image ? nextRotation / 40 : 0,
        sidewaysLean: sidewaysLean,
        wandTilt: wandTilt,
      ),
      480,
      640,
      time,
      worldLandmarks: _world(
        rotationDegrees: nextRotation,
        elbowBend: elbowBend,
        upperArmOffset: upperArmOffset,
        sidewaysLean: sidewaysLean,
      ),
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
    expect(ShoulderRotationAssessment.visibilityMin, .7);
    expect(
      ShoulderRotationAssessment.provenance,
      'proposed_engineering_settings',
    );
    expect(ShoulderRotationAssessment.thresholds['elbow_bend']['status'], 'existing');
    expect(
      ShoulderRotationAssessment.thresholds['torso_sideways_lean']['status'],
      'existing',
    );
    expect(ShoulderRotationAssessment.thresholds['torso_twist']['status'], 'proposed');
    expect(
      ShoulderRotationAssessment.thresholdSummary,
      allOf(contains('60-120'), contains('Proposed engineering settings')),
    );
    expect(() => jsonEncode(ShoulderRotationAssessment.thresholds), returnsNormally);
  });

  test('bundled calibration file matches the engine constants', () {
    final reference =
        jsonDecode(File('../docs/calibration/shoulder-rotation.json').readAsStringSync())
            as Map;
    expect(ShoulderRotationAssessment.thresholds, reference['thresholds']);
    expect(ShoulderRotationAssessment.provenance, reference['status']);
    expect(ShoulderRotationAssessment.source, reference['angle_source']);
    expect(
      reference['provenance_notes'],
      contains('not degrees'),
    );
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
      greaterThanOrEqualTo(ShoulderRotationAssessment.failurePersistenceFraction),
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
    for (final value in [.0, .3, .69]) {
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
    expect(rep['limitations'], contains('not direct anatomical shoulder rotation'));
    expect(rep['score'], inInclusiveRange(0, 100));
  });
}

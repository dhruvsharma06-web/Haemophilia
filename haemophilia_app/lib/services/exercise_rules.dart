import 'dart:math' as math;

import '../utils/exercise_utils.dart';

/// Camera measurements and provisional assessment presets, not clinical prescriptions.
class ExerciseRule {
  final String id, joint, outwardStage, returnStage, cameraView;
  final double start, enter, target, minimumRom, returnBand;
  final bool increasing, relative;
  static const readyHoldSeconds = .3;
  static const targetHoldSeconds = .2;
  static const returnHoldSeconds = .2;
  static const errorHoldSeconds = .3;
  static const angleMargin = 2.0;
  static const minimumCycleSeconds = 1.0;
  static const reversalDegrees = 8.0;
  static const reversalHoldSeconds = .18;
  const ExerciseRule(
    this.id,
    this.joint,
    this.start,
    this.enter,
    this.target, {
    this.increasing = false,
    this.relative = false,
    this.minimumRom = 15,
    this.returnBand = 10,
    this.outwardStage = 'BENDING',
    this.returnStage = 'RETURNING',
    this.cameraView = 'Side view',
  });

  String get thresholdSummary {
    final startSign = increasing ? '≤' : '≥';
    final targetSign = increasing ? '≥' : '≤';
    if (relative) {
      return '$joint: movement ≥${target.toStringAsFixed(0)}° from your start; return within ${returnBand.toStringAsFixed(0)}°.';
    }
    return '$joint: start $startSign${start.toStringAsFixed(0)}° → target $targetSign${target.toStringAsFixed(0)}° → return $startSign${start.toStringAsFixed(0)}°.';
  }

  static const catalog = <ExerciseRule>[
    ExerciseRule(
      kAssistedShoulderFlexion,
      'Shoulder elevation',
      40,
      50,
      150,
      increasing: true,
      minimumRom: 75,
      outwardStage: 'RAISING',
      returnStage: 'LOWERING',
      cameraView: 'Front view',
    ),
    // Relative camera azimuth is a movement proxy, not clinical axial rotation.
    ExerciseRule(
      kShoulderRotation,
      'Forearm rotation',
      8,
      10,
      20,
      increasing: true,
      relative: true,
      returnBand: 4,
      outwardStage: 'ROTATING_OUT',
      returnStage: 'ROTATING_IN',
      cameraView: 'Front view',
    ),
    ExerciseRule(
      kAssistedElbowFlexionV5,
      'Elbow angle',
      150,
      140,
      90,
      minimumRom: 50,
      returnBand: 8,
      outwardStage: 'FLEXING',
      returnStage: 'EXTENDING',
      cameraView: 'Front view',
    ),
    ExerciseRule(
      kElbowFlexionExtension,
      'Elbow angle',
      155,
      145,
      90,
      minimumRom: 50,
      returnBand: 8,
      outwardStage: 'FLEXING',
      returnStage: 'EXTENDING',
      cameraView: 'Front oblique view',
    ),
    ExerciseRule(kHeelSlide, 'Knee angle', 170, 150, 90),
    ExerciseRule(
      kMiniSquat,
      'Knee angle',
      165,
      150,
      130,
      returnBand: 8,
      outwardStage: 'LOWERING',
      returnStage: 'RISING',
      cameraView: 'Front or side view',
    ),
    ExerciseRule(
      kSeatedKneeExtension,
      'Knee angle',
      95,
      100,
      160,
      increasing: true,
      outwardStage: 'EXTENDING',
      returnStage: 'BENDING',
    ),
    ExerciseRule(
      kStraightLegRaise,
      'Hip angle',
      172,
      165,
      140,
      outwardStage: 'RAISING',
      returnStage: 'LOWERING',
    ),
    ExerciseRule(
      kTerminalKneeExtension,
      'Knee angle',
      145,
      155,
      170,
      increasing: true,
      returnBand: 6,
      outwardStage: 'EXTENDING',
      returnStage: 'BENDING',
    ),
    ExerciseRule(
      kSquat,
      'Knee angle',
      155,
      145,
      120,
      outwardStage: 'LOWERING',
      returnStage: 'RISING',
      cameraView: 'Front or side view',
    ),
  ];

  static ExerciseRule forExercise(String name) {
    final id = normalizeExerciseId(name);
    return catalog.firstWhere(
      (rule) => rule.id == id,
      orElse: () =>
          throw StateError('This exercise has no on-device assessment rules.'),
    );
  }

  bool get usesBothArms => [
    kAssistedShoulderFlexion,
    kShoulderRotation,
    kElbowFlexionExtension,
  ].contains(id);

  List<String> get postureGuidance => switch (id) {
    kAssistedShoulderFlexion => [
      'Raise both arms evenly.',
      'Keep your torso steady.',
    ],
    kShoulderRotation => [
      'Keep both elbows bent near 90 degrees.',
      'Keep your elbows beside your torso.',
    ],
    kAssistedElbowFlexionV5 => [
      'Support the working forearm with your opposite hand.',
      'Keep the working elbow close to your torso.',
    ],
    kElbowFlexionExtension => [
      'Bend and straighten both elbows together.',
      'Keep both upper arms beside your torso.',
    ],
    kStraightLegRaise => ['Keep the lifting knee straight.'],
    kSeatedKneeExtension => ['Sit upright without rocking your torso.'],
    kTerminalKneeExtension => ['Keep your thigh resting on the support.'],
    kHeelSlide => [
      'Keep your heel on the surface.',
      'Keep your hip on the support surface.',
    ],
    _ => [
      'Keep your knees aligned with your feet.',
      'Keep your heel on the surface.',
    ],
  };
}

class _Point {
  final double x, y, z, visibility;
  const _Point(this.x, this.y, this.z, this.visibility);
  double distance(_Point other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));
}

/// Complete cycles with hysteresis, timed holds and loss-of-tracking guards.
/// Pure Dart: no trained form classifier, network, image conversion or file writes.
class ExerciseRulesAssessment {
  final ExerciseRule rule;
  String hand;
  String stage = 'POSITIONING';
  int repCount = 0, correctCount = 0;
  double? _lastTime, _readySince, _onsetSince, _returnSince, _startedAt;
  double? _targetSince,
      _finishSince,
      _shortReturnSince,
      _filteredLeft,
      _filteredRight;
  double _assessedSeconds = 0, _postureErrorSeconds = 0;
  double? _leftPeak, _rightPeak;
  String? _incorrectStep;
  double? _baseline,
      _best,
      _lastAngle,
      _baselineTilt,
      _baselineHipY,
      _baselineHeelY,
      _baselineThigh;
  double? _leftRotationBaseline, _rightRotationBaseline;
  bool _armed = false, _targetReached = false;
  final List<(double, double)> _trace = [];
  final Map<String, double> _errorSince = {};
  final Set<String> _errors = {};
  double? _frameWidth, _frameHeight;
  Map<String, dynamic> _lastResult = {};

  ExerciseRulesAssessment(String exercise, {this.hand = 'Left'})
    : rule = ExerciseRule.forExercise(exercise);

  void resetTracking() {
    stage = 'POSITIONING';
    _armed = false;
    _readySince = null;
    _onsetSince = null;
    _returnSince = null;
    _targetSince = null;
    _finishSince = null;
    _shortReturnSince = null;
    _filteredLeft = null;
    _filteredRight = null;
    _assessedSeconds = 0;
    _postureErrorSeconds = 0;
    _leftPeak = null;
    _rightPeak = null;
    _incorrectStep = null;
    _startedAt = null;
    _baseline = null;
    _best = null;
    _lastAngle = null;
    _leftRotationBaseline = null;
    _rightRotationBaseline = null;
    _baselineTilt = null;
    _baselineHipY = null;
    _baselineHeelY = null;
    _baselineThigh = null;
    _trace.clear();
    _errors.clear();
    _errorSince.clear();
    _targetReached = false;
    _lastTime = null;
  }

  static double? angle(List<double> a, List<double> b, List<double> c) {
    final ax = a[0] - b[0],
        ay = a[1] - b[1],
        bx = c[0] - b[0],
        by = c[1] - b[1];
    final denominator = math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by));
    if (!denominator.isFinite || denominator < 1e-5) return null;
    return math.acos(((ax * bx + ay * by) / denominator).clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }

  Map<String, dynamic> update(
    List<Map<String, dynamic>> landmarks,
    double width,
    double height,
    double time,
  ) {
    if (!time.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      resetTracking();
      return _state([], null, 'Show your joints clearly.');
    }
    if (_frameWidth != width || _frameHeight != height) resetTracking();
    _frameWidth = width;
    _frameHeight = height;
    if (_lastTime != null && (time <= _lastTime! || time - _lastTime! > .75)) {
      resetTracking();
    }
    final dt = _lastTime == null ? .08 : (time - _lastTime!).clamp(.001, .2);
    _lastTime = time;
    final points = <_Point>[];
    for (final value in landmarks) {
      double number(String key) =>
          value[key] is num ? (value[key] as num).toDouble() : double.nan;
      points.add(
        _Point(
          number('x') * width,
          number('y') * height,
          number('z') * width,
          number('visibility'),
        ),
      );
    }
    bool visible(int id) =>
        id < points.length &&
        points[id].visibility >= .55 &&
        points[id].x.isFinite &&
        points[id].y.isFinite &&
        points[id].x >= 0 &&
        points[id].x <= width &&
        points[id].y >= 0 &&
        points[id].y <= height;
    double? joint(int a, int b, int c) => [a, b, c].every(visible)
        ? angle([points[a].x, points[a].y], [points[b].x, points[b].y], [
            points[c].x,
            points[c].y,
          ])
        : null;
    double? elbowAngle(int a, int b, int c) {
      if (![a, b, c].every(visible)) return null;
      final p = points[a], q = points[b], r = points[c];
      if (![p.z, q.z, r.z].every((v) => v.isFinite)) return null;
      final ux = p.x - q.x, uy = p.y - q.y, uz = p.z - q.z;
      final vx = r.x - q.x, vy = r.y - q.y, vz = r.z - q.z;
      final length = math.sqrt(
        (ux * ux + uy * uy + uz * uz) * (vx * vx + vy * vy + vz * vz),
      );
      if (length < 1e-5 || !length.isFinite) return null;
      return math.acos(
            ((ux * vx + uy * vy + uz * vz) / length).clamp(-1.0, 1.0),
          ) *
          180 /
          math.pi;
    }

    final upper = [
      kAssistedShoulderFlexion,
      kAssistedElbowFlexionV5,
      kElbowFlexionExtension,
      kShoulderRotation,
    ].contains(rule.id);
    final bilateral = rule.usesBothArms;
    final activeRight = rule.id == kAssistedElbowFlexionV5 && hand == 'Right';
    final sh = activeRight ? 12 : 11,
        el = activeRight ? 14 : 13,
        wr = activeRight ? 16 : 15;
    final hip = activeRight ? 24 : 23;
    final required = upper ? <int>[sh, el, wr, hip] : <int>[11, 23, 25, 27];
    if (bilateral || rule.id == kAssistedElbowFlexionV5) {
      required.addAll([11, 12, 13, 14, 15, 16, 23, 24]);
    }
    if (rule.id == kHeelSlide || rule.id == kMiniSquat || rule.id == kSquat) {
      required.add(29);
    }
    if (!required.every(visible)) {
      resetTracking();
      return _state(
        [],
        null,
        'Show the required joints clearly, then return to the starting position.',
      );
    }
    double? leftAngle, rightAngle, driver;
    if (rule.id == kAssistedShoulderFlexion) {
      leftAngle = joint(23, 11, 13);
      rightAngle = joint(24, 12, 14);
      if (leftAngle != null && rightAngle != null) {
        driver = (leftAngle + rightAngle) / 2;
      }
    } else if (rule.id == kShoulderRotation) {
      double? azimuth(int e, int w) {
        final x = points[w].x - points[e].x, z = points[w].z - points[e].z;
        if (!z.isFinite || math.sqrt(x * x + z * z) < 1e-5) return null;
        return math.atan2(x, -z) * 180 / math.pi;
      }

      final left = azimuth(13, 15), right = azimuth(14, 16);
      if (left != null && right != null) {
        _leftRotationBaseline ??= left;
        _rightRotationBaseline ??= right;
        double difference(double a, double b) =>
            ((a - b + 540) % 360 - 180).abs();
        leftAngle = difference(left, _leftRotationBaseline!);
        rightAngle = difference(right, _rightRotationBaseline!);
        driver = (leftAngle + rightAngle) / 2;
      }
    } else if (upper) {
      leftAngle = elbowAngle(11, 13, 15);
      rightAngle = elbowAngle(12, 14, 16);
      driver = rule.id == kElbowFlexionExtension
          ? (leftAngle != null && rightAngle != null
                ? (leftAngle + rightAngle) / 2
                : null)
          : activeRight
          ? rightAngle
          : leftAngle;
    } else {
      leftAngle = rule.id == kStraightLegRaise
          ? joint(11, 23, 25)
          : joint(23, 25, 27);
      rightAngle = rule.id == kStraightLegRaise
          ? joint(12, 24, 26)
          : joint(24, 26, 28);
      driver = leftAngle;
    }
    if (driver == null || !driver.isFinite) {
      resetTracking();
      return _state(
        [],
        null,
        'Joint angle unavailable. Reposition the camera.',
      );
    }
    // A short causal filter suppresses single-frame pose jitter. Targets still
    // need a continuous hold and cannot be satisfied by a brief angle spike.
    final alpha = (1 - math.exp(-dt / .10)).clamp(.15, .85);
    double? filter(double? value, double? previous) => value == null
        ? null
        : previous == null
        ? value
        : previous + alpha * (value - previous);
    leftAngle = filter(leftAngle, _filteredLeft);
    rightAngle = filter(rightAngle, _filteredRight);
    _filteredLeft = leftAngle;
    _filteredRight = rightAngle;
    if (bilateral && leftAngle != null && rightAngle != null) {
      driver = (leftAngle + rightAngle) / 2;
    } else if (upper) {
      driver = activeRight ? rightAngle : leftAngle;
    } else {
      driver = leftAngle;
    }
    final angleNow = driver!;
    final torso = points[sh].distance(points[hip]);
    if (torso < 20) {
      resetTracking();
      return _state([], null, 'Move closer so your joints can be tracked.');
    }
    final tilt =
        math.atan2(points[sh].x - points[hip].x, points[hip].y - points[sh].y) *
        180 /
        math.pi;
    final atRest = bilateral
        ? rule.increasing
              ? math.max(leftAngle!, rightAngle!) <=
                    rule.start + ExerciseRule.angleMargin
              : math.min(leftAngle!, rightAngle!) >=
                    rule.start - ExerciseRule.angleMargin
        : rule.relative
        ? angleNow.abs() <= rule.start + ExerciseRule.angleMargin
        : rule.increasing
        ? angleNow <= rule.start + ExerciseRule.angleMargin
        : angleNow >= rule.start - ExerciseRule.angleMargin;
    final entering =
        _armed &&
        (rule.relative
            ? angleNow.abs() >= 8
            : _baseline != null && (angleNow - _baseline!).abs() >= 8);
    final reached = bilateral
        ? rule.increasing
              ? math.min(leftAngle!, rightAngle!) >=
                    rule.target - ExerciseRule.angleMargin
              : math.max(leftAngle!, rightAngle!) <=
                    rule.target + ExerciseRule.angleMargin
        : rule.increasing
        ? angleNow >= rule.target - ExerciseRule.angleMargin
        : angleNow <= rule.target + ExerciseRule.angleMargin;
    final active = _startedAt != null;
    final alerts = <String>[];
    if (upper &&
        _baselineTilt != null &&
        (tilt - _baselineTilt!).abs() >
            (rule.id == kAssistedShoulderFlexion ? 8 : 12)) {
      alerts.add('Keep your torso steady.');
    }
    if (rule.id == kAssistedShoulderFlexion &&
        leftAngle != null &&
        rightAngle != null &&
        (leftAngle - rightAngle).abs() > 18) {
      alerts.add('Raise both arms evenly.');
    }
    if (rule.id == kElbowFlexionExtension) {
      if ((leftAngle! - rightAngle!).abs() > 20) {
        alerts.add('Bend and straighten both elbows together.');
      }
      if ((joint(23, 11, 13) ?? 180) > 35 || (joint(24, 12, 14) ?? 180) > 35) {
        alerts.add('Keep both upper arms beside your torso.');
      }
    }
    if (rule.id == kShoulderRotation) {
      final le = elbowAngle(11, 13, 15), re = elbowAngle(12, 14, 16);
      if (le == null ||
          re == null ||
          le < 70 ||
          le > 110 ||
          re < 70 ||
          re > 110) {
        alerts.add('Keep both elbows bent near 90 degrees.');
      }
      final la = joint(23, 11, 13), ra = joint(24, 12, 14);
      if ((la ?? 180) > 30 || (ra ?? 180) > 30) {
        alerts.add('Keep your elbows beside your torso.');
      }
    }
    if (rule.id == kAssistedElbowFlexionV5) {
      final support = points[activeRight ? 15 : 16];
      final forearm = points[el].distance(points[wr]);
      final midpoint = _Point(
        (points[el].x + points[wr].x) / 2,
        (points[el].y + points[wr].y) / 2,
        0,
        1,
      );
      if (forearm < 15 || support.distance(midpoint) > forearm * .8) {
        alerts.add('Support the working forearm with your opposite hand.');
      }
      if ((joint(hip, sh, el) ?? 180) > 35) {
        alerts.add('Keep the working elbow close to your torso.');
      }
    }
    if (rule.id == kStraightLegRaise && (joint(23, 25, 27) ?? 0) < 160) {
      alerts.add('Keep the lifting knee straight.');
    }
    if (!upper &&
        active &&
        _baselineHipY != null &&
        [
          kHeelSlide,
          kSeatedKneeExtension,
          kTerminalKneeExtension,
        ].contains(rule.id) &&
        (_baselineHipY! - points[23].y) / height > .03) {
      alerts.add('Keep your hip on the support surface.');
    }
    if ([kHeelSlide, kMiniSquat, kSquat].contains(rule.id) &&
        active &&
        _baselineHeelY != null &&
        (_baselineHeelY! - points[29].y) / height > .03) {
      alerts.add('Keep your heel on the surface.');
    }
    if ([kMiniSquat, kSquat].contains(rule.id) &&
        [12, 24, 26, 28].every(visible)) {
      final ankleWidth = (points[27].x - points[28].x).abs();
      final shoulderWidth = (points[11].x - points[12].x).abs();
      if (shoulderWidth > torso * .4 &&
          ankleWidth > 10 &&
          (points[25].x - points[26].x).abs() < ankleWidth * .72) {
        alerts.add('Keep your knees aligned with your feet.');
      }
    }
    if (rule.id == kSeatedKneeExtension &&
        _baselineTilt != null &&
        (tilt - _baselineTilt!).abs() > 20) {
      alerts.add('Sit upright without rocking your torso.');
    }
    if (rule.id == kTerminalKneeExtension && _baselineThigh != null) {
      final thigh =
          math.atan2(points[25].y - points[23].y, points[25].x - points[23].x) *
          180 /
          math.pi;
      if ((thigh - _baselineThigh!).abs() > 15) {
        alerts.add('Keep your thigh resting on the support.');
      }
    }

    Map<String, dynamic>? completed;
    if (!active) {
      if (!_armed && atRest && alerts.isEmpty) {
        if (_lastAngle != null && (angleNow - _lastAngle!).abs() > 5) {
          _readySince = null;
        }
        _readySince ??= time;
        if (time - _readySince! >= ExerciseRule.readyHoldSeconds) {
          _armed = true;
          stage = 'READY';
          if (!rule.relative) _baseline = angleNow;
          _baselineTilt = tilt;
          _baselineHipY = points[hip].y;
          _baselineHeelY = points.length > 29 ? points[29].y : null;
          if (!upper) {
            _baselineThigh =
                math.atan2(
                  points[25].y - points[23].y,
                  points[25].x - points[23].x,
                ) *
                180 /
                math.pi;
          }
        }
      } else if (!_armed) {
        _readySince = null;
        stage = 'POSITIONING';
      }
      final movingWithError =
          _armed &&
          alerts.isNotEmpty &&
          (angleNow - (rule.relative ? 0 : (_baseline ?? angleNow))).abs() >= 3;
      if (_armed && (entering || movingWithError)) {
        _onsetSince ??= time;
        if (time - _onsetSince! >= .1) {
          _startedAt = time;
          _best = angleNow;
          _targetReached = false;
          _errors.clear();
          _errorSince.clear();
          _assessedSeconds = 0;
          _postureErrorSeconds = 0;
          _incorrectStep = null;
          _targetSince = null;
          _finishSince = null;
          _leftPeak = leftAngle;
          _rightPeak = rightAngle;
          _trace
            ..clear()
            ..add((time, rule.relative ? 0 : (_baseline ?? angleNow)))
            ..add((time, angleNow));
          stage = rule.outwardStage;
        }
      } else {
        _onsetSince = null;
        if (_armed) {
          stage = atRest && alerts.isEmpty ? 'READY' : 'POSITIONING';
        }
      }
    } else {
      _trace.add((time, angleNow));
      _assessedSeconds += dt;
      if (alerts.isNotEmpty) _postureErrorSeconds += dt;
      if (leftAngle != null) {
        _leftPeak = _leftPeak == null
            ? leftAngle
            : rule.increasing
            ? math.max(_leftPeak!, leftAngle)
            : math.min(_leftPeak!, leftAngle);
      }
      if (rightAngle != null) {
        _rightPeak = _rightPeak == null
            ? rightAngle
            : rule.increasing
            ? math.max(_rightPeak!, rightAngle)
            : math.min(_rightPeak!, rightAngle);
      }
      if (time - _startedAt! > 45 || _trace.length > 1500) {
        resetTracking();
        return _state(
          landmarks,
          angleNow,
          'Movement timed out. Return to your starting position.',
        );
      }
      _best = rule.increasing
          ? math.max(_best!, angleNow)
          : math.min(_best!, angleNow);
      if (reached) {
        _targetSince ??= time;
        if (time - _targetSince! >= ExerciseRule.targetHoldSeconds) {
          _targetReached = true;
        }
      } else {
        _targetSince = null;
      }
      for (final alert in alerts) {
        _errorSince[alert] ??= time;
        if (time - _errorSince[alert]! >= ExerciseRule.errorHoldSeconds) {
          _recordError(alert);
        }
      }
      _errorSince.removeWhere((key, value) => !alerts.contains(key));
      final reversed = rule.increasing
          ? _best! - angleNow >= ExerciseRule.reversalDegrees
          : angleNow - _best! >= ExerciseRule.reversalDegrees;
      if (reversed) {
        _returnSince ??= time;
      } else {
        _returnSince = null;
      }
      if (_returnSince != null &&
          time - _returnSince! >= ExerciseRule.reversalHoldSeconds) {
        if (!_targetReached) {
          _recordError(
            'Target angle was not held. Reach the shown target before returning.',
          );
        }
        stage = rule.returnStage;
      } else if (_targetReached && stage != rule.returnStage) {
        stage = 'TARGET_REACHED';
      }
      final baseline = rule.relative ? 0.0 : _trace.first.$2;
      final distanceToStart = (angleNow - baseline).abs();
      final bothReturned =
          !bilateral ||
          rule.relative ||
          rule.increasing ||
          math.min(leftAngle!, rightAngle!) >= rule.start;
      final fullyReturned =
          atRest && bothReturned && distanceToStart <= rule.returnBand;
      if (stage == rule.returnStage && fullyReturned) {
        _finishSince ??= time;
      } else {
        _finishSince = null;
      }
      if (stage == rule.returnStage &&
          !fullyReturned &&
          _lastAngle != null &&
          (angleNow - _lastAngle!).abs() / dt < 5) {
        _shortReturnSince ??= time;
        if (time - _shortReturnSince! > 2) {
          _recordError(
            'Return is incomplete. Move back to your starting angle.',
          );
        }
      } else {
        _shortReturnSince = null;
      }
      if (_finishSince != null &&
          time - _finishSince! >= ExerciseRule.returnHoldSeconds) {
        final duration = time - _startedAt!;
        final rom = (_best! - baseline).abs();
        if (duration >= .4 && rom >= 10 && _trace.length >= 6) {
          if (!_targetReached || rom < rule.minimumRom) {
            _recordError(
              'Target range not reached. Follow your prescribed comfortable range.',
            );
          }
          if (duration < ExerciseRule.minimumCycleSeconds) {
            _recordError('Move more slowly and with control.');
          }
          final returned = rom > 0
              ? (100 * (1 - math.max(0, (angleNow - baseline).abs() - 3) / rom))
                    .clamp(0.0, 100.0)
              : 0.0;
          double travel = 0;
          for (var i = 1; i < _trace.length; i++) {
            travel += (_trace[i].$2 - _trace[i - 1].$2).abs();
          }
          final smoothness = travel > 0
              ? (100 * (2 * rom - distanceToStart) / travel).clamp(0.0, 100.0)
              : 0.0;
          final good = _errors.isEmpty;
          final neededRom = math.max(
            rule.minimumRom,
            (rule.target - baseline).abs(),
          );
          final rangeScore = math
              .min(_targetReached ? 100.0 : 90.0, 100 * rom / neededRom)
              .clamp(0.0, 100.0);
          final postureErrors = _errors
              .where(
                (e) => ![
                  'TARGET_NOT_HELD',
                  'INSUFFICIENT_ROM',
                  'INCOMPLETE_RETURN',
                  'TOO_FAST',
                ].contains(_errorCode(e)),
              )
              .length;
          final postureScore =
              (100 -
                      math.min(
                        75,
                        100 *
                                _postureErrorSeconds /
                                math.max(.01, _assessedSeconds) +
                            12 * postureErrors,
                      ))
                  .clamp(0.0, 100.0);
          final paceScore = duration < 1
              ? 40.0
              : duration < 2
              ? 70 + 30 * (duration - 1)
              : duration <= 6
              ? 100.0
              : math.max(65.0, 100 - (duration - 6) * 5);
          final formScore = .75 * postureScore + .25 * returned;
          var score = .45 * formScore + .35 * rangeScore + .20 * paceScore;
          if (!good) score = math.min(score, _targetReached ? 55.0 : 50.0);
          repCount++;
          if (good) correctCount++;
          final resultFeedback = good
              ? score >= 90
                    ? 'Good repetition. Target held, posture steady, and return completed.'
                    : 'Target and return completed. Keep a steady pace for better control.'
              : _errors.first;
          completed = {
            'rep_index': repCount,
            'exercise': rule.id,
            'form': good ? 'correct' : 'incorrect',
            'score': score.clamp(0.0, 100.0),
            'score_kind': 'descriptive_movement_quality',
            'score_components': {
              'range': rangeScore,
              'posture': postureScore,
              'pace': paceScore,
              'return': returned,
              'weights': {'form': .45, 'range': .35, 'pace': .20},
            },
            'range_of_motion': rom,
            'duration': duration,
            'speed': duration < 1
                ? 'Fast'
                : duration > 8
                ? 'Slow'
                : 'Controlled',
            'smoothness': smoothness,
            'minimum_angle': _trace.map((e) => e.$2).reduce(math.min),
            'maximum_angle': _trace.map((e) => e.$2).reduce(math.max),
            'return_completion': returned,
            'angular_speed': travel / duration,
            'feedback': resultFeedback,
            'feedback_details': _errors.toList(),
            'error_type': good ? '' : _errorCode(_errors.first),
            'error_codes': _errors.map(_errorCode).toList(),
            'incorrect_step': _incorrectStep,
            'target_reached': _targetReached,
            'required_target': rule.target,
            'left_peak_angle': _leftPeak,
            'right_peak_angle': _rightPeak,
            'hand': upper
                ? (bilateral
                      ? 'Both'
                      : activeRight
                      ? 'Right'
                      : 'Left')
                : 'Left',
            'model_identity': 'On-device joint tracking + angle rules',
            'model_version': 'OnDeviceRules_v2',
            'assessment_method': 'on_device_angle_rules',
            'experimental': true,
            'clinically_validated': false,
            'thresholds': {
              'start': rule.start,
              'enter': rule.enter,
              'target': rule.target,
              'relative': rule.relative,
              'targetHoldSeconds': ExerciseRule.targetHoldSeconds,
              'returnHoldSeconds': ExerciseRule.returnHoldSeconds,
              'returnTolerance': rule.returnBand,
            },
            'angle_trace': [
              for (
                var i = 0;
                i < _trace.length;
                i += math.max(1, (_trace.length / 60).ceil())
              )
                {'seconds': _trace[i].$1 - _startedAt!, 'angle': _trace[i].$2},
            ],
          };
          _lastResult = completed;
          if (good && rule.id == kAssistedElbowFlexionV5) {
            hand = hand == 'Left' ? 'Right' : 'Left';
          }
        }
        resetTracking();
      }
    }
    _lastAngle = angleNow;
    final feedback = completed != null
        ? completed['feedback'] as String
        : _errors.isNotEmpty
        ? _errors.first
        : alerts.isNotEmpty
        ? alerts.first
        : stage == 'POSITIONING'
        ? 'Return to the starting position and keep the joints visible.'
        : stage == 'READY'
        ? 'Begin slowly within your comfortable range.'
        : stage == rule.returnStage
        ? 'Return smoothly to your starting position.'
        : 'Move smoothly toward the target angle.';
    final result = _state(landmarks, angleNow, feedback);
    if (completed != null) {
      result['form'] = completed['form'];
      result['error_type'] = completed['error_type'];
      result['incorrect_step'] = completed['incorrect_step'];
      result['target_reached'] = completed['target_reached'];
    }
    return {
      ...result,
      'left_angle': leftAngle,
      'right_angle': rightAngle,
      'completed_rep': ?completed,
    };
  }

  void _recordError(String feedback) {
    _incorrectStep ??= stage;
    _errors.add(feedback);
  }

  static String _errorCode(String feedback) => switch (feedback) {
    'Target angle was not held. Reach the shown target before returning.' =>
      'TARGET_NOT_HELD',
    'Target range not reached. Follow your prescribed comfortable range.' =>
      'INSUFFICIENT_ROM',
    'Return is incomplete. Move back to your starting angle.' =>
      'INCOMPLETE_RETURN',
    'Move more slowly and with control.' => 'TOO_FAST',
    'Keep your torso steady.' ||
    'Sit upright without rocking your torso.' => 'BODY_TILT',
    'Raise both arms evenly.' ||
    'Bend and straighten both elbows together.' => 'ARM_ASYMMETRY',
    'Keep both upper arms beside your torso.' => 'UPPER_ARM_POSITION',
    'Support the working forearm with your opposite hand.' => 'SUPPORT_MISSING',
    'Keep the working elbow close to your torso.' ||
    'Keep your elbows beside your torso.' => 'ELBOW_FLARE',
    'Keep both elbows bent near 90 degrees.' => 'ELBOW_POSITION',
    'Keep the lifting knee straight.' => 'KNEE_BENT',
    'Keep your hip on the support surface.' => 'HIP_LIFT',
    'Keep your heel on the surface.' => 'HEEL_LIFT',
    'Keep your knees aligned with your feet.' => 'KNEE_ALIGNMENT',
    'Keep your thigh resting on the support.' => 'THIGH_MOVEMENT',
    _ => 'MOVEMENT_RULE',
  };

  Map<String, dynamic> _state(
    List<Map<String, dynamic>> landmarks,
    double? angle,
    String feedback,
  ) => {
    'type': 'live_state',
    'exercise': rule.id,
    'landmarks': landmarks,
    'state': stage,
    'expected_hand': rule.id == kAssistedElbowFlexionV5
        ? hand
        : rule.usesBothArms
        ? 'Both'
        : 'Left',
    'angle': angle,
    'rep_count': repCount,
    'correct_reps': correctCount,
    'form': _errors.isNotEmpty
        ? 'incorrect'
        : stage == 'POSITIONING'
        ? 'Waiting'
        : stage,
    'feedback': feedback,
    'error_type': _errors.isEmpty ? '' : _errorCode(_errors.first),
    'incorrect_step': _incorrectStep,
    'target_reached': _targetReached,
    'required_target': rule.target,
    'target_hold_progress': _targetReached
        ? 1.0
        : _targetSince == null
        ? 0.0
        : (((_lastTime ?? _targetSince!) - _targetSince!) /
                  ExerciseRule.targetHoldSeconds)
              .clamp(0.0, 1.0),
    'range_of_motion': _best == null
        ? 0
        : (_best! - (rule.relative ? 0 : (_baseline ?? _best!))).abs(),
    'duration': _startedAt == null
        ? null
        : (_lastTime ?? _startedAt!) - _startedAt!,
    'score': _lastResult['score'],
    'score_kind': 'descriptive_movement_quality',
    'score_components': _lastResult['score_components'],
    'smoothness': _lastResult['smoothness'],
    'return_completion': _lastResult['return_completion'],
    'speed': _lastResult['speed'] ?? 'Waiting',
    'tracking_valid': angle != null,
    'threshold_summary': rule.thresholdSummary,
    'camera_view': rule.cameraView,
    'assessment_method': 'on_device_angle_rules',
    'clinically_validated': false,
  };
}

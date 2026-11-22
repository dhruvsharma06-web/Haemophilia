import 'dart:math' as math;

import '../utils/exercise_utils.dart';
import 'elbow_world_assessment.dart';
import 'patient_calibration.dart';
import 'shoulder_rotation_assessment.dart';

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

  /// The same rule with a patient-specific target (see PatientCalibration).
  ExerciseRule withTarget(double newTarget, double newMinimumRom) =>
      ExerciseRule(
        id,
        joint,
        start,
        enter,
        newTarget,
        increasing: increasing,
        relative: relative,
        minimumRom: newMinimumRom,
        returnBand: returnBand,
        outwardStage: outwardStage,
        returnStage: returnStage,
        cameraView: cameraView,
      );

  String get thresholdSummary {
    if (id == kElbowFlexionExtension) {
      return ElbowWorldAssessment.thresholdSummary;
    }
    if (id == kShoulderRotation) {
      return ShoulderRotationAssessment.appThresholdSummary;
    }
    if (id == kAssistedElbowFlexionV5) {
      return 'Hold a comfortable, steady starting position. Bend to the shown '
          'target (<=${target.toStringAsFixed(0)} degrees), then return within '
          '${returnBand.toStringAsFixed(0)} degrees of your own start. '
          'Support the working forearm with the opposite hand.';
    }
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
      ShoulderRotationAssessment.appReturnBandDegrees,
      ShoulderRotationAssessment.appOnsetDegrees,
      ShoulderRotationAssessment.extremeDegrees,
      increasing: true,
      relative: true,
      returnBand: ShoulderRotationAssessment.appReturnBandDegrees,
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
      ElbowWorldAssessment.rightExtensionMin,
      145,
      ElbowWorldAssessment.leftFlexionMax,
      minimumRom: ElbowWorldAssessment.leftRomMin,
      returnBand: ElbowWorldAssessment.leftReturnErrorMax,
      outwardStage: 'FLEXING',
      returnStage: 'EXTENDING',
      cameraView: 'Front oblique view',
    ),
    // Lower-body display targets follow codex/lower-body-integration's
    // backend/app/config/exercises.json. These remain provisional camera
    // measurements rather than prescribed range-of-motion limits.
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
      cameraView: 'Side view',
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
    // The source squat config enters at 105 degrees but targets 120 degrees:
    // that starts the rep after the target was crossed. Retain the working
    // 145-degree onset while using its 155-degree return and 120-degree target.
    ExerciseRule(
      kSquat,
      'Knee angle',
      155,
      145,
      120,
      outwardStage: 'LOWERING',
      returnStage: 'RISING',
      cameraView: 'Side view',
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
  bool get isUpperBody => [
    kAssistedShoulderFlexion,
    kAssistedElbowFlexionV5,
    kElbowFlexionExtension,
    kShoulderRotation,
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
  final ElbowWorldAssessment _elbowWorld = ElbowWorldAssessment();
  final ShoulderRotationAssessment _shoulderRotation =
      ShoulderRotationAssessment(bilateralExternal: true, autoProtocol: true);
  final ExerciseRule rule;
  String hand;
  String _leg = 'Left';
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
      _baselineLeft,
      _baselineRight,
      _best,
      _lastAngle,
      _baselineTilt,
      _baselineHipY,
      _baselineHeelY,
      _baselineThigh;
  double? _leftRotationBaseline, _rightRotationBaseline;
  bool _armed = false, _targetReached = false;
  bool _currentAlert = false;
  final List<(double, double)> _trace = [];
  final Map<String, double> _errorSince = {};
  double? _supportDistanceRatio, _supportContactRatio, _lastRepTime;
  bool _assistedWorld = false, _supportHeld = false;
  double? _supportEnterSince, _supportExitSince, _roleSwapSince;
  double _supportObservedSeconds = 0, _supportAssessedSeconds = 0;
  final Map<String, double> _armRestAngles = {}, _armRestSince = {};
  final Set<String> _errors = {};
  final Map<String, Map<String, double>> _readyLegs = {};
  double? _frameWidth, _frameHeight;
  Map<String, dynamic> _lastResult = {};

  /// Patient-specific target in use, or null for the standard rule.
  final CalibrationResult? calibration;

  ExerciseRulesAssessment(
    String exercise, {
    this.hand = 'Left',
    this.calibration,
  }) : rule = _calibrated(ExerciseRule.forExercise(exercise), calibration);

  static ExerciseRule _calibrated(
    ExerciseRule base,
    CalibrationResult? calibration,
  ) =>
      calibration == null ||
          !calibration.personalised ||
          calibration.exercise != base.id ||
          !PatientCalibration.supports(base.id)
      ? base
      : base.withTarget(calibration.target, calibration.minimumRom);

  void resetTracking() {
    if (rule.id == kElbowFlexionExtension) _elbowWorld.resetTracking();
    if (rule.id == kShoulderRotation) _shoulderRotation.resetTracking();
    stage = 'POSITIONING';
    _armed = false;
    _currentAlert = false;
    _supportDistanceRatio = _supportContactRatio = null;
    _supportHeld = false;
    _supportEnterSince = _supportExitSince = _roleSwapSince = null;
    _supportObservedSeconds = _supportAssessedSeconds = 0;
    _armRestAngles.clear();
    _armRestSince.clear();
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
    _baselineLeft = null;
    _baselineRight = null;
    _readyLegs.clear();
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
    double time, {
    List<Map<String, dynamic>>? worldLandmarks,
    String? angleSource,
  }) {
    if (rule.id == kElbowFlexionExtension) {
      final result = _elbowWorld.update(
        landmarks,
        width,
        height,
        time,
        worldLandmarks: worldLandmarks,
        angleSource: angleSource,
      );
      repCount = result['rep_count'] as int;
      correctCount = result['correct_reps'] as int;
      stage = result['state'] as String;
      return result;
    }
    if (rule.id == kShoulderRotation) {
      final result = _shoulderRotation.update(
        landmarks,
        width,
        height,
        time,
        worldLandmarks: worldLandmarks,
        angleSource: angleSource,
      );
      repCount = result['rep_count'] as int;
      correctCount = result['correct_reps'] as int;
      stage = result['state'] as String;
      return result;
    }
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
        points[id].visibility >= .4 &&
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
      if (rule.id == kAssistedElbowFlexionV5) {
        if (!_assistedWorld) return joint(a, b, c);
        final world = worldLandmarks;
        if (world == null || [a, b, c].any((i) => i >= world.length)) {
          return null;
        }
        for (final i in [a, b, c]) {
          final p = world[i];
          if ([
                'x',
                'y',
                'z',
                'visibility',
              ].any((key) => p[key] is! num || !(p[key] as num).isFinite) ||
              (p['visibility'] as num) < .4 ||
              (p['presence'] is num && (p['presence'] as num) < .4)) {
            return null;
          }
        }
        final u = [
          for (final key in ['x', 'y', 'z'])
            (world[a][key] as num).toDouble() -
                (world[b][key] as num).toDouble(),
        ];
        final v = [
          for (final key in ['x', 'y', 'z'])
            (world[c][key] as num).toDouble() -
                (world[b][key] as num).toDouble(),
        ];
        final ul = math.sqrt(u.fold<double>(0, (s, x) => s + x * x)),
            vl = math.sqrt(v.fold<double>(0, (s, x) => s + x * x));
        if (ul < 1e-5 || vl < 1e-5) return null;
        final dot = u[0] * v[0] + u[1] * v[1] + u[2] * v[2];
        return math.acos((dot / (ul * vl)).clamp(-1.0, 1.0)) * 180 / math.pi;
      }
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

    _assistedWorld =
        rule.id == kAssistedElbowFlexionV5 &&
        angleSource == 'pose_world_landmarks';
    final assistedReadyFloor = _assistedWorld
        ? math.min(rule.start, rule.target + rule.minimumRom)
        : rule.start;
    final upper = rule.isUpperBody;
    final bilateral = rule.usesBothArms;
    if (!upper && !_armed && _startedAt == null) {
      double quality(List<int> ids) => ids.every(visible)
          ? ids.map((id) => points[id].visibility).reduce(math.min)
          : 0;
      final needsHeel = [kHeelSlide, kMiniSquat, kSquat].contains(rule.id);
      final leftQuality = quality([11, 23, 25, 27, if (needsHeel) 29]);
      final rightQuality = quality([12, 24, 26, 28, if (needsHeel) 30]);
      if (rightQuality > leftQuality + .05) {
        _leg = 'Right';
      } else if (leftQuality > rightQuality + .05) {
        _leg = 'Left';
      }
    }
    // When both legs are visible, use the leg that actually starts moving.
    // The choice is frozen for the repetition, including its own ready baseline.
    if (!upper &&
        _armed &&
        _startedAt == null &&
        ![kMiniSquat, kSquat].contains(rule.id) &&
        _readyLegs.length == 2) {
      double movement(String side) {
        final right = side == 'Right';
        final value = rule.id == kStraightLegRaise
            ? joint(right ? 12 : 11, right ? 24 : 23, right ? 26 : 25)
            : joint(right ? 24 : 23, right ? 26 : 25, right ? 28 : 27);
        return value == null ? 0 : (value - _readyLegs[side]!['angle']!).abs();
      }

      final other = _leg == 'Left' ? 'Right' : 'Left';
      final otherMotion = movement(other);
      if (otherMotion >= 12 && otherMotion > movement(_leg) + 8) {
        _leg = other;
        final ready = _readyLegs[_leg]!;
        _baseline = ready['angle'];
        _baselineTilt = ready['tilt'];
        _baselineHipY = ready['hipY'];
        _baselineHeelY = ready['heelY'];
        _baselineThigh = ready['thigh'];
      }
    }
    // A supporting palm may touch the wrist or elbow, not just the forearm
    // midpoint. Use a scale-relative capsule around the segment. Finger points
    // are optional and must remain anatomically close to their own wrist.
    double supportContactRatio(bool right) {
      final e = right ? 14 : 13, w = right ? 16 : 15;
      final sh = right ? 12 : 11, hip = right ? 24 : 23;
      final support = right ? 15 : 16;
      if (![e, w, sh, hip, support].every(visible)) return double.infinity;
      final length = points[e].distance(points[w]);
      final torso = points[sh].distance(points[hip]);
      if (torso < 20 || length < torso * .05) return double.infinity;
      final tolerance = math.max(length * .3, torso * .15);
      final dx = points[w].x - points[e].x, dy = points[w].y - points[e].y;
      double distance(_Point p) {
        final t =
            (((p.x - points[e].x) * dx + (p.y - points[e].y) * dy) /
                    (length * length))
                .clamp(0.0, 1.0);
        return p.distance(
          _Point(points[e].x + t * dx, points[e].y + t * dy, 0, 1),
        );
      }

      var nearest = distance(points[support]);
      for (final tip in right ? [17, 19, 21] : [18, 20, 22]) {
        if (visible(tip) &&
            points[tip].distance(points[support]) <= torso * .25) {
          nearest = math.min(nearest, distance(points[tip]));
        }
      }
      return nearest / tolerance;
    }

    if (rule.id == kAssistedElbowFlexionV5 && _startedAt == null) {
      for (final right in [false, true]) {
        final label = right ? 'Right' : 'Left';
        final bend = elbowAngle(
          right ? 12 : 11,
          right ? 14 : 13,
          right ? 16 : 15,
        );
        if (bend != null &&
            bend >= assistedReadyFloor - ExerciseRule.angleMargin) {
          _armRestSince[label] ??= time;
          _armRestAngles[label] = math.max(_armRestAngles[label] ?? bend, bend);
        }
      }
    }
    if (rule.id == kAssistedElbowFlexionV5 &&
        (repCount == 0 ||
            (_lastRepTime != null && time - _lastRepTime! >= .8)) &&
        _startedAt == null &&
        (!_armed || _baselineLeft != null)) {
      bool supportedRest(bool right) {
        final shoulder = right ? 12 : 11, elbow = right ? 14 : 13;
        final wrist = right ? 16 : 15, hip = right ? 24 : 23;
        final support = right ? 15 : 16;
        if (![shoulder, elbow, wrist, hip, support].every(visible)) {
          return false;
        }
        final bend = elbowAngle(shoulder, elbow, wrist);
        final torso = points[shoulder].distance(points[hip]);
        final length = points[elbow].distance(points[wrist]);
        final baseline = right ? _baselineRight : _baselineLeft;
        return bend != null &&
            (bend >= assistedReadyFloor - ExerciseRule.angleMargin ||
                (_armed && baseline != null && baseline - bend >= 8)) &&
            torso >= 20 &&
            length >= torso * .05 &&
            supportContactRatio(right) <= 1 &&
            (joint(hip, shoulder, elbow) ?? 180) <= 35;
      }

      final right = hand == 'Right';

      if (supportedRest(!right) &&
          (!supportedRest(right) ||
              supportContactRatio(!right) + .15 < supportContactRatio(right))) {
        if (_armed) {
          _baseline = right ? _baselineLeft : _baselineRight;
          _onsetSince = null;
        } else {
          resetTracking();
        }
        hand = right ? 'Left' : 'Right';
      }
    }
    if (rule.id == kAssistedElbowFlexionV5 && _startedAt == null) {
      final other = hand == 'Left' ? 'Right' : 'Left';
      double motion(String label) {
        final right = label == 'Right';
        final bend = elbowAngle(
          right ? 12 : 11,
          right ? 14 : 13,
          right ? 16 : 15,
        );
        return bend == null || !_armRestAngles.containsKey(label)
            ? 0
            : _armRestAngles[label]! - bend;
      }

      if (supportContactRatio(other == 'Right') <=
              supportContactRatio(hand == 'Right') + .15 &&
          motion(other) >= 8 &&
          motion(other) > motion(hand) + 6 &&
          _armRestSince[other] != null &&
          time - _armRestSince[other]! >= ExerciseRule.readyHoldSeconds) {
        hand = other;
        _armed = true;
        _baseline = _armRestAngles[other];
        _baselineLeft = _armRestAngles['Left'];
        _baselineRight = _armRestAngles['Right'];
        _onsetSince = null;
      }
    }
    // An opposite hand crossing the torso often bends before the working arm.
    // Correct that provisional role using torso-relative geometry, preserving
    // completed repetitions and each arm's measured resting angle.
    if (rule.id == kAssistedElbowFlexionV5) {
      final current = hand == 'Right', other = !current;
      double crossing(bool right) {
        if (![11, 12, right ? 14 : 13, right ? 16 : 15].every(visible)) {
          return 0;
        }
        final dx = points[11].x - points[12].x,
            dy = points[11].y - points[12].y;
        final span2 = dx * dx + dy * dy;
        if (span2 < 100) return 0;
        final e = points[right ? 14 : 13], w = points[right ? 16 : 15];
        return -(right ? -1 : 1) *
            ((w.x - e.x) * dx + (w.y - e.y) * dy) /
            span2;
      }

      final mistaken =
          !(_targetReached && _supportHeld) &&
          crossing(current) > .4 &&
          crossing(other) < .25 &&
          supportContactRatio(other) <= 1.25 &&
          supportContactRatio(other) + .3 < supportContactRatio(current);
      if (mistaken) {
        _roleSwapSince ??= time;
        if (time - _roleSwapSince! >= .15) {
          final rest = Map<String, double>.from(_armRestAngles);
          final since = Map<String, double>.from(_armRestSince);
          final next = current ? 'Left' : 'Right';
          resetTracking();
          hand = next;
          _armRestAngles.addAll(rest);
          _armRestSince.addAll(since);
          if (rest[next] != null) {
            _armed = true;
            _baseline = rest[next];
            _baselineLeft = rest['Left'];
            _baselineRight = rest['Right'];
          }
        }
      } else {
        _roleSwapSince = null;
      }
    }
    final activeRight = upper
        ? rule.id == kAssistedElbowFlexionV5 && hand == 'Right'
        : _leg == 'Right';
    final sh = activeRight ? 12 : 11,
        el = activeRight ? 14 : 13,
        wr = activeRight ? 16 : 15;
    final hip = activeRight ? 24 : 23;
    final knee = activeRight ? 26 : 25,
        ankle = activeRight ? 28 : 27,
        heel = activeRight ? 30 : 29;
    final required = upper
        ? <int>[sh, el, wr, hip]
        : <int>[sh, hip, knee, ankle];
    if (bilateral) {
      required.addAll([11, 12, 13, 14, 15, 16, 23, 24]);
    }
    if (rule.id == kAssistedElbowFlexionV5) {
      // The supporting elbow is commonly hidden behind the working forearm.
      // Only its wrist is needed for the support test; do not reset a valid
      // working-arm cycle because unrelated supporting-side joints disappear.
      required.add(activeRight ? 15 : 16);
    }
    if (rule.id == kHeelSlide || rule.id == kMiniSquat || rule.id == kSquat) {
      required.add(heel);
    }
    if (!required.every(visible)) {
      resetTracking();
      return _state(
        landmarks,
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
        double difference(double a, double b) => (a - b + 540) % 360 - 180;
        final midline = (points[11].x + points[12].x) / 2;
        // Outward is away from the torso on each side, independent of camera mirroring.
        leftAngle =
            difference(left, _leftRotationBaseline!) *
            (points[11].x - midline).sign;
        rightAngle =
            difference(right, _rightRotationBaseline!) *
            (points[12].x - midline).sign;
        driver = (leftAngle.abs() + rightAngle.abs()) / 2;
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
      driver = activeRight ? rightAngle : leftAngle;
    }
    if (driver == null || !driver.isFinite) {
      resetTracking();
      return _state(
        landmarks,
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
      driver = rule.relative
          ? (leftAngle.abs() + rightAngle.abs()) / 2
          : (leftAngle + rightAngle) / 2;
    } else if (upper) {
      driver = activeRight ? rightAngle : leftAngle;
    } else {
      driver = activeRight ? rightAngle : leftAngle;
    }
    final angleNow = driver!;
    final torso = points[sh].distance(points[hip]);
    if (torso < 20) {
      resetTracking();
      return _state(
        landmarks,
        null,
        'Move closer so your joints can be tracked.',
      );
    }
    final tilt =
        math.atan2(points[sh].x - points[hip].x, points[hip].y - points[sh].y) *
        180 /
        math.pi;
    final atRest = _assistedWorld
        ? angleNow >=
              (_armed && _baseline != null
                      ? _baseline! - rule.returnBand
                      : assistedReadyFloor) -
                  ExerciseRule.angleMargin
        : rule.relative
        ? math.max(leftAngle!.abs(), rightAngle!.abs()) <=
              rule.start + ExerciseRule.angleMargin
        : bilateral
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
      if (leftAngle! < -5 || rightAngle! < -5) {
        alerts.add('Rotate your forearms outward, away from your torso.');
      }
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
      _supportDistanceRatio = forearm > 0
          ? support.distance(midpoint) / forearm
          : null;
      final contact = supportContactRatio(activeRight);
      _supportContactRatio = contact.isFinite ? contact : null;
      if (contact.isFinite && contact <= 1.25) {
        _supportEnterSince ??= time;
        _supportExitSince = null;
        if (time - _supportEnterSince! >= .12) _supportHeld = true;
      } else if (!contact.isFinite || contact > 1.75) {
        _supportExitSince ??= time;
        _supportEnterSince = null;
        if (time - _supportExitSince! >= .25) _supportHeld = false;
      } else {
        _supportEnterSince = _supportExitSince = null;
      }
      if (!_supportHeld) {
        alerts.add('Support the working forearm with your opposite hand.');
      }
      if ((joint(hip, sh, el) ?? 180) > 35) {
        alerts.add('Keep the working elbow close to your torso.');
      }
    }
    if (rule.id == kStraightLegRaise && (joint(hip, knee, ankle) ?? 0) < 160) {
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
        (_baselineHipY! - points[hip].y) / height > .03) {
      alerts.add('Keep your hip on the support surface.');
    }
    if ([kHeelSlide, kMiniSquat, kSquat].contains(rule.id) &&
        active &&
        _baselineHeelY != null &&
        (_baselineHeelY! - points[heel].y) / height > .03) {
      alerts.add('Keep your heel on the surface.');
    }
    if (rule.id == kMiniSquat && angleNow < 120) {
      alerts.add('Keep the mini squat controlled and shallow.');
    }
    if ([kMiniSquat, kSquat].contains(rule.id) &&
        [11, 12, 23, 24, 25, 26, 27, 28].every(visible)) {
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
          math.atan2(
            points[knee].y - points[hip].y,
            points[knee].x - points[hip].x,
          ) *
          180 /
          math.pi;
      if ((thigh - _baselineThigh!).abs() > 15) {
        alerts.add('Keep your thigh resting on the support.');
      }
    }

    _currentAlert = alerts.isNotEmpty;
    Map<String, dynamic>? completed;
    if (!active) {
      final canEstablishStart =
          alerts.isEmpty ||
          (rule.id == kAssistedElbowFlexionV5 &&
              alerts.every(
                (a) =>
                    a == 'Support the working forearm with your opposite hand.',
              ));
      if (!_armed && atRest && canEstablishStart) {
        if (_lastAngle != null && (angleNow - _lastAngle!).abs() > 5) {
          _readySince = null;
        }
        _readySince ??= time;
        if (time - _readySince! >= ExerciseRule.readyHoldSeconds) {
          _armed = true;
          stage = 'READY';
          if (!rule.relative) _baseline = angleNow;
          _baselineLeft = leftAngle;
          _baselineRight = rightAngle;
          _baselineTilt = tilt;
          _baselineHipY = points[hip].y;
          _baselineHeelY = points.length > heel ? points[heel].y : null;
          if (!upper) {
            for (final right in [false, true]) {
              final s = right ? 12 : 11, h = right ? 24 : 23;
              final k = right ? 26 : 25, a = right ? 28 : 27;
              final foot = right ? 30 : 29;
              final value = right ? rightAngle : leftAngle;
              final rest =
                  value != null &&
                  (rule.increasing
                      ? value <= rule.start + ExerciseRule.angleMargin
                      : value >= rule.start - ExerciseRule.angleMargin);
              if (rest &&
                  [
                    s,
                    h,
                    k,
                    a,
                    if ([kHeelSlide, kMiniSquat, kSquat].contains(rule.id))
                      foot,
                  ].every(visible)) {
                _readyLegs[right ? 'Right' : 'Left'] = {
                  'angle': value,
                  'hipY': points[h].y,
                  'heelY': points[foot].y,
                  'tilt':
                      math.atan2(
                        points[s].x - points[h].x,
                        points[h].y - points[s].y,
                      ) *
                      180 /
                      math.pi,
                  'thigh':
                      math.atan2(
                        points[k].y - points[h].y,
                        points[k].x - points[h].x,
                      ) *
                      180 /
                      math.pi,
                };
              }
            }
            _baselineThigh =
                math.atan2(
                  points[knee].y - points[hip].y,
                  points[knee].x - points[hip].x,
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
          _supportObservedSeconds = _supportAssessedSeconds = 0;
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
          stage = atRest && canEstablishStart ? 'READY' : 'POSITIONING';
        }
      }
    } else {
      _trace.add((time, angleNow));
      _assessedSeconds += dt;
      if (alerts.isNotEmpty) _postureErrorSeconds += dt;
      if (rule.id == kAssistedElbowFlexionV5 &&
          _baseline != null &&
          _baseline! - angleNow >= 20) {
        _supportAssessedSeconds += dt;
        if (_supportHeld) {
          _supportObservedSeconds += dt;
        }
      }
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
          if (rule.id != kAssistedElbowFlexionV5 ||
              _errorCode(alert) != 'SUPPORT_MISSING') {
            _recordError(alert);
          }
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
        if (!_targetReached && rule.id != kAssistedElbowFlexionV5) {
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
          (rule.relative
              ? math.max(leftAngle!.abs(), rightAngle!.abs()) <= rule.returnBand
              : (leftAngle! - _baselineLeft!).abs() <= rule.returnBand &&
                    (rightAngle! - _baselineRight!).abs() <= rule.returnBand);
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
        if (duration >= .4 &&
            rom >=
                (rule.id == kAssistedElbowFlexionV5
                    ? math.max(15, math.min(30, rule.minimumRom * .5))
                    : 10) &&
            _trace.length >= 6) {
          if (rule.id == kAssistedElbowFlexionV5) {
            if (!_targetReached) {
              _recordError(
                'Target angle was not held. Reach the shown target before returning.',
              );
            }
            if (_supportAssessedSeconds >= .3 &&
                _supportObservedSeconds / _supportAssessedSeconds < .6) {
              _recordError(
                'Support the working forearm with your opposite hand.',
              );
            }
          }
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
          _lastRepTime = time;
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
                : _leg,
            'model_identity': 'On-device joint tracking + angle rules',
            'model_version': rule.id == kAssistedElbowFlexionV5
                ? 'AssistedElbowWorldRules_v7'
                : 'OnDeviceRules_v3',
            if (rule.id == kAssistedElbowFlexionV5)
              'angle_source': _assistedWorld
                  ? 'pose_world_landmarks'
                  : 'normalized_image_xy',
            if (rule.id == kAssistedElbowFlexionV5)
              'support_contact_verified': false,
            if (rule.id == kAssistedElbowFlexionV5)
              'support_coverage': _supportAssessedSeconds > 0
                  ? _supportObservedSeconds / _supportAssessedSeconds
                  : null,
            'assessment_method': 'on_device_angle_rules',
            'experimental': true,
            'clinically_validated': false,
            'thresholds': {
              'start': rule.start,
              'movementOnsetDegrees': 8.0,
              'minimumRom': rule.minimumRom,
              if (rule.id == kAssistedElbowFlexionV5)
                'ready_available_rom': rule.minimumRom,
              if (rule.id == kAssistedElbowFlexionV5)
                'minimum_counted_excursion': math.max(
                  15,
                  math.min(30, rule.minimumRom * .5),
                ),
              'angleMargin': ExerciseRule.angleMargin,
              'target': rule.target,
              'relative': rule.relative,
              'targetHoldSeconds': ExerciseRule.targetHoldSeconds,
              'returnHoldSeconds': ExerciseRule.returnHoldSeconds,
              'returnTolerance': rule.returnBand,
              if (rule.id == kAssistedElbowFlexionV5)
                'support_contact': {
                  'measurement':
                      'opposite wrist or nearby hand tip to forearm segment',
                  'forearm_fraction': .3,
                  'torso_fraction': .15,
                  'hand_tip_max_wrist_distance_torso_fraction': .25,
                  'contact_enter_ratio': 1.25,
                  'contact_exit_ratio': 1.75,
                  'contact_enter_hold_s': .12,
                  'contact_exit_hold_s': .25,
                  'required_bending_support_fraction': .6,
                },
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
          // Keep the observed working arm. The next side is selected from
          // support and movement, never from the previous repetition's label.
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
    'Rotate your forearms outward, away from your torso.' =>
      'ROTATION_DIRECTION',
    'Keep the lifting knee straight.' => 'KNEE_BENT',
    'Keep your hip on the support surface.' => 'HIP_LIFT',
    'Keep your heel on the surface.' => 'HEEL_LIFT',
    'Keep your knees aligned with your feet.' => 'KNEE_ALIGNMENT',
    'Keep the mini squat controlled and shallow.' => 'SQUAT_TOO_DEEP',
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
        : _leg,
    'angle': angle,
    'rep_count': repCount,
    'correct_reps': correctCount,
    'form': _errors.isNotEmpty
        ? 'incorrect'
        : angle == null
        ? 'Waiting'
        : _currentAlert
        ? 'Adjusting'
        : _armed || _startedAt != null
        ? 'correct'
        : 'Waiting',
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
    if (rule.id == kAssistedElbowFlexionV5)
      'support_distance_ratio': _supportDistanceRatio,
    if (rule.id == kAssistedElbowFlexionV5)
      'support_contact_ratio': _supportContactRatio,
    if (rule.id == kAssistedElbowFlexionV5) 'support_observed': _supportHeld,
    if (rule.id == kAssistedElbowFlexionV5)
      'angle_source': _assistedWorld
          ? 'pose_world_landmarks'
          : 'normalized_image_xy',
    'threshold_summary': rule.thresholdSummary,
    'camera_view': rule.cameraView,
    'assessment_method': 'on_device_angle_rules',
    'clinically_validated': false,
  };
}

import 'dart:math' as math;

import '../utils/exercise_utils.dart';
import 'exercise_rules.dart';

/// Local port of the six lower-body rule profiles in
/// backend/app/config/exercises.json and src/exercises/lower_body/checks.py.
///
/// The original RandomForest bundles are research outputs and do not decide
/// form or score in the server implementation. This adapter likewise uses
/// rules only. Its input is ML Kit pose data rather than MediaPipe data, so
/// measured 3D angles and view detection require device validation.
class LowerBodyAssessment extends ExerciseRulesAssessment {
  LowerBodyAssessment(super.exercise, {super.calibration})
    : _profile = _Profile.forId(exercise).withTarget(
        calibration != null &&
                calibration.personalised &&
                calibration.exercise == normalizeExerciseId(exercise)
            ? calibration.target
            : null,
      );

  final _Profile _profile;
  String _leg = 'Left';
  bool _ready = false;
  bool _active = false;
  bool _targetReached = false;
  double? _readySince;
  double? _targetSince;
  double? _returnSince;
  double? _shortReturnSince;
  double? _lastTime;
  double? _frameWidth;
  double? _frameHeight;
  double? _startedAt;
  double? _bestAngle;
  double? _baselineAngle;
  double? _leftReadyAngle;
  double? _rightReadyAngle;
  double? _pelvisY;
  double? _headY;
  double? _thighAngle;
  double _restHeelDistance = 0;
  double _minimumHeelDistance = double.infinity;
  double _minimumSlideAngle = double.infinity;
  bool _slideJudged = false;
  bool _slideInsufficient = false;
  final Map<int, double> _heelBaseline = {};
  final Map<String, double> _errorSince = {};
  final List<double> _angles = [];
  List<String> _activeAlerts = [];
  final Set<String> _errors = {};
  String? _incorrectStep;
  Map<String, dynamic> _lastRep = {};

  @override
  void resetTracking() {
    super.resetTracking();
    _ready = false;
    _active = false;
    _targetReached = false;
    _readySince = null;
    _targetSince = null;
    _returnSince = null;
    _shortReturnSince = null;
    _lastTime = null;
    _startedAt = null;
    _bestAngle = null;
    _baselineAngle = null;
    _leftReadyAngle = null;
    _rightReadyAngle = null;
    _pelvisY = null;
    _headY = null;
    _thighAngle = null;
    _restHeelDistance = 0;
    _minimumHeelDistance = double.infinity;
    _minimumSlideAngle = double.infinity;
    _slideJudged = false;
    _slideInsufficient = false;
    _heelBaseline.clear();
    _errorSince.clear();
    _angles.clear();
    _activeAlerts = [];
    _errors.clear();
    _incorrectStep = null;
  }

  @override
  Map<String, dynamic> update(
    List<Map<String, dynamic>> landmarks,
    double width,
    double height,
    double time, {
    // Accepted for signature compatibility with the base dispatcher. Lower-body
    // profiles measure from the ML Kit joint estimates in `landmarks`; the
    // bridge does not request MediaPipe world landmarks for these exercises, so
    // there is nothing to consume here.
    List<Map<String, dynamic>>? worldLandmarks,
    String? angleSource,
  }) {
    if (!time.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        landmarks.length < 33) {
      resetTracking();
      return _state(landmarks, null, 'Show the required joints clearly.');
    }
    if ((_frameWidth != null && _frameWidth != width) ||
        (_frameHeight != null && _frameHeight != height)) {
      resetTracking();
    }
    _frameWidth = width;
    _frameHeight = height;
    if (_lastTime != null && (time <= _lastTime! || time - _lastTime! > .75)) {
      resetTracking();
    }
    _lastTime = time;

    final pose = _Pose(landmarks, width, height);
    if (!_active && !_ready) {
      final left = pose.quality(false);
      final right = pose.quality(true);
      if (right > left + .05) {
        _leg = 'Right';
      } else if (left > right + .05) {
        _leg = 'Left';
      }
    }

    var angle = _driver(pose, _leg == 'Right');
    if (_ready && !_active && !_profile.isSquat) {
      final left = _driver(pose, false);
      final right = _driver(pose, true);
      final leftMotion = left == null || _leftReadyAngle == null
          ? 0.0
          : (left - _leftReadyAngle!).abs();
      final rightMotion = right == null || _rightReadyAngle == null
          ? 0.0
          : (right - _rightReadyAngle!).abs();
      if (_leg == 'Left' && rightMotion >= 12 && rightMotion > leftMotion + 8) {
        _leg = 'Right';
        angle = right;
        _baselineAngle = _rightReadyAngle;
      } else if (_leg == 'Right' &&
          leftMotion >= 12 &&
          leftMotion > rightMotion + 8) {
        _leg = 'Left';
        angle = left;
        _baselineAngle = _leftReadyAngle;
      }
    }

    final right = _leg == 'Right';
    final sh = right ? 12 : 11;
    final hip = right ? 24 : 23;
    final knee = right ? 26 : 25;
    final ankle = right ? 28 : 27;
    final heel = right ? 30 : 29;
    if (![sh, hip, knee, ankle].every(pose.visible) ||
        angle == null ||
        !angle.isFinite ||
        pose.pixelDistance(sh, hip) < 20) {
      resetTracking();
      return _state(
        landmarks,
        null,
        'Show the required joints clearly, then return to the starting position.',
      );
    }

    final atRest = _profile.increasing
        ? angle <= _profile.exitAngle
        : angle >= _profile.exitAngle;
    final enters = _profile.increasing
        ? angle >= _profile.enterAngle
        : angle <= _profile.enterAngle;
    final reachesTarget = _profile.increasing
        ? angle >= _profile.target - ExerciseRule.angleMargin
        : angle <= _profile.target + ExerciseRule.angleMargin;

    if (!_active) {
      if (rule.id == kHeelSlide && pose.visible(hip) && pose.visible(heel)) {
        _restHeelDistance = math.max(
          _restHeelDistance,
          pose.pixelDistance(hip, heel),
        );
      }
      if (atRest) {
        _readySince ??= time;
        if (!_ready && time - _readySince! >= ExerciseRule.readyHoldSeconds) {
          _ready = true;
          stage = 'READY';
          _leftReadyAngle = _driver(pose, false);
          _rightReadyAngle = _driver(pose, true);
          _baselineAngle = angle;
        }
      } else if (!_ready) {
        _readySince = null;
        stage = 'POSITIONING';
      }
      if (_ready && enters) {
        _startRep(pose, time, angle);
      }
    } else {
      if (time - _startedAt! > 60 || _angles.length >= 1800) {
        resetTracking();
        return _state(
          landmarks,
          angle,
          'Movement timed out. Return to your starting position.',
        );
      }
      _angles.add(angle);
      _bestAngle = _profile.increasing
          ? math.max(_bestAngle!, angle)
          : math.min(_bestAngle!, angle);
      if (reachesTarget) {
        _targetSince ??= time;
        if (time - _targetSince! >= ExerciseRule.targetHoldSeconds) {
          _targetReached = true;
        }
      } else {
        _targetSince = null;
      }
      _activeAlerts = _checkForm(pose, angle);
      for (final alert in _activeAlerts) {
        _errorSince[alert] ??= time;
        if (time - _errorSince[alert]! >= ExerciseRule.errorHoldSeconds) {
          _incorrectStep ??= stage;
          _errors.add(alert);
        }
      }
      _errorSince.removeWhere((message, _) => !_activeAlerts.contains(message));

      // The source uses separate enter and exit thresholds to prevent one
      // noisy angle near a boundary from counting multiple repetitions.
      final returnedToOwnStart =
          atRest &&
          _baselineAngle != null &&
          (angle - _baselineAngle!).abs() <= rule.returnBand;
      if (returnedToOwnStart) {
        _shortReturnSince = null;
        _returnSince ??= time;
        if (time - _returnSince! >= ExerciseRule.returnHoldSeconds) {
          final rep = _finishRep(time);
          final result = _state(landmarks, angle, rep['feedback'] as String);
          result['form'] = rep['form'];
          result['error_type'] = rep['error_type'];
          result['target_reached'] = rep['target_reached'];
          result['target_hold_progress'] = rep['target_reached'] == true
              ? 1.0
              : 0.0;
          result['range_of_motion'] = rep['range_of_motion'];
          result['completed_rep'] = rep;
          return result;
        }
      } else {
        _returnSince = null;
        if (atRest) {
          _shortReturnSince ??= time;
          if (time - _shortReturnSince! > 2) {
            _incorrectStep ??= stage;
            _errors.add(
              'Return is incomplete. Move back to your starting angle.',
            );
          }
        } else {
          _shortReturnSince = null;
        }
      }
    }

    final alerts = _active ? _errors.toList() : <String>[];
    final feedback = alerts.isNotEmpty
        ? alerts.first
        : _activeAlerts.isNotEmpty
        ? _activeAlerts.first
        : _active
        ? _targetReached
              ? 'Return smoothly to your starting position.'
              : 'Move smoothly toward the target angle.'
        : _ready
        ? 'Begin slowly within your comfortable range.'
        : 'Return to the starting position and keep the joints visible.';
    return _state(landmarks, angle, feedback);
  }

  double? _driver(_Pose pose, bool right) {
    final shoulder = right ? 12 : 11;
    final hip = right ? 24 : 23;
    final knee = right ? 26 : 25;
    final ankle = right ? 28 : 27;
    if (rule.id == kStraightLegRaise) {
      return pose.angle3d(shoulder, hip, knee);
    }
    return _profile.driver3d
        ? pose.angle3d(hip, knee, ankle)
        : pose.angle2d(hip, knee, ankle);
  }

  void _startRep(_Pose pose, double time, double angle) {
    _active = true;
    stage = 'DOWN';
    _startedAt = time;
    _bestAngle = angle;
    _targetReached = false;
    _targetSince = null;
    _returnSince = null;
    _shortReturnSince = null;
    _readySince = null;
    _incorrectStep = null;
    _angles
      ..clear()
      ..add(angle);
    _errors.clear();
    _errorSince.clear();
    _activeAlerts = [];
    _minimumHeelDistance = double.infinity;
    _minimumSlideAngle = double.infinity;
    _slideJudged = false;
    _slideInsufficient = false;
    final right = _leg == 'Right';
    final hip = right ? 24 : 23;
    final knee = right ? 26 : 25;
    final sh = right ? 12 : 11;
    _pelvisY = pose.pelvisY;
    _headY = pose.visible(0) ? pose.y(0) : null;
    _thighAngle = pose.angle2d(sh, hip, knee);
    _heelBaseline.clear();
    for (final id in [29, 30]) {
      if (pose.visible(id)) _heelBaseline[id] = pose.y(id);
    }
  }

  List<String> _checkForm(_Pose pose, double angle) {
    final alerts = <String>[];
    final right = _leg == 'Right';
    final sh = right ? 12 : 11;
    final hip = right ? 24 : 23;
    final knee = right ? 26 : 25;
    final ankle = right ? 28 : 27;
    final heel = right ? 30 : 29;
    final ear = right ? 8 : 7;
    final view = pose.view;

    void heelLift() {
      for (final entry in _heelBaseline.entries) {
        if (pose.visible(entry.key) && entry.value - pose.y(entry.key) > .03) {
          alerts.add('Heel lifting off the surface — keep it down');
          return;
        }
      }
    }

    void hipLift() {
      if (_pelvisY != null &&
          pose.pelvisY != null &&
          _pelvisY! - pose.pelvisY! > .03) {
        alerts.add('Hip lifting off the surface — keep it flat');
      }
    }

    if ([kHeelSlide, kMiniSquat, kSquat].contains(rule.id)) {
      heelLift();
    }
    if ([
      kHeelSlide,
      kSeatedKneeExtension,
      kTerminalKneeExtension,
    ].contains(rule.id)) {
      hipLift();
    }

    if (rule.id == kHeelSlide) {
      _minimumSlideAngle = math.min(_minimumSlideAngle, angle);
      if (pose.visible(hip) && pose.visible(heel)) {
        _minimumHeelDistance = math.min(
          _minimumHeelDistance,
          pose.pixelDistance(hip, heel),
        );
      }
      if (!_slideJudged && angle >= _minimumSlideAngle + 15) {
        _slideJudged = true;
        final insufficientTravel =
            _restHeelDistance > 0 &&
            _minimumHeelDistance.isFinite &&
            (_restHeelDistance - _minimumHeelDistance) / _restHeelDistance <
                .25;
        _slideInsufficient = _minimumSlideAngle > 90 || insufficientTravel;
        // This is an accumulated travel verdict, so the source records it
        // once at the turn rather than waiting for another posture sample.
        if (_slideInsufficient) {
          _incorrectStep ??= stage;
          _errors.add('Slide heel further toward your hips');
        }
      }
      if (_slideInsufficient) alerts.add('Slide heel further toward your hips');
    } else if (rule.id == kMiniSquat) {
      // The source has a 130° depth target but no excessive-depth check.
      // Keep a small local guard below 120° so reaching 130° stays valid.
      if (angle < 120) {
        alerts.add('Keep the mini squat shallow.');
      }
      if (view == 'FRONT') {
        _checkKneeWidth(pose, .6, alerts, stance: true);
        _checkKneeOffset(pose, 1.8, alerts);
      }
    } else if (rule.id == kSeatedKneeExtension) {
      if ([0, 11, 12, 23, 24].every(pose.visible)) {
        final shoulderX = (pose.x(11) + pose.x(12)) / 2;
        final shoulderY = (pose.y(11) + pose.y(12)) / 2;
        final hipX = (pose.x(23) + pose.x(24)) / 2;
        final hipY = (pose.y(23) + pose.y(24)) / 2;
        final trunk = math.sqrt(
          math.pow((shoulderX - hipX) * pose.width, 2) +
              math.pow((shoulderY - hipY) * pose.height, 2),
        );
        if (trunk >= 10 &&
            (pose.x(0) - shoulderX).abs() * pose.width / trunk > .88) {
          alerts.add('Keep your back straight and chest upright');
        }
        // The source divides head motion by projected shoulder width. In the
        // required side view that width approaches zero, so tiny ML Kit pose
        // jitter becomes a false rocking verdict. Keep the upright-trunk cue,
        // but leave rocking out until a camera-calibrated measure is available.
      }
    } else if (rule.id == kStraightLegRaise) {
      final raiseAngle = pose.angle2d(sh, hip, knee);
      if (raiseAngle != null && 180 - raiseAngle > 46) {
        alerts.add('Raising too high — lower the leg');
      }
      final kneeAngle = pose.angle2d(hip, knee, ankle);
      if (kneeAngle != null && kneeAngle < 170) {
        alerts.add('Knee bending — keep your leg straight');
      }
      if (_headY != null && pose.visible(0) && _headY! - pose.y(0) > .03) {
        alerts.add('Head lifting — rest your head down');
      }
    } else if (rule.id == kTerminalKneeExtension) {
      final thigh = pose.angle2d(sh, hip, knee);
      if (thigh != null &&
          _thighAngle != null &&
          (thigh - _thighAngle!).abs() > 20) {
        alerts.add('Keep your thigh on the pillow — only straighten the knee');
      }
    } else if (rule.id == kSquat) {
      if (view == 'FRONT') {
        _checkKneeWidth(pose, .72, alerts);
      }
      if (pose.visible(sh) && pose.visible(hip)) {
        final shoulderX =
            view == 'FRONT' && [11, 12, 23, 24].every(pose.visible)
            ? (pose.x(11) + pose.x(12)) / 2
            : pose.x(sh);
        final shoulderY =
            view == 'FRONT' && [11, 12, 23, 24].every(pose.visible)
            ? (pose.y(11) + pose.y(12)) / 2
            : pose.y(sh);
        final hipX = view == 'FRONT' && [11, 12, 23, 24].every(pose.visible)
            ? (pose.x(23) + pose.x(24)) / 2
            : pose.x(hip);
        final hipY = view == 'FRONT' && [11, 12, 23, 24].every(pose.visible)
            ? (pose.y(23) + pose.y(24)) / 2
            : pose.y(hip);
        final lean =
            math.atan2(
              ((shoulderX - hipX) * pose.width).abs(),
              math.max((hipY - shoulderY) * pose.height, 1),
            ) *
            180 /
            math.pi;
        if (lean > 55) alerts.add('Leaning too far forward — chest up');
      }
      if (view == 'SIDE') {
        // The source's absolute knee-to-toe X distance also flags a knee
        // behind the toes. Omit this cue until facing direction is reliable.
        if (angle <= 115) {
          final hipAngle = pose.angle3d(sh, hip, knee);
          if (hipAngle != null && hipAngle < 58) {
            alerts.add('Lower back rounding — brace your core');
          }
        }
      }
      // ML Kit does not estimate facial landmark depth reliably. Only use a
      // visible side projection for this cue, never a 3D ear angle.
      final neck = view == 'SIDE' ? pose.angle2d(ear, sh, hip) : null;
      if (neck != null && neck < 140) {
        alerts.add('Neck not neutral — look straight ahead');
      }
    }
    return alerts;
  }

  void _checkKneeWidth(
    _Pose pose,
    double ratio,
    List<String> alerts, {
    bool stance = false,
  }) {
    if (![11, 12, 25, 26, 27, 28].every(pose.visible)) return;
    final ankleWidth = ((pose.x(27) - pose.x(28)) * pose.width).abs();
    final kneeWidth = ((pose.x(25) - pose.x(26)) * pose.width).abs();
    if (stance) {
      final shoulderWidth = pose.distance3d(11, 12);
      if (shoulderWidth > 1e-6 &&
          pose.distance3d(27, 28) / shoulderWidth < ratio) {
        alerts.add('Ankles too close together — widen stance');
      }
    } else if (ankleWidth > 10 && kneeWidth < ankleWidth * ratio) {
      alerts.add('Knees caving in — push knees out');
    }
  }

  void _checkKneeOffset(_Pose pose, double ratio, List<String> alerts) {
    if (![23, 24, 25, 26, 27, 28].every(pose.visible)) return;
    final hipWidth = ((pose.x(23) - pose.x(24)) * pose.width).abs();
    if (hipWidth < 10) return;
    for (final right in [false, true]) {
      final h = right ? 24 : 23, k = right ? 26 : 25, a = right ? 28 : 27;
      final vx = (pose.x(a) - pose.x(h)) * pose.width;
      final vy = (pose.y(a) - pose.y(h)) * pose.height;
      final length = math.sqrt(vx * vx + vy * vy);
      if (length < 1) continue;
      final kx = (pose.x(k) - pose.x(h)) * pose.width;
      final ky = (pose.y(k) - pose.y(h)) * pose.height;
      final offset = (kx * vy - ky * vx).abs() / length / hipWidth;
      if (offset > ratio) {
        alerts.add('Keep knees aligned with toes');
        return;
      }
    }
  }

  Map<String, dynamic> _finishRep(double time) {
    final best = _bestAngle!;
    final crossedTarget = _profile.increasing
        ? best >= _profile.target - ExerciseRule.angleMargin
        : best <= _profile.target + ExerciseRule.angleMargin;
    final depthReached = _targetReached;
    if (!crossedTarget) _errors.add(_profile.depthAlert);
    if (crossedTarget && !depthReached) {
      _errors.add(
        'Target angle was not held. Reach the shown target before returning.',
      );
    }
    final duration = math.max(0.0, time - _startedAt!);
    // Prevent a short tracking fluctuation from satisfying an assigned rep.
    if (duration < ExerciseRule.minimumCycleSeconds) {
      _errors.add('Move at a slower, controlled pace.');
    }
    final minAngle = _angles.reduce(math.min);
    final maxAngle = _angles.reduce(math.max);
    final rom = maxAngle - minAngle;
    final smoothness = _angles.length < 3
        ? 0.0
        : 100 /
              (1 +
                  List<double>.generate(
                        _angles.length - 2,
                        (i) =>
                            (_angles[i + 2] - 2 * _angles[i + 1] + _angles[i])
                                .abs(),
                      ).reduce((a, b) => a + b) /
                      (_angles.length - 2));
    // Several source checks can describe the same mistake in different
    // words. Count each error category once so scoring stays proportional.
    final errorCodes = _errors.map(_errorCode).toSet();
    final good = errorCodes.isEmpty;
    final score = good
        ? math.min(100.0, 92 + rom / 10)
        : math.max(40.0, 75 - 15.0 * errorCodes.length);
    final feedback = good
        ? 'Good repetition! Maintain controlled pace.'
        : _errors.first;
    repCount++;
    if (good) correctCount++;
    final rep = <String, dynamic>{
      'rep_index': repCount,
      'exercise': rule.id,
      'form': good ? 'correct' : 'incorrect',
      'score': score,
      'score_kind': 'rule_heuristic_not_accuracy',
      'range_of_motion': rom,
      'duration': duration,
      'speed': duration < 1
          ? 'Fast'
          : duration <= 3.8
          ? 'Good'
          : 'Slow',
      'smoothness': smoothness,
      'return_completion': 100.0,
      'minimum_angle': minAngle,
      'maximum_angle': maxAngle,
      'feedback': feedback,
      'feedback_details': _errors.toList(),
      'error_type': good ? '' : _errorCode(_errors.first),
      'error_codes': errorCodes.toList(),
      'incorrect_step': _incorrectStep,
      'target_reached': depthReached,
      'required_target': _profile.target,
      'hand': _leg,
      'assessment_method': 'on_device_angle_rules',
      'model_identity': 'Local lower-body rules from backend exercise config',
      'model_version': 'LowerBodyRulesLocal_v1',
      'experimental': true,
      'clinically_validated': false,
      'biomechanical_evaluation': {
        'depth_target': _profile.target,
        'best_angle': best,
        'depth_reached': depthReached,
        'errors': _errors.toList(),
      },
      'thresholds': {
        'source': 'backend/app/config/exercises.json',
        'enter': _profile.enterAngle,
        'exit': _profile.exitAngle,
        'depthTarget': _profile.target,
        'angleMargin': ExerciseRule.angleMargin,
        'targetHoldSeconds': ExerciseRule.targetHoldSeconds,
        'returnHoldSeconds': ExerciseRule.returnHoldSeconds,
        'errorHoldSeconds': ExerciseRule.errorHoldSeconds,
        'returnTolerance': rule.returnBand,
        if (rule.id == kMiniSquat) 'localExcessDepthLimit': 120.0,
      },
    };
    _lastRep = rep;
    _active = false;
    _ready = false;
    _targetReached = false;
    _readySince = null;
    _targetSince = null;
    _returnSince = null;
    _shortReturnSince = null;
    _startedAt = null;
    _bestAngle = null;
    _baselineAngle = null;
    _angles.clear();
    _errors.clear();
    _heelBaseline.clear();
    _errorSince.clear();
    _activeAlerts = [];
    _incorrectStep = null;
    stage = 'UP';
    return rep;
  }

  Map<String, dynamic> _state(
    List<Map<String, dynamic>> landmarks,
    double? angle,
    String feedback,
  ) {
    final incorrect = _errors.isNotEmpty;
    return {
      'type': 'live_state',
      'exercise': rule.id,
      'landmarks': landmarks,
      'state': stage,
      'expected_hand': _leg,
      'angle': angle,
      'rep_count': repCount,
      'correct_reps': correctCount,
      'form': incorrect
          ? 'incorrect'
          : angle == null
          ? 'Waiting'
          : _activeAlerts.isNotEmpty
          ? 'Adjusting'
          : _ready || _active
          ? 'correct'
          : 'Waiting',
      'feedback': feedback,
      'error_type': incorrect ? _errorCode(_errors.first) : '',
      'incorrect_step': _incorrectStep,
      'target_reached': _targetReached,
      'target_hold_progress': _targetReached
          ? 1.0
          : _targetSince == null
          ? 0.0
          : (((_lastTime ?? _targetSince!) - _targetSince!) /
                    ExerciseRule.targetHoldSeconds)
                .clamp(0.0, 1.0),
      'required_target': _profile.target,
      'range_of_motion': _active && _bestAngle != null && _baselineAngle != null
          ? (_bestAngle! - _baselineAngle!).abs()
          : 0.0,
      'duration': _startedAt == null || _lastTime == null
          ? null
          : _lastTime! - _startedAt!,
      'score': _lastRep['score'],
      'score_kind': 'rule_heuristic_not_accuracy',
      'smoothness': _lastRep['smoothness'],
      'return_completion': _lastRep['return_completion'],
      'speed': _lastRep['speed'] ?? 'Waiting',
      'tracking_valid': angle != null,
      'threshold_summary': rule.thresholdSummary,
      'camera_view': rule.cameraView,
      'assessment_method': 'on_device_angle_rules',
      'clinically_validated': false,
    };
  }

  static String _errorCode(String message) => switch (message) {
    'Heel lifting off the surface — keep it down' => 'HEEL_LIFT',
    'Hip lifting off the surface — keep it flat' => 'HIP_LIFT',
    'Slide heel further toward your hips' ||
    'Slide your heel further in' => 'SLIDE_INSUFFICIENT',
    'Knee past toes — sit back more' => 'KNEE_PAST_TOES',
    'Keep the mini squat shallow.' => 'SQUAT_TOO_DEEP',
    'Ankles too close together — widen stance' => 'STANCE_NARROW',
    'Keep knees aligned with toes' ||
    'Knees caving in — push knees out' => 'KNEE_ALIGNMENT',
    'Keep your back straight and chest upright' => 'BACK_SLOUCHING',
    'Keep upper body still — avoid rocking' => 'BACK_ROCKING',
    'Raising too high — lower the leg' => 'RAISE_TOO_HIGH',
    'Knee bending — keep your leg straight' => 'KNEE_BENT',
    'Head lifting — rest your head down' => 'HEAD_LIFT',
    'Keep your thigh on the pillow — only straighten the knee' =>
      'THIGH_MOVEMENT',
    'Leaning too far forward — chest up' => 'TORSO_LEAN',
    'Lower back rounding — brace your core' => 'BACK_ROUNDING',
    'Neck not neutral — look straight ahead' => 'NECK_POSITION',
    'Target angle was not held. Reach the shown target before returning.' =>
      'TARGET_NOT_HELD',
    'Move at a slower, controlled pace.' => 'TOO_FAST',
    'Return is incomplete. Move back to your starting angle.' =>
      'INCOMPLETE_RETURN',
    _ => 'INSUFFICIENT_DEPTH',
  };
}

class _Profile {
  const _Profile(
    this.enterAngle,
    this.exitAngle,
    this.target, {
    this.increasing = false,
    this.driver3d = true,
    this.isSquat = false,
    required this.depthAlert,
  });

  final double enterAngle, exitAngle, target;
  final bool increasing, driver3d, isSquat;
  final String depthAlert;

  _Profile withTarget(double? value) => value == null
      ? this
      : _Profile(
          enterAngle,
          exitAngle,
          value,
          increasing: increasing,
          driver3d: driver3d,
          isSquat: isSquat,
          depthAlert: depthAlert,
        );

  static _Profile forId(String id) => switch (normalizeExerciseId(id)) {
    kHeelSlide => const _Profile(
      150,
      170,
      90,
      depthAlert: 'Slide your heel further in',
    ),
    kMiniSquat => const _Profile(
      150,
      165,
      130,
      driver3d: false,
      isSquat: true,
      depthAlert: 'Not deep enough',
    ),
    kSeatedKneeExtension => const _Profile(
      100,
      95,
      160,
      increasing: true,
      depthAlert: 'Extend your knee further',
    ),
    kStraightLegRaise => const _Profile(
      165,
      172,
      140,
      depthAlert: 'Raise your leg higher',
    ),
    kTerminalKneeExtension => const _Profile(
      155,
      145,
      170,
      increasing: true,
      depthAlert: 'Straighten your knee fully',
    ),
    // Source squat enter=105°, depth=120°: entry happens after the target.
    // Enter at 145° as in the existing local preset; keep source exit/target.
    kSquat => const _Profile(
      145,
      155,
      120,
      driver3d: false,
      isSquat: true,
      depthAlert: 'Not deep enough',
    ),
    _ => throw StateError('Unsupported lower-body exercise: $id'),
  };
}

class _Pose {
  _Pose(this.landmarks, this.width, this.height);

  final List<Map<String, dynamic>> landmarks;
  final double width, height;

  double _number(int id, String key) {
    final value = landmarks[id][key];
    return value is num ? value.toDouble() : double.nan;
  }

  double x(int id) => _number(id, 'x');
  double y(int id) => _number(id, 'y');
  double z(int id) => _number(id, 'z');

  bool visible(int id) =>
      id >= 0 &&
      id < landmarks.length &&
      _number(id, 'visibility') >= .5 &&
      x(id).isFinite &&
      y(id).isFinite &&
      x(id) >= 0 &&
      x(id) <= 1 &&
      y(id) >= 0 &&
      y(id) <= 1;

  double quality(bool right) {
    final ids = right ? [12, 24, 26, 28] : [11, 23, 25, 27];
    if (!ids.every(visible)) return 0;
    return ids.map((id) => _number(id, 'visibility')).reduce(math.min);
  }

  double pixelDistance(int a, int b) => math.sqrt(
    math.pow((x(a) - x(b)) * width, 2) + math.pow((y(a) - y(b)) * height, 2),
  );

  // LocalPoseBridge normalizes x and z by frame width, but y by height.
  // Restore one common pixel scale before comparing lengths or angles.
  double distance3d(int a, int b) => math.sqrt(
    math.pow((x(a) - x(b)) * width, 2) +
        math.pow((y(a) - y(b)) * height, 2) +
        math.pow((z(a) - z(b)) * width, 2),
  );

  double? angle2d(int a, int b, int c) {
    if (![a, b, c].every(visible)) return null;
    return ExerciseRulesAssessment.angle(
      [x(a) * width, y(a) * height],
      [x(b) * width, y(b) * height],
      [x(c) * width, y(c) * height],
    );
  }

  double? angle3d(int a, int b, int c) {
    if (![a, b, c].every(visible) ||
        ![z(a), z(b), z(c)].every((v) => v.isFinite)) {
      return null;
    }
    final ux = (x(a) - x(b)) * width;
    final uy = (y(a) - y(b)) * height;
    final uz = (z(a) - z(b)) * width;
    final vx = (x(c) - x(b)) * width;
    final vy = (y(c) - y(b)) * height;
    final vz = (z(c) - z(b)) * width;
    final denominator = math.sqrt(
      (ux * ux + uy * uy + uz * uz) * (vx * vx + vy * vy + vz * vz),
    );
    if (!denominator.isFinite || denominator < 1e-8) return null;
    return math.acos(
          ((ux * vx + uy * vy + uz * vz) / denominator).clamp(-1.0, 1.0),
        ) *
        180 /
        math.pi;
  }

  double? get pelvisY =>
      visible(23) && visible(24) ? (y(23) + y(24)) / 2 : null;

  String get view {
    if (!visible(11) || !visible(12)) return 'FRONT';
    final depthSide =
        z(11).isFinite && z(12).isFinite && (z(11) - z(12)).abs() > .12;
    // ML Kit and MediaPipe depth are scaled differently. A narrow shoulder
    // projection supplies a 2D fallback for side-specific checks.
    final hasHips = visible(23) && visible(24);
    final torso = hasHips
        ? math.max(pixelDistance(11, 23), pixelDistance(12, 24))
        : 0.0;
    final projectedSide =
        hasHips && torso > 20 && ((x(11) - x(12)) * width).abs() < torso * .35;
    return depthSide || projectedSide ? 'SIDE' : 'FRONT';
  }
}

import 'dart:math' as math;

/// Bilateral shoulder rotation measured from MediaPipe world
/// landmarks, following the supplied 15 October 2026 specification.
///
/// Status of the numbers, as stated in that report: only the elbow bend range
/// (60-120 degrees) and the sideways torso lean (12 degrees) are retained from
/// the previous implementation. Every other angular limit is a proposed
/// engineering starting value, not a learned LSTM threshold and not a
/// clinically validated limit. The 20-degree "extreme" is a detection setting,
/// not a therapeutic target or a maximum permitted movement.
///
/// The rotation signal is a forearm-orientation proxy in a torso-relative
/// horizontal plane. It is not direct anatomical shoulder rotation.
class ShoulderRotationAssessment {
  /// The app tutorial is bilateral external rotation and return. Keep the
  /// legacy sweep available for old recordings. App auto mode locks a pattern
  /// from observed movement instead of negating one arm for every exercise.
  final bool bilateralExternal;
  final bool autoProtocol;
  bool _wandDetected = false, _protocolLocked = false;
  bool? _protocolCandidate;
  double? _protocolSince, _baselineShoulderRatio;
  double _externalPolarity = 1;
  double? _leftForearmScale, _rightForearmScale;
  double? _leftOnsetAt, _rightOnsetAt, _leftReturnAt, _rightReturnAt;
  bool get _external => bilateralExternal && !_wandDetected;
  double get _returnBand =>
      autoProtocol ? appReturnBandDegrees : centreBandDegrees;
  static const appReturnBandDegrees = 10.0;
  static const appOnsetDegrees = 12.0;
  static const appReturnHoldSeconds = .2;
  ShoulderRotationAssessment({
    this.bilateralExternal = false,
    this.autoProtocol = false,
  });
  bool _externalTargetHeld = false;
  double? _centreSince;
  List<double>? _neutralUpperArms, _neutralImageAnchor;
  final List<double> _neutralSamplesLeft = [], _neutralSamplesRight = [];
  String? _currentFailure;
  final Map<String, double> _liveFailureSince = {};
  final Set<String> _confirmedLiveFailures = {};
  // --- Section 1: joint and posture thresholds -----------------------------
  /// Elbow flexion range accepted while rotating. Retained from the previous
  /// implementation; the report labels this "Existing".
  static const elbowBendMin = 60.0;
  static const elbowBendTarget = 90.0;
  static const elbowBendMax = 120.0;

  /// Angle between the shoulder-to-elbow vector and the downward torso axis.
  static const upperArmMax = 20.0;

  /// Frontal-plane torso-axis deviation from vertical. Retained; "Existing".
  static const sidewaysLeanMax = 12.0;

  /// Sagittal-plane torso inclination change from the calibrated upright.
  static const forwardLeanChangeMax = 10.0;

  /// Shoulder-line yaw change from the calibrated starting orientation.
  static const torsoTwistMax = 10.0;

  /// Wrist-to-wrist inclination from horizontal in the frontal view. The
  /// wrists approximate the wand endpoints.
  static const wandLevelMax = 10.0;

  /// A threshold exceeded in at least this fraction of valid samples flags a
  /// repetition-level form error. Retained from the previous implementation;
  /// this is feedback logic, not a safety assessment.
  static const failurePersistenceFraction = .2;

  // --- Section 2: rotation measurement and counting ------------------------
  /// Stable neutral posture required before calibration is accepted.
  static const neutralHoldSeconds = .5;

  /// Both deviations must sit inside +/- this band to count as centre.
  static const centreBandDegrees = 5.0;

  /// Detection threshold for either extreme, in either direction.
  static const extremeDegrees = 20.0;

  /// Both deviations must stay beyond the extreme threshold this long.
  static const extremeHoldSeconds = .15;

  /// Allowed absolute difference between the aligned forearm deviations.
  static const bilateralMaxDifference = 15.0;

  /// A complete repetition spans centre -> extreme -> centre -> opposite
  /// extreme, so a full cycle covers twice this.
  static const fullExcursionDegrees = 2 * extremeDegrees;

  // --- Section 4: tracking and timing --------------------------------------
  // Tracking confidence, not a movement target. Match the existing world-elbow
  // confidence floor; .7 repeatedly rejected visible wrists on the test phone.
  static const visibilityMin = .5;
  static const maximumFrameGapSeconds = .5;

  /// Causal low-pass constant for the deviation signal. The report asks for
  /// smoothing that reduces jitter without hiding centre crossings and says to
  /// tune it on recordings; 0.08 s matches the elbow engine and is an
  /// engineering choice, not a value from the report.
  static const filterTauSeconds = .08;

  static const source = 'pose_world_landmarks';
  static const provenance = 'proposed_engineering_settings';
  static const reportDate = '2026-10-15';
  static const reportTitle =
      'Shoulder Rotation Measurement and Threshold Report';

  static const limitations =
      'Elbow bend and sideways torso lean are retained from the previous '
      'implementation. Every other limit is a proposed engineering starting '
      'value, not a learned LSTM threshold and not a clinically validated '
      'limit. The rotation signal is a forearm-orientation proxy, not direct '
      'anatomical shoulder rotation. Single-camera depth estimates can make '
      'forearm rotation noisy.';

  static const thresholds = <String, dynamic>{
    'elbow_bend': {
      'target_deg': elbowBendTarget,
      'accept_min_deg': elbowBendMin,
      'accept_max_deg': elbowBendMax,
      'status': 'existing',
    },
    'upper_arm': {'accept_max_deg': upperArmMax, 'status': 'proposed'},
    'torso_sideways_lean': {
      'accept_max_deg': sidewaysLeanMax,
      'status': 'existing',
    },
    'torso_forward_lean_change': {
      'accept_max_deg': forwardLeanChangeMax,
      'status': 'proposed',
    },
    'torso_twist': {'accept_max_deg': torsoTwistMax, 'status': 'proposed'},
    'wand_level': {'accept_max_deg': wandLevelMax, 'status': 'proposed'},
    'failure_persistence_fraction': failurePersistenceFraction,
    'rotation': {
      'neutral_hold_s': neutralHoldSeconds,
      'centre_band_deg': centreBandDegrees,
      'extreme_deg': extremeDegrees,
      'extreme_hold_s': extremeHoldSeconds,
      'bilateral_max_difference_deg': bilateralMaxDifference,
      'status': 'proposed',
    },
    'tracking': {
      'visibility_min': visibilityMin,
      'maximum_frame_gap_s': maximumFrameGapSeconds,
    },
  };

  static String get thresholdSummary =>
      'Elbows bent ${elbowBendMin.toStringAsFixed(0)}-'
      '${elbowBendMax.toStringAsFixed(0)} deg (target '
      '${elbowBendTarget.toStringAsFixed(0)}), upper arms within '
      '${upperArmMax.toStringAsFixed(0)} deg of the torso, torso lean within '
      '${sidewaysLeanMax.toStringAsFixed(0)} deg, forward lean, twist and wand '
      'level change within ${forwardLeanChangeMax.toStringAsFixed(0)} deg. '
      'Rotate both forearms together past '
      '${extremeDegrees.toStringAsFixed(0)} deg each way, holding '
      '${extremeHoldSeconds.toStringAsFixed(2)} s, with arms within '
      '${bilateralMaxDifference.toStringAsFixed(0)} deg of each other. '
      'Proposed engineering settings, not clinical targets.';

  static String get appThresholdSummary =>
      'Hold a comfortable starting position with elbows bent 60-120 degrees (near 90). '
      'Move both forearms through at least ${extremeDegrees.toStringAsFixed(0)} degrees together, hold ${extremeHoldSeconds.toStringAsFixed(2)} s, '
      'then return within ${appReturnBandDegrees.toStringAsFixed(0)} degrees of the held start for ${appReturnHoldSeconds.toStringAsFixed(1)} s. '
      'One completed outward-and-return or side-and-return movement is one repetition. '
      'Proposed engineering settings. The camera movement estimate is not a clinical shoulder rotation measurement.';

  static String get externalThresholdSummary =>
      'Elbows bent 60-120 deg; both forearms rotate outward at least 20 deg, '
      'hold 0.15 s, then return within 5 deg of the start and hold 0.2 s. '
      'Upper-arm and torso deviations are assessed as form feedback, not '
      'silently discarded repetitions. Proposed engineering settings, not clinical targets.';

  final _ArmSignal _left = _ArmSignal();
  final _ArmSignal _right = _ArmSignal();

  int repCount = 0;
  int correctCount = 0;
  String stage = 'POSITIONING';
  bool calibrated = false;

  double? _lastTime;
  double? _neutralSince;
  double? _neutralLeft;
  double? _neutralRight;
  double? _previousLeft;
  double? _previousRight;
  double? _startedAt;
  double? _extremeSince;
  Map<String, dynamic> _lastResult = {};
  Map<String, dynamic> _trackingMetrics = {};

  /// Sign of the first extreme in the current cycle: +1, -1, or null.
  int? _firstSign;

  /// Frames counted toward the repetition-level form decision.
  int _validSamples = 0;
  final Map<String, int> _failureSamples = {};
  double _maximumBilateralDifference = 0;
  final List<Map<String, double>> _trace = [];

  // Calibrated body frame, captured at neutral.
  double _baselineLeft = 0;
  double _baselineRight = 0;
  List<double> _baselineUp = const [0, -1, 0];
  List<double> _baselineLateral = const [1, 0, 0];
  List<double> _baselineForward = const [0, 0, -1];

  void resetTracking() {
    stage = 'POSITIONING';
    calibrated = false;
    _neutralUpperArms = _neutralImageAnchor = null;
    _neutralSamplesLeft.clear();
    _neutralSamplesRight.clear();
    _currentFailure = null;
    _liveFailureSince.clear();
    _confirmedLiveFailures.clear();
    _wandDetected = _protocolLocked = false;
    _protocolCandidate = null;
    _protocolSince = null;
    _baselineShoulderRatio = null;
    _externalPolarity = 1;
    _leftForearmScale = _rightForearmScale = null;
    _leftOnsetAt = _rightOnsetAt = _leftReturnAt = _rightReturnAt = null;
    _lastTime = null;
    _neutralSince = null;
    _externalTargetHeld = false;
    _centreSince = null;
    _neutralLeft = null;
    _neutralRight = null;
    _previousLeft = _previousRight = null;
    _startedAt = null;
    _extremeSince = null;
    _firstSign = null;
    _validSamples = 0;
    _failureSamples.clear();
    _maximumBilateralDifference = 0;
    _trace.clear();
    _trackingMetrics = {};
    _left.reset();
    _right.reset();
  }

  Map<String, dynamic> update(
    List<Map<String, dynamic>> imageLandmarks,
    double width,
    double height,
    double time, {
    List<Map<String, dynamic>>? worldLandmarks,
    String? angleSource,
  }) {
    final invalid =
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        !time.isFinite ||
        angleSource != source ||
        worldLandmarks == null ||
        worldLandmarks.length < 33 ||
        imageLandmarks.length < 33 ||
        !_visible(worldLandmarks, const [11, 12, 13, 14, 15, 16, 23, 24]);
    if (invalid) {
      resetTracking();
      return _state(
        imageLandmarks,
        false,
        'Step back until both shoulders, elbows, wrists and hips are visible. '
        'Keep your body facing the camera.',
      );
    }
    if (_lastTime != null && time <= _lastTime!) {
      resetTracking();
      return _state(
        imageLandmarks,
        false,
        'Tracking timestamps must increase.',
      );
    }
    final delta = _lastTime == null ? null : time - _lastTime!;
    final gap = delta != null && delta > maximumFrameGapSeconds;
    _lastTime = time;

    // A tracking gap discards an incomplete sequence and requires centre
    // again. Occlusion must not be recorded as incorrect form, so the
    // accumulated failures for the abandoned cycle are dropped with it.
    if (gap && !calibrated) resetTracking();
    if (gap && calibrated) _abandonSequence();

    final posture = _Posture.from(
      worldLandmarks,
      imageLandmarks,
      width,
      height,
      stableForward: bilateralExternal,
      imageRotationProxy: autoProtocol,
      forwardReference: calibrated ? _baselineForward : null,
    );
    _trackingMetrics = posture.measurements;
    // The rotation signal is each forearm's azimuth in the body frame built
    // for this frame. Calibration stores the neutral azimuth as the baseline.
    double projectedAngle(String side, double? calibratedScale) {
      final scale =
          calibratedScale ??
          posture.measurements['${side}_forearm_world_ratio']!;
      return math.asin(
            (posture.measurements['${side}_forearm_lateral']! /
                    math.max(.1, scale))
                .clamp(-.98, .98),
          ) *
          180 /
          math.pi;
    }

    _left.raw = autoProtocol
        ? projectedAngle('left', _leftForearmScale)
        : posture.leftAzimuth;
    _right.raw = autoProtocol
        ? projectedAngle('right', _rightForearmScale)
        : posture.rightAzimuth;

    if (!calibrated) {
      final ready =
          posture.elbowOk &&
          (bilateralExternal || posture.upperArmOk) &&
          posture.sidewaysLeanOk &&
          (bilateralExternal || posture.wandLevelOk);
      // Hold against an anchored orientation, rather than accepting any
      // continuously moving pose with correctly bent elbows as neutral.
      double separation(double a, double b) =>
          ((a - b + 540) % 360 - 180).abs();
      final anchor = [
        for (final key in [
          'neutral_left_x',
          'neutral_left_y',
          'neutral_right_x',
          'neutral_right_y',
        ])
          posture.measurements[key]!,
      ];
      final imageMoved =
          _neutralImageAnchor == null ||
          List.generate(
            4,
            (i) => (anchor[i] - _neutralImageAnchor![i]).abs(),
          ).any((d) => d > .04);
      if (!ready) {
        _neutralSince = null;
        _neutralLeft = _neutralRight = null;
        _neutralImageAnchor = null;
        _neutralSamplesLeft.clear();
        _neutralSamplesRight.clear();
      } else if (_neutralSince == null ||
          (bilateralExternal
              ? imageMoved
              : separation(_left.raw, _neutralLeft!) > centreBandDegrees ||
                    separation(_right.raw, _neutralRight!) >
                        centreBandDegrees)) {
        _neutralLeft = _left.raw;
        _neutralRight = _right.raw;
        _neutralImageAnchor = anchor;
        _neutralSince = time;
        _neutralSamplesLeft.clear();
        _neutralSamplesRight.clear();
      }
      if (ready) {
        _neutralSamplesLeft.add(
          autoProtocol
              ? posture.measurements['left_forearm_lateral']!
              : _left.raw,
        );
        _neutralSamplesRight.add(
          autoProtocol
              ? posture.measurements['right_forearm_lateral']!
              : _right.raw,
        );
        if (_neutralSamplesLeft.length > 40) {
          _neutralSamplesLeft.removeAt(0);
          _neutralSamplesRight.removeAt(0);
        }
      }
      if (_neutralSince != null &&
          time - _neutralSince! >= neutralHoldSeconds) {
        calibrated = true;
        if (autoProtocol) {
          _leftForearmScale = posture.measurements['left_forearm_world_ratio'];
          _rightForearmScale =
              posture.measurements['right_forearm_world_ratio'];
        }
        double circularMean(List<double> values) =>
            math.atan2(
              values.fold<double>(0, (s, x) => s + math.sin(x * math.pi / 180)),
              values.fold<double>(0, (s, x) => s + math.cos(x * math.pi / 180)),
            ) *
            180 /
            math.pi;
        double projectedNeutral(List<double> values, double scale) =>
            math.asin(
              (values.reduce((a, b) => a + b) /
                      values.length /
                      math.max(.1, scale))
                  .clamp(-.98, .98),
            ) *
            180 /
            math.pi;
        if (autoProtocol) {
          _left.raw = projectedAngle('left', _leftForearmScale);
          _right.raw = projectedAngle('right', _rightForearmScale);
        }
        _baselineLeft = autoProtocol
            ? projectedNeutral(_neutralSamplesLeft, _leftForearmScale!)
            : bilateralExternal
            ? circularMean(_neutralSamplesLeft)
            : _left.raw;
        _baselineRight = autoProtocol
            ? projectedNeutral(_neutralSamplesRight, _rightForearmScale!)
            : bilateralExternal
            ? circularMean(_neutralSamplesRight)
            : _right.raw;
        _baselineUp = posture.up;
        _baselineLateral = posture.lateral;
        _baselineForward = posture.forward;
        if (bilateralExternal) {
          _baselineShoulderRatio = posture.measurements['shoulder_width_ratio'];
          _neutralUpperArms = [
            posture.measurements['left_upper_arm']!,
            posture.measurements['right_upper_arm']!,
          ];
        }
        stage = 'CENTRE';
        _neutralSince = null;
      }
      final left = _left.raw;
      final right = _right.raw;
      _left.value = left - _baselineLeft;
      _right.value = right - _baselineRight;
      return _state(
        imageLandmarks,
        true,
        calibrated
            ? _feedback()
            : _message(
                    (bilateralExternal
                            ? !posture.elbowOk
                                  ? 'ELBOW_BEND'
                                  : !posture.sidewaysLeanOk
                                  ? 'TORSO_SIDEWAYS_LEAN'
                                  : null
                            : posture.failureText) ??
                        '',
                  ) ??
                  'Hold a steady neutral posture with elbows bent near 90 '
                      'degrees to calibrate.',
      );
    }

    final failure = posture.failureCode(
      baselineUp: _baselineUp,
      baselineLateral: _baselineLateral,
      baselineForward: _baselineForward,
      requireWandLevel: !bilateralExternal,
      upperArmReference: _neutralUpperArms,
      baselineShoulderRatio: _baselineShoulderRatio,
      observableElbowChecks: autoProtocol,
    );

    _currentFailure = failure;
    // Deviation from the calibrated neutral, unwrapped, then smoothed.
    final leftDeviation = _left.update(time, delta, _baselineLeft);
    final rawRightDeviation = _right.update(time, delta, _baselineRight);
    // Re-arm pattern selection only after a real neutral return. Select from
    // sustained paired motion, not one noisy or asynchronous first sample.
    if (autoProtocol &&
        stage == 'CENTRE' &&
        _startedAt == null &&
        leftDeviation.abs() <= _returnBand &&
        rawRightDeviation.abs() <= _returnBand) {
      _protocolLocked = false;
      _leftOnsetAt = _rightOnsetAt = null;
      _protocolCandidate = null;
      _protocolSince = null;
    }
    if (autoProtocol) {
      if (leftDeviation.abs() >= 12) _leftOnsetAt ??= time;
      if (rawRightDeviation.abs() >= 12) _rightOnsetAt ??= time;
    }
    if (autoProtocol &&
        !_protocolLocked &&
        leftDeviation.abs() >= 8 &&
        rawRightDeviation.abs() >= 8) {
      final wand = leftDeviation * rawRightDeviation > 0;
      if (_protocolCandidate != wand) {
        _protocolCandidate = wand;
        _protocolSince = time;
      }
      if (_protocolSince != null && time - _protocolSince! >= .15) {
        _wandDetected = wand;
        _protocolLocked = true;
        _externalPolarity = leftDeviation < 0 ? -1 : 1;
        _stopSequence();
        stage = 'CENTRE';
      }
    }
    final left = autoProtocol || _external
        ? leftDeviation * _externalPolarity
        : leftDeviation;
    final rightDeviation = _external
        ? -rawRightDeviation * _externalPolarity
        : autoProtocol
        ? rawRightDeviation * _externalPolarity
        : rawRightDeviation;
    if (autoProtocol && !_protocolLocked) {
      return _state(
        imageLandmarks,
        true,
        'Move both forearms together from the neutral position.',
      );
    }
    if (autoProtocol || _external) {
      return _externalCycle(
        imageLandmarks,
        time,
        posture,
        failure,
        left,
        rightDeviation,
      );
    }
    final bilateral = (leftDeviation - rightDeviation).abs();
    _maximumBilateralDifference = math.max(
      _maximumBilateralDifference,
      bilateral,
    );
    final bilateralFail = bilateral > bilateralMaxDifference;
    _updateLiveForm(failure, bilateralFail, time);

    Map<String, dynamic>? completed;
    final right = rightDeviation;
    final sampledCentre =
        left.abs() <= _returnBand && right.abs() <= _returnBand;
    // At camera cadence a smooth centre crossing can fall between frames.
    // Accept it only when both arms occupy the centre band at an overlapping
    // interpolated time, with no large jump or tracking gap.
    final inCentre =
        sampledCentre || (!gap && _crossedCentre(left, right, delta: delta));
    _previousLeft = left;
    _previousRight = right;
    final positive = left >= extremeDegrees && right >= extremeDegrees;
    final negative = left <= -extremeDegrees && right <= -extremeDegrees;
    final atExtreme = positive || negative;
    final sign = positive
        ? 1
        : negative
        ? -1
        : 0;

    if (stage == 'CENTRE') {
      _extremeSince = atExtreme ? (_extremeSince ?? time) : null;
      if (_extremeSince != null &&
          time - _extremeSince! >= extremeHoldSeconds) {
        stage = 'OUT';
        _firstSign = sign;
        _startedAt = time;
        _extremeSince = null;
        _beginSequence(left, right);
      }
    } else if (stage == 'OUT') {
      if (inCentre) {
        stage = 'BACK_TO_CENTRE';
        _extremeSince = null;
      } else if (sign != 0 && sign != _firstSign) {
        // Changed direction without passing through the centre band; treat as
        // a new attempt once the centre is re-established.
        stage = 'NEED_CENTRE';
        _extremeSince = null;
        _abandonSequence();
      }
    } else if (stage == 'BACK_TO_CENTRE') {
      _extremeSince = sign != 0 ? (_extremeSince ?? time) : null;
      if (sign != 0 && sign == _firstSign) {
        // Went back out the same side instead of the opposite one.
        stage = 'NEED_CENTRE';
        _extremeSince = null;
        _abandonSequence();
      } else if (_extremeSince != null &&
          time - _extremeSince! >= extremeHoldSeconds) {
        completed = _complete(time, posture, bilateral);
        _lastResult = completed;
        _stopSequence();
      }
    } else if (stage == 'NEED_CENTRE') {
      if (inCentre) {
        stage = 'CENTRE';
        _extremeSince = null;
      }
    }

    if (_startedAt != null && stage != 'POSITIONING') {
      _trace.add({
        'seconds': time - _startedAt!,
        'left_angle': left,
        'right_angle': right,
      });
      if (_trace.length > 240) _trace.removeAt(1);
    }
    if (_startedAt != null) _observe(failure, bilateralFail);

    final state = _state(
      imageLandmarks,
      true,
      completed?['feedback'] as String? ??
          _feedback(failure, bilateral, posture),
    );
    if (completed != null) {
      state.addAll({
        'completed_rep': completed,
        'form': completed['form'],
        'error_type': completed['error_type'],
        'incorrect_step': completed['incorrect_step'],
        'target_reached': completed['target_reached'],
        'target_hold_progress': 1.0,
        'angle': (left + right) / 2,
        'left_angle': left,
        'right_angle': right,
        'range_of_motion': completed['range_of_motion'],
        'left_range_of_motion': completed['left_excursion'],
        'right_range_of_motion': completed['right_excursion'],
        'duration': completed['duration'],
      });
    }
    return state;
  }

  bool _crossedCentre(double left, double right, {double? delta}) {
    if (_previousLeft == null || _previousRight == null) return false;
    List<double>? interval(double previous, double current) {
      final change = current - previous;
      final maximumStep = math.max(
        extremeDegrees,
        math.min(60, 240 * (delta ?? .08)),
      );
      if (change.abs() > maximumStep) return null;
      if (change.abs() < 1e-9) {
        return current.abs() <= centreBandDegrees ? [0, 1] : null;
      }
      final a = (-centreBandDegrees - previous) / change;
      final b = (centreBandDegrees - previous) / change;
      final start = math.max(0.0, math.min(a, b));
      final end = math.min(1.0, math.max(a, b));
      return start <= end ? [start, end] : null;
    }

    final l = interval(_previousLeft!, left);
    final r = interval(_previousRight!, right);
    return l != null &&
        r != null &&
        math.max(l[0], r[0]) <= math.min(l[1], r[1]);
  }

  Map<String, dynamic> _externalCycle(
    List<Map<String, dynamic>> image,
    double time,
    _Posture posture,
    String? failure,
    double left,
    double right,
  ) {
    final inCentre = left.abs() <= _returnBand && right.abs() <= _returnBand;
    final difference = (left - right).abs();
    final phaseMismatch =
        left > _returnBand && right < -_returnBand ||
        right > _returnBand && left < -_returnBand;
    final onsetLag =
        _leftOnsetAt != null &&
        _rightOnsetAt != null &&
        (_leftOnsetAt! - _rightOnsetAt!).abs() > .6;
    final coordinationFail = autoProtocol
        ? phaseMismatch || onsetLag
        : difference > bilateralMaxDifference;
    _updateLiveForm(failure, coordinationFail, time);
    Map<String, dynamic>? completed;
    if (stage == 'NEED_CENTRE' && inCentre) stage = 'CENTRE';
    if (stage == 'CENTRE' && math.max(left, right) >= (autoProtocol ? 12 : 8)) {
      _beginSequence(0, 0);
      _startedAt = time;
      _externalTargetHeld = false;
      _centreSince = _extremeSince = null;
      _leftReturnAt = _rightReturnAt = null;
      stage = 'ROTATING_OUT';
    }
    if (_startedAt != null) {
      _maximumBilateralDifference = math.max(
        _maximumBilateralDifference,
        difference,
      );
      _observe(failure, coordinationFail);
      _trace.add({
        'seconds': time - _startedAt!,
        'left_angle': left,
        'right_angle': right,
        'angle': (left + right) / 2,
      });
      if (_trace.length > 240) _trace.removeAt(1);
      final atTarget = left >= extremeDegrees && right >= extremeDegrees;
      _extremeSince = atTarget ? (_extremeSince ?? time) : null;
      if (_extremeSince != null &&
          time - _extremeSince! >= extremeHoldSeconds) {
        _externalTargetHeld = true;
        stage = 'RETURNING';
      }
      if (autoProtocol && _externalTargetHeld) {
        _leftReturnAt = left.abs() <= _returnBand
            ? (_leftReturnAt ?? time)
            : null;
        _rightReturnAt = right.abs() <= _returnBand
            ? (_rightReturnAt ?? time)
            : null;
      }
      _centreSince = inCentre ? (_centreSince ?? time) : null;
      if (_centreSince != null && time - _centreSince! >= .2) {
        final meaningful =
            _left.excursion >= (autoProtocol ? 15 : 8) &&
            _right.excursion >= (autoProtocol ? 15 : 8) &&
            time - _startedAt! >= .8;
        if (meaningful) {
          completed = _complete(
            time,
            posture,
            difference,
            targetReached: _externalTargetHeld,
          );
        }
        if (completed != null) _lastResult = completed;
        _stopSequence();
        stage = 'CENTRE';
      } else if (time - _startedAt! > 45) {
        _abandonSequence();
      }
    }
    final state = _state(
      image,
      true,
      completed?['feedback'] as String? ??
          _feedback(failure, difference, posture),
    );
    if (completed != null) {
      state.addAll({
        'completed_rep': completed,
        'form': completed['form'],
        'range_of_motion': completed['range_of_motion'],
        'left_range_of_motion': completed['left_excursion'],
        'right_range_of_motion': completed['right_excursion'],
        'target_hold_progress': completed['target_reached'] == true ? 1.0 : 0.0,
        'duration': completed['duration'],
        'target_reached': completed['target_reached'],
        'error_type': completed['error_type'],
      });
    }
    return state;
  }

  void _updateLiveForm(String? failure, bool bilateralFail, double time) {
    final current = <String>{
      ?failure,
      if (bilateralFail) 'BILATERAL_COORDINATION',
    };
    _currentFailure = current.isEmpty ? null : current.first;
    _liveFailureSince.removeWhere((key, _) => !current.contains(key));
    for (final code in current) {
      _liveFailureSince[code] ??= time;
      if (_startedAt != null && time - _liveFailureSince[code]! >= .3) {
        _confirmedLiveFailures.add(code);
      }
    }
  }

  /// Records one valid sample against the repetition-level form decision.
  void _observe(String? failure, bool bilateralFail) {
    _validSamples++;
    if (failure != null) {
      _failureSamples[failure] = (_failureSamples[failure] ?? 0) + 1;
    }
    if (bilateralFail) {
      _failureSamples['BILATERAL_COORDINATION'] =
          (_failureSamples['BILATERAL_COORDINATION'] ?? 0) + 1;
    }
  }

  void _beginSequence(double left, double right) {
    _validSamples = 0;
    _failureSamples.clear();
    _confirmedLiveFailures.clear();
    _liveFailureSince.clear();
    _maximumBilateralDifference = 0;
    _trace.clear();
    _left.beginExcursion(left);
    _right.beginExcursion(right);
  }

  void _abandonSequence() {
    stage = 'NEED_CENTRE';
    _startedAt = null;
    _firstSign = null;
    _extremeSince = _centreSince = null;
    _externalTargetHeld = false;
    _validSamples = 0;
    _failureSamples.clear();
    _trace.clear();
    _confirmedLiveFailures.clear();
    _liveFailureSince.clear();
    _left.endExcursion();
    _right.endExcursion();
  }

  void _stopSequence() {
    // Completion occurs at the opposite extreme, not at centre. Require an
    // actual centre return before another repetition can begin.
    stage = 'NEED_CENTRE';
    _startedAt = null;
    _firstSign = null;
    _extremeSince = _centreSince = null;
    _externalTargetHeld = false;
    _validSamples = 0;
    _failureSamples.clear();
    _trace.clear();
    _confirmedLiveFailures.clear();
    _liveFailureSince.clear();
    _left.endExcursion();
    _right.endExcursion();
  }

  Map<String, dynamic> _complete(
    double time,
    _Posture posture,
    double bilateral, {
    bool targetReached = true,
  }) {
    // A failure flags the repetition once it covers at least the persistence
    // fraction of valid samples in the cycle.
    final required = math.max(
      1,
      (_validSamples * failurePersistenceFraction).ceil(),
    );
    final codes = <String>[
      for (final entry in _failureSamples.entries)
        if (entry.value >= required) entry.key,
    ]..sort();
    if (!targetReached) codes.add('TARGET_NOT_HELD');
    if (autoProtocol &&
        _leftReturnAt != null &&
        _rightReturnAt != null &&
        (_leftReturnAt! - _rightReturnAt!).abs() > .6 &&
        !codes.contains('BILATERAL_COORDINATION')) {
      codes.add('BILATERAL_COORDINATION');
    }
    final good = codes.isEmpty;
    final duration = time - _startedAt!;
    final leftExcursion = _left.excursion;
    final rightExcursion = _right.excursion;
    final rangeScore =
        100 *
        math.min(
          math.min(leftExcursion, rightExcursion) /
              ((autoProtocol || _external)
                  ? extremeDegrees
                  : fullExcursionDegrees),
          1.0,
        );
    final formScore = (100 - 20 * codes.length).clamp(0.0, 100.0);
    // Duration and speed are reported for information. The report proposes no
    // speed or duration pass/fail limit, so pace never raises an error code.
    final paceScore = duration <= 12 ? 100.0 : 80.0;
    final weighted = .45 * formScore + .35 * rangeScore + .20 * paceScore;
    final score = good ? math.min(100.0, weighted) : math.min(60.0, weighted);
    repCount++;
    if (good) correctCount++;
    return {
      ..._metadata,
      'rep_index': repCount,
      'form': good ? 'correct' : 'incorrect',
      'score': score,
      'score_kind': 'descriptive_movement_quality',
      'score_components': {
        'form': formScore,
        'range': rangeScore,
        'pace': paceScore,
        'weights': {'form': .45, 'range': .35, 'pace': .20},
      },
      'score_basis':
          'Posture persistence and measured forearm excursion. Duration and '
          'speed are reported but do not pass or fail the repetition.',
      'duration': duration,
      'speed': duration <= 0
          ? 'Waiting'
          : duration > 12
          ? 'Slow'
          : 'Controlled',
      'angular_speed': duration > 0
          ? (leftExcursion + rightExcursion) / (2 * duration)
          : 0.0,
      'range_of_motion': math.min(leftExcursion, rightExcursion),
      'left_excursion': leftExcursion,
      'right_excursion': rightExcursion,
      'maximum_bilateral_difference': _maximumBilateralDifference,
      'bilateral_difference_limit': autoProtocol
          ? null
          : bilateralMaxDifference,
      if (autoProtocol)
        'coordination': {
          'maximum_onset_lag_s': .6,
          'maximum_return_lag_s': .6,
          'onset_lag_s': _leftOnsetAt != null && _rightOnsetAt != null
              ? (_leftOnsetAt! - _rightOnsetAt!).abs()
              : null,
          'return_lag_s': _leftReturnAt != null && _rightReturnAt != null
              ? (_leftReturnAt! - _rightReturnAt!).abs()
              : null,
        },
      // Every observed posture violation fraction, including those below the
      // persistence threshold, so the data is available for tuning. Only codes
      // at or above `form_failure_threshold` appear in `error_codes` and decide
      // the form verdict.
      'form_failures': {
        for (final entry in _failureSamples.entries)
          entry.key: entry.value / math.max(1, _validSamples),
      },
      'form_failure_threshold': failurePersistenceFraction,
      'valid_samples': _validSamples,
      'angle_trace': List<Map<String, double>>.from(_trace),
      'smoothness': null,
      'target_reached': targetReached,
      'required_target': extremeDegrees,
      'required_left_target': extremeDegrees,
      'required_right_target': extremeDegrees,
      'feedback': good
          ? 'Both forearms rotated through the full range with steady posture.'
          : codes.map(_message).join(' '),
      'feedback_details': codes.map(_message).toList(),
      'error_codes': codes,
      'error_type': good ? '' : codes.first,
      'incorrect_step': good ? null : 'ROTATING',
      'hand': 'Both',
    };
  }

  Map<String, dynamic> get _metadata => {
    'exercise': 'shoulder_rotation',
    'angle_source': autoProtocol ? 'image_lateral_with_world_scale' : source,
    if (autoProtocol) 'pose_coordinate_source': source,
    'assessment_method': 'on_device_angle_rules',
    'model_identity': autoProtocol
        ? 'MediaPipe full video + projected forearm candidate rules'
        : 'MediaPipe world shoulder-rotation candidate rules',
    'model_version': autoProtocol
        ? 'ShoulderRotationApp_v4'
        : _external
        ? 'ShoulderRotationExternal_v2'
        : 'ShoulderRotationRules_v1',
    'movement_protocol': _external
        ? 'bilateral_outward_return'
        : autoProtocol
        ? 'bilateral_sweep_return'
        : 'legacy_wand_sweep',
    if (bilateralExternal)
      'posture_reference':
          'image frontal upper-arm angle plus world change from held neutral',
    'calibration_status': provenance,
    'calibration_report': reportTitle,
    'calibration_report_date': reportDate,
    'limitations': limitations,
    'experimental': true,
    'clinically_validated': false,
    'thresholds': autoProtocol
        ? {
            ...thresholds,
            'app_rotation': {
              'signal': 'image_lateral_with_world_scale',
              'start_relative': true,
              'target_deg': extremeDegrees,
              'target_hold_s': extremeHoldSeconds,
              'return_band_deg': 10,
              'return_hold_s': .2,
              'onset_deg': 12,
              'minimum_counted_excursion_deg': 15,
              'minimum_counted_duration_s': .8,
              'maximum_bilateral_onset_lag_s': .6,
              'maximum_bilateral_return_lag_s': .6,
              'bilateral_comparison':
                  'direction and timing; per-arm target and return',
              'neutral_image_stability_torso_fraction': .04,
            },
          }
        : thresholds,
  };

  String _feedback([String? failure, double? bilateral, _Posture? posture]) {
    if (failure != null) return _message(failure)!;
    if (autoProtocol && _currentFailure == 'BILATERAL_COORDINATION' ||
        !autoProtocol &&
            bilateral != null &&
            bilateral > bilateralMaxDifference) {
      return _message('BILATERAL_COORDINATION')!;
    }
    if (autoProtocol) {
      return switch (stage) {
        'CENTRE' =>
          'Move both forearms slowly, then return to the starting position.',
        'ROTATING_OUT' =>
          'Keep your elbows beside your torso as both forearms move.',
        'RETURNING' =>
          'Return both forearms to the position held at the start.',
        _ => 'Hold the starting position briefly with both elbows bent.',
      };
    }
    if (_external) {
      return switch (stage) {
        'CENTRE' => 'Rotate both forearms outward, then return to your starting position.',
        'ROTATING_OUT' => 'Rotate both forearms outward together while keeping your elbows beside your torso.',
        'RETURNING' => 'Return both forearms to your starting position.',
        _ => 'Hold both forearms steady in the starting position.',
      };
    }
    return switch (stage) {
      'CENTRE' => 'Rotate both forearms together to one side.',
      'OUT' => 'Return both forearms to the centre.',
      'BACK_TO_CENTRE' => 'Now rotate both forearms to the other side.',
      'NEED_CENTRE' => 'Return both forearms to the centre.',
      _ => 'Hold a steady neutral posture to calibrate.',
    };
  }

  String? _message(String code) => switch (code) {
    'TARGET_NOT_HELD' =>
      autoProtocol
          ? 'Both forearms must reach and briefly hold the movement target before returning.'
          : 'Both forearms must reach and briefly hold the outward target before returning.',
    'ELBOW_BEND' =>
      'Keep both elbows bent between ${elbowBendMin.toStringAsFixed(0)} and '
          '${elbowBendMax.toStringAsFixed(0)} degrees.',
    'UPPER_ARM_POSITION' =>
      'Keep your upper arms within ${upperArmMax.toStringAsFixed(0)} degrees '
          'of your torso.',
    'TORSO_SIDEWAYS_LEAN' =>
      'Keep your torso upright; lean stayed over '
          '${sidewaysLeanMax.toStringAsFixed(0)} degrees.',
    'TORSO_FORWARD_LEAN' =>
      'Keep your torso steady front to back; lean changed by more than '
          '${forwardLeanChangeMax.toStringAsFixed(0)} degrees.',
    'TORSO_TWIST' =>
      'Do not twist your torso; shoulder line turned more than '
          '${torsoTwistMax.toStringAsFixed(0)} degrees.',
    'WAND_NOT_LEVEL' =>
      'Keep the wand level; it tilted more than '
          '${wandLevelMax.toStringAsFixed(0)} degrees.',
    'BILATERAL_COORDINATION' =>
      autoProtocol
          ? 'Move both forearms together; start and return at the same time.'
          : 'Move both arms together; they differed by more than '
                '${bilateralMaxDifference.toStringAsFixed(0)} degrees.',
    _ => null,
  };

  Map<String, dynamic> _state(
    List<Map<String, dynamic>> landmarks,
    bool valid,
    String feedback,
  ) {
    final left = calibrated
        ? (_left.value ?? 0) *
              ((autoProtocol || _external) ? _externalPolarity : 1)
        : 0.0;
    final right = calibrated
        ? (_right.value ?? 0) *
              (_external
                  ? -_externalPolarity
                  : autoProtocol
                  ? _externalPolarity
                  : 1)
        : 0.0;
    return {
      ..._metadata,
      'type': 'live_state',
      'landmarks': landmarks,
      'state': stage,
      'expected_hand': 'Both',
      'angle': calibrated ? (left + right) / 2 : null,
      'left_angle': calibrated ? left : null,
      'right_angle': calibrated ? right : null,
      'rep_count': repCount,
      'correct_reps': correctCount,
      'form': !valid || !calibrated
          ? 'Waiting'
          : _confirmedLiveFailures.isNotEmpty
          ? 'incorrect'
          : _currentFailure != null
          ? 'Adjusting'
          : 'correct',
      'feedback': feedback,
      'error_type': _failureSamples.isEmpty ? '' : _failureSamples.keys.first,
      'incorrect_step': _failureSamples.isEmpty ? null : stage,
      'target_reached':
          calibrated &&
          ((autoProtocol || _external)
              ? _externalTargetHeld
              : _firstSign != null),
      'required_target': extremeDegrees,
      'required_left_target': extremeDegrees,
      'required_right_target': extremeDegrees,
      'target_hold_progress': (autoProtocol || _external)
          ? _externalTargetHeld
                ? 1.0
                : _extremeSince == null
                ? 0.0
                : ((_lastTime! - _extremeSince!) / extremeHoldSeconds).clamp(
                    0.0,
                    1.0,
                  )
          : 0.0,
      'range_of_motion': math.min(
        _left.currentExcursion,
        _right.currentExcursion,
      ),
      'left_range_of_motion': _left.currentExcursion,
      'right_range_of_motion': _right.currentExcursion,
      'duration': _startedAt == null ? null : _lastTime! - _startedAt!,
      'bilateral_difference': calibrated ? (left - right).abs() : null,
      'score': _lastResult['score'],
      'score_kind': 'descriptive_movement_quality',
      'score_components': _lastResult['score_components'],
      'smoothness': null,
      'angular_speed': _lastResult['angular_speed'],
      'return_completion': _lastResult['return_completion'],
      'speed': _lastResult['speed'] ?? 'Waiting',
      'tracking_valid': valid,
      'tracking_metrics': _trackingMetrics,
      'threshold_summary': autoProtocol
          ? appThresholdSummary
          : _external
          ? externalThresholdSummary
          : thresholdSummary,
      'camera_view': 'Front view, upright camera',
    };
  }

  static bool _visible(List<Map<String, dynamic>> points, List<int> indices) {
    for (final index in indices) {
      if (index >= points.length) return false;
      final point = points[index];
      // The current engineering gate requires visibility of 0.5 for every required
      // landmark and treats a missing value as insufficient tracking, so an
      // absent or non-finite visibility is rejected rather than assumed good.
      final visibility = point['visibility'];
      if (visibility is! num ||
          !visibility.isFinite ||
          visibility.toDouble() < visibilityMin) {
        return false;
      }
      for (final axis in ['x', 'y', 'z']) {
        final value = point[axis];
        if (value is! num || !value.isFinite) return false;
      }
    }
    return true;
  }
}

/// One forearm's azimuth signal, unwrapped and smoothed.
class _ArmSignal {
  double raw = 0;
  double? _previousRaw;
  double _unwrapped = 0;
  double? value;
  double? _excursionMin;
  double? _excursionMax;

  void reset() {
    raw = 0;
    _previousRaw = null;
    _unwrapped = 0;
    value = null;
    _excursionMin = null;
    _excursionMax = null;
  }

  /// Unwraps the new raw azimuth against the previous sample so a crossing of
  /// +/-180 does not look like a jump, then returns the smoothed deviation.
  double update(double time, double? delta, double baseline) {
    if (_previousRaw == null) {
      _unwrapped = raw;
    } else {
      var difference = raw - _previousRaw!;
      while (difference > 180) {
        difference -= 360;
      }
      while (difference < -180) {
        difference += 360;
      }
      _unwrapped += difference;
    }
    _previousRaw = raw;
    final deviation = _unwrapped - baseline;
    final weight = delta == null || delta <= 0
        ? 1.0
        : 1 - math.exp(-delta / ShoulderRotationAssessment.filterTauSeconds);
    value = value == null ? deviation : value! + weight * (deviation - value!);
    if (_excursionMin == null || value! < _excursionMin!) _excursionMin = value;
    if (_excursionMax == null || value! > _excursionMax!) _excursionMax = value;
    return value!;
  }

  void beginExcursion(double start) {
    _excursionMin = start;
    _excursionMax = start;
  }

  void endExcursion() {
    _excursionMin = null;
    _excursionMax = null;
  }

  double get excursion =>
      _excursionMin == null ? 0 : (_excursionMax ?? 0) - (_excursionMin ?? 0);
  double get currentExcursion => excursion;
}

/// Posture measurements for one frame, in the calibrated body frame.
class _Posture {
  final Map<String, double> measurements;
  final bool elbowOk;
  final bool upperArmOk;
  final bool sidewaysLeanOk;
  final bool wandLevelOk;
  final String? failureText;
  final List<double> up;
  final List<double> lateral;
  final List<double> forward;
  final double leftElbow;
  final double rightElbow;
  final double leftAzimuth;
  final double rightAzimuth;

  const _Posture({
    required this.measurements,
    required this.elbowOk,
    required this.upperArmOk,
    required this.sidewaysLeanOk,
    required this.wandLevelOk,
    required this.failureText,
    required this.up,
    required this.lateral,
    required this.forward,
    required this.leftElbow,
    required this.rightElbow,
    required this.leftAzimuth,
    required this.rightAzimuth,
  });

  /// Builds the MediaPipe body frame described in section 3 of the report.
  static _Posture from(
    List<Map<String, dynamic>> world,
    List<Map<String, dynamic>> image,
    double width,
    double height, {
    bool stableForward = false,
    bool imageRotationProxy = false,
    List<double>? forwardReference,
  }) {
    List<double> w(int index) => [
      (world[index]['x'] as num).toDouble(),
      (world[index]['y'] as num).toDouble(),
      (world[index]['z'] as num).toDouble(),
    ];
    List<double> i(int index) => [
      (image[index]['x'] as num).toDouble() * width,
      (image[index]['y'] as num).toDouble() * height,
      (image[index]['z'] as num).toDouble() * width,
    ];

    final up = _normalize(_subtract(_mid(w(11), w(12)), _mid(w(23), w(24))));
    final shoulderLine = _subtract(w(11), w(12));
    final lateral = _normalize(
      _subtract(shoulderLine, _scale(up, _dot(shoulderLine, up))),
    );
    var forward = _cross(up, lateral);
    // Choose forward from the resting forearms and retain the calibrated sign.
    // A moving wrist must not flip the body frame during the cycle.
    if (stableForward) {
      final reference =
          forwardReference ??
          _mid(_subtract(w(15), w(13)), _subtract(w(16), w(14)));
      if (_dot(forward, reference) < 0) forward = _scale(forward, -1);
    }
    if (!stableForward && _dot(forward, _subtract(w(15), w(11))) < 0) {
      forward = _scale(forward, -1);
    }

    List<double> xy(int index) => [i(index)[0], i(index)[1], 0];
    final imageTorso = _subtract(_mid(xy(11), xy(12)), _mid(xy(23), xy(24)));
    final torsoPixels = math.sqrt(_dot(imageTorso, imageTorso));
    final torsoWorld = math.sqrt(
      _dot(
        _subtract(_mid(w(11), w(12)), _mid(w(23), w(24))),
        _subtract(_mid(w(11), w(12)), _mid(w(23), w(24))),
      ),
    );
    final sideAxis = _normalize(_subtract(xy(11), xy(12)));
    final imageMetrics = <String, double>{};
    for (final (name, e, wr) in [('left', 13, 15), ('right', 14, 16)]) {
      final foreWorld = _subtract(w(wr), w(e));
      final ratio =
          math.sqrt(_dot(foreWorld, foreWorld)) / math.max(.01, torsoWorld);
      final foreImage = _subtract(xy(wr), xy(e));
      imageMetrics['${name}_forearm_world_ratio'] = ratio;
      imageMetrics['${name}_forearm_lateral'] =
          _dot(foreImage, sideAxis) / math.max(1, torsoPixels);
      imageMetrics['${name}_projection_quality'] =
          _dot(foreImage, sideAxis).abs() / math.max(1, torsoPixels * ratio);
    }
    final leftWorldElbow = _angle(w(11), w(13), w(15));
    final rightWorldElbow = _angle(w(12), w(14), w(16));
    final leftElbow =
        imageRotationProxy && imageMetrics['left_projection_quality']! >= .65
        ? _angle(xy(11), xy(13), xy(15))
        : leftWorldElbow;
    final rightElbow =
        imageRotationProxy && imageMetrics['right_projection_quality']! >= .65
        ? _angle(xy(12), xy(14), xy(16))
        : rightWorldElbow;
    final elbowOk =
        leftElbow >= ShoulderRotationAssessment.elbowBendMin &&
        leftElbow <= ShoulderRotationAssessment.elbowBendMax &&
        rightElbow >= ShoulderRotationAssessment.elbowBendMin &&
        rightElbow <= ShoulderRotationAssessment.elbowBendMax;

    final down = _scale(up, -1);
    final leftUpper = _angleBetween(_subtract(w(13), w(11)), down);
    final rightUpper = _angleBetween(_subtract(w(14), w(12)), down);
    final upperArmOk =
        leftUpper <= ShoulderRotationAssessment.upperArmMax &&
        rightUpper <= ShoulderRotationAssessment.upperArmMax;

    // Frontal-plane checks use aspect-corrected image coordinates with an
    // upright camera, as the report directs for 2D checks.
    // Image y grows downward, so an upright torso has a negative y component.
    // Lean is the angle of the torso axis away from vertical in the frontal
    // plane; folding onto +y keeps it independent of camera mirroring.

    final sidewaysLean =
        math.atan2(imageTorso[0].abs(), imageTorso[1].abs()) * 180 / math.pi;
    final sidewaysLeanOk =
        sidewaysLean <= ShoulderRotationAssessment.sidewaysLeanMax;
    // Wrist-to-wrist inclination from horizontal. Fold onto +x first so a
    // level wand reads 0 whichever wrist is on the left of the image.
    final wand = _subtract(i(15), i(16));
    final horizontal = wand[0].abs();
    final wandTilt = math.atan2(wand[1].abs(), horizontal) * 180 / math.pi;
    final wandLevelOk = wandTilt <= ShoulderRotationAssessment.wandLevelMax;

    String? failure;
    if (!elbowOk) {
      failure = 'ELBOW_BEND';
    } else if (!upperArmOk) {
      failure = 'UPPER_ARM_POSITION';
    } else if (!sidewaysLeanOk) {
      failure = 'TORSO_SIDEWAYS_LEAN';
    } else if (!wandLevelOk) {
      failure = 'WAND_NOT_LEVEL';
    }
    // Align the two hands' signs so moving the wand to the same side produces
    // the same sign on both, as the report requires. Both forearms use the same
    // body-frame azimuth (`shoulderRotationAzimuth`), which is measured from
    // the forward axis toward the same lateral axis for each arm. A wand move
    // toward the subject's left therefore gives both hands a positive sign;
    // no per-arm negation is applied, and `left/right same-side` is covered by
    // the tests.
    final leftAzimuth = shoulderRotationAzimuth(
      w(13),
      w(15),
      up,
      lateral,
      forward,
    );
    final rightAzimuth = shoulderRotationAzimuth(
      w(14),
      w(16),
      up,
      lateral,
      forward,
    );
    return _Posture(
      measurements: {
        ...imageMetrics,
        'left_world_elbow_bend': leftWorldElbow,
        'right_world_elbow_bend': rightWorldElbow,
        'left_elbow_bend': leftElbow,
        'right_elbow_bend': rightElbow,
        'left_upper_arm': leftUpper,
        'right_upper_arm': rightUpper,
        'left_image_upper_arm': _angleBetween(
          [i(13)[0] - i(11)[0], i(13)[1] - i(11)[1], 0],
          [-imageTorso[0], -imageTorso[1], 0],
        ),
        'right_image_upper_arm': _angleBetween(
          [i(14)[0] - i(12)[0], i(14)[1] - i(12)[1], 0],
          [-imageTorso[0], -imageTorso[1], 0],
        ),
        'sideways_lean': sidewaysLean,
        'wand_tilt': wandTilt,
        for (final (name, index) in [('left', 15), ('right', 16)]) ...{
          'neutral_${name}_x':
              (i(index)[0] - (i(11)[0] + i(12)[0]) / 2) /
              math.max(
                1,
                math.sqrt(
                  imageTorso[0] * imageTorso[0] + imageTorso[1] * imageTorso[1],
                ),
              ),
          'neutral_${name}_y':
              (i(index)[1] - (i(11)[1] + i(12)[1]) / 2) /
              math.max(
                1,
                math.sqrt(
                  imageTorso[0] * imageTorso[0] + imageTorso[1] * imageTorso[1],
                ),
              ),
        },
        'shoulder_width_ratio':
            math.sqrt(
              math.pow(i(11)[0] - i(12)[0], 2) +
                  math.pow(i(11)[1] - i(12)[1], 2),
            ) /
            math.max(
              1,
              math.sqrt(
                math.pow(imageTorso[0], 2) + math.pow(imageTorso[1], 2),
              ),
            ),
      },
      elbowOk: elbowOk,
      upperArmOk: upperArmOk,
      sidewaysLeanOk: sidewaysLeanOk,
      wandLevelOk: wandLevelOk,
      failureText: failure,
      up: up,
      lateral: lateral,
      forward: forward,
      leftElbow: leftElbow,
      rightElbow: rightElbow,
      leftAzimuth: leftAzimuth,
      rightAzimuth: rightAzimuth,
    );
  }

  /// Posture codes that need the calibrated baseline, evaluated per sample.
  String? failureCode({
    required List<double> baselineUp,
    required List<double> baselineLateral,
    required List<double> baselineForward,
    bool requireWandLevel = true,
    double? baselineShoulderRatio,
    bool observableElbowChecks = false,
    List<double>? upperArmReference,
  }) {
    if (!elbowOk &&
        (!observableElbowChecks ||
            (measurements['left_projection_quality']! >= .65 &&
                (leftElbow < ShoulderRotationAssessment.elbowBendMin ||
                    leftElbow > ShoulderRotationAssessment.elbowBendMax)) ||
            (measurements['right_projection_quality']! >= .65 &&
                (rightElbow < ShoulderRotationAssessment.elbowBendMin ||
                    rightElbow > ShoulderRotationAssessment.elbowBendMax)))) {
      return 'ELBOW_BEND';
    }
    if (upperArmReference == null) {
      if (!upperArmOk) return 'UPPER_ARM_POSITION';
    } else {
      // Frontal abduction is visible in image XY. Assess depth changes against
      // the held neutral pose, instead of grading a static model-depth offset.
      for (var side = 0; side < 2; side++) {
        final name = side == 0 ? 'left' : 'right';
        if (measurements['${name}_image_upper_arm']! >
                ShoulderRotationAssessment.upperArmMax ||
            (measurements['${name}_upper_arm']! - upperArmReference[side])
                    .abs() >
                ShoulderRotationAssessment.upperArmMax) {
          return 'UPPER_ARM_POSITION';
        }
      }
    }
    if (!sidewaysLeanOk) return 'TORSO_SIDEWAYS_LEAN';
    if (requireWandLevel && !wandLevelOk) return 'WAND_NOT_LEVEL';
    final su = _dot(up, baselineUp);
    final sagittal = math.atan2(_dot(up, baselineForward), su) * 180 / math.pi;
    final imageConfirmsChange =
        baselineShoulderRatio == null ||
        (measurements['shoulder_width_ratio']! / baselineShoulderRatio - 1)
                .abs() >
            .12;
    if (sagittal.abs() > ShoulderRotationAssessment.forwardLeanChangeMax &&
        imageConfirmsChange) {
      return 'TORSO_FORWARD_LEAN';
    }
    final yaw =
        math.atan2(
          _dot(lateral, baselineForward),
          _dot(lateral, baselineLateral),
        ) *
        180 /
        math.pi;
    measurements['torso_yaw_change'] = yaw;
    final width = measurements['shoulder_width_ratio']!;
    final imageConfirms =
        baselineShoulderRatio == null ||
        (width / baselineShoulderRatio - 1).abs() > .12;
    if (yaw.abs() > ShoulderRotationAssessment.torsoTwistMax && imageConfirms) {
      return 'TORSO_TWIST';
    }
    return null;
  }

  static List<double> _mid(List<double> a, List<double> b) => [
    (a[0] + b[0]) / 2,
    (a[1] + b[1]) / 2,
    (a[2] + b[2]) / 2,
  ];
  static List<double> _subtract(List<double> a, List<double> b) => [
    a[0] - b[0],
    a[1] - b[1],
    a[2] - b[2],
  ];
  static List<double> _scale(List<double> a, double k) => [
    a[0] * k,
    a[1] * k,
    a[2] * k,
  ];
  static double _dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  static List<double> _cross(List<double> a, List<double> b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
  static List<double> _normalize(List<double> a) {
    final length = math.sqrt(_dot(a, a));
    if (!length.isFinite || length < 1e-9) return const [0, -1, 0];
    return [a[0] / length, a[1] / length, a[2] / length];
  }

  static double _angleBetween(List<double> a, List<double> b) {
    final denominator = math.sqrt(_dot(a, a) * _dot(b, b));
    if (!denominator.isFinite || denominator < 1e-9) return 180;
    return math.acos((_dot(a, b) / denominator).clamp(-1.0, 1.0)) *
        180 /
        math.pi;
  }

  /// Three-point angle with the middle point as the vertex.
  static double _angle(List<double> a, List<double> b, List<double> c) =>
      _angleBetween(_subtract(a, b), _subtract(c, b));
}

/// Signed forearm azimuth in the torso-relative horizontal plane.
///
/// Exposed for tests: projects the elbow-to-wrist vector into the plane
/// perpendicular to [up] and returns its angle from [forward] toward [lateral].
double shoulderRotationAzimuth(
  List<double> elbow,
  List<double> wrist,
  List<double> up,
  List<double> lateral,
  List<double> forward,
) {
  final v = [wrist[0] - elbow[0], wrist[1] - elbow[1], wrist[2] - elbow[2]];
  final upComponent = v[0] * up[0] + v[1] * up[1] + v[2] * up[2];
  final projected = [
    v[0] - upComponent * up[0],
    v[1] - upComponent * up[1],
    v[2] - upComponent * up[2],
  ];
  final lateralComponent =
      projected[0] * lateral[0] +
      projected[1] * lateral[1] +
      projected[2] * lateral[2];
  final forwardComponent =
      projected[0] * forward[0] +
      projected[1] * forward[1] +
      projected[2] * forward[2];
  if (lateralComponent.abs() < 1e-12 && forwardComponent.abs() < 1e-12) {
    return 0;
  }
  return math.atan2(lateralComponent, forwardComponent) * 180 / math.pi;
}

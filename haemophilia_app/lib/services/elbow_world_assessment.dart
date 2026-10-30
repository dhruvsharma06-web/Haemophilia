import 'dart:math' as math;

class ElbowWorldAssessment {
  static const leftExtensionMin = 152.59284378588075;
  static const leftFlexionMax = 70.75558628426776;
  static const leftRomMin = 87.9257364170231;
  static const leftReturnErrorMax = 7.763461670817362;
  static const rightExtensionMin = 153.6168987049523;
  static const rightFlexionMax = 91.96654666142514;
  static const rightRomMin = 70.01687215785255;
  static const rightReturnErrorMax = 8.541307073061384;
  static const maximumAngleDifference = 34.758123896484435;
  static const maximumRomDifference = 31.302325022900295;
  static const filterTauSeconds = .08;
  static const readyHoldSeconds = .3;
  static const targetHoldSeconds = .2;
  static const returnHoldSeconds = .2;
  static const stableReturnSeconds = 2.0;
  static const trackingTimeoutSeconds = 45.0;
  static const maximumFrameGapSeconds = .5;
  static const movementDegrees = 8.0;
  /// Numerical convergence tolerance only, applied when comparing the smoothed
  /// angle against a threshold. The causal low-pass filter asymptotically
  /// approaches its input, so a patient holding exactly at a displayed
  /// threshold settles a few thousandths of a degree below it and a strict
  /// comparison would reject a compliant hold. This is far below pose noise
  /// (~1-3 deg) and is deliberately NOT a clinical or jitter allowance: the
  /// supplied thresholds are compared as given, per the source method.
  static const _convergenceEpsilon = .05;
  static const source = 'pose_world_landmarks';
  static const provenance = 'person_specific_candidate';
  static const sourceSessionId = 'session_20261015_230124_9f81f611';
  static const limitations =
      'Estimated 3D person-specific candidate references, not clinical targets. '
      'Do not mix with image-plane angles. No technique accuracy claim without '
      'held-out labelled validation.';

  static const thresholds = <String, dynamic>{
    'left': {
      'extension_min_deg': leftExtensionMin,
      'flexion_max_deg': leftFlexionMax,
      'rom_min_deg': leftRomMin,
      'return_error_max_deg': leftReturnErrorMax,
    },
    'right': {
      'extension_min_deg': rightExtensionMin,
      'flexion_max_deg': rightFlexionMax,
      'rom_min_deg': rightRomMin,
      'return_error_max_deg': rightReturnErrorMax,
    },
    'bilateral': {
      'maximum_angle_difference_deg': maximumAngleDifference,
      'rom_difference_max_deg': maximumRomDifference,
    },
  };

  static String get thresholdSummary =>
      'World XYZ candidate references: left extension >= ${leftExtensionMin.toStringAsFixed(2)} deg, '
      'flexion <= ${leftFlexionMax.toStringAsFixed(2)} deg, ROM >= ${leftRomMin.toStringAsFixed(2)} deg, '
      'return error <= ${leftReturnErrorMax.toStringAsFixed(2)} deg; '
      'right extension >= ${rightExtensionMin.toStringAsFixed(2)} deg, '
      'flexion <= ${rightFlexionMax.toStringAsFixed(2)} deg, ROM >= ${rightRomMin.toStringAsFixed(2)} deg, '
      'return error <= ${rightReturnErrorMax.toStringAsFixed(2)} deg. '
      'Bilateral angle difference <= ${maximumAngleDifference.toStringAsFixed(2)} deg; '
      'ROM difference <= ${maximumRomDifference.toStringAsFixed(2)} deg. '
      'Hold extension 0.3s, flexion and return 0.2s. Not clinically validated.';

  final _left = _Arm(
    leftExtensionMin,
    leftFlexionMax,
    leftRomMin,
    leftReturnErrorMax,
  );
  final _right = _Arm(
    rightExtensionMin,
    rightFlexionMax,
    rightRomMin,
    rightReturnErrorMax,
  );
  int repCount = 0;
  int correctCount = 0;
  String stage = 'POSITIONING';
  double? _lastTime;
  double? _startedAt;
  double? _returnSince;
  double? _stableSince;
  double? _stableLeft;
  double? _stableRight;
  double _maximumDifference = 0;
  final Set<String> _errors = {};
  final List<Map<String, double>> _trace = [];
  Map<String, dynamic> _lastResult = {};

  void resetTracking() {
    stage = 'POSITIONING';
    _lastTime = null;
    _startedAt = null;
    _returnSince = null;
    _stableSince = null;
    _stableLeft = null;
    _stableRight = null;
    _maximumDifference = 0;
    _errors.clear();
    _trace.clear();
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
    final leftRaw = angleSource == source ? _angle(worldLandmarks, 11) : null;
    final rightRaw = angleSource == source ? _angle(worldLandmarks, 12) : null;
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        !time.isFinite ||
        leftRaw == null ||
        rightRaw == null) {
      resetTracking();
      return _state(
        imageLandmarks,
        false,
        'Valid frame dimensions and both arms in pose_world_landmarks are required; no image fallback.',
      );
    }
    final elapsed = _lastTime == null ? null : time - _lastTime!;
    if (elapsed != null && elapsed <= 0) {
      resetTracking();
      return _state(
        imageLandmarks,
        false,
        'Tracking timestamps must increase.',
      );
    }
    if (elapsed != null && elapsed > maximumFrameGapSeconds) {
      resetTracking();
    }
    final delta = _lastTime == null ? null : time - _lastTime!;
    _lastTime = time;
    _left.filter(leftRaw, delta);
    _right.filter(rightRaw, delta);
    if (_startedAt != null && time - _startedAt! > trackingTimeoutSeconds) {
      resetTracking();
      return _state(
        imageLandmarks,
        false,
        'Movement timed out. Hold both elbows extended to restart.',
      );
    }
    Map<String, dynamic>? completed;
    if (stage == 'POSITIONING') {
      _left.ready(time);
      _right.ready(time);
      if (_left.extensionHeld(time) && _right.extensionHeld(time)) {
        stage = 'READY';
        _left.begin();
        _right.begin();
      }
    } else if (stage == 'READY') {
      if (_left.baseline! - _left.value! >= movementDegrees ||
          _right.baseline! - _right.value! >= movementDegrees) {
        stage = 'BENDING';
        _startedAt = time;
      } else {
        _left.baseline = math.max(_left.baseline!, _left.value!);
        _right.baseline = math.max(_right.baseline!, _right.value!);
      }
    }
    if (_startedAt != null) {
      _left.track(time);
      _right.track(time);
      _trace.add({
        'seconds': time - _startedAt!,
        'angle': (_left.value! + _right.value!) / 2,
        'left_angle': _left.value!,
        'right_angle': _right.value!,
      });
      if (_trace.length > 240) _trace.removeAt(1);
      _maximumDifference = math.max(
        _maximumDifference,
        (_left.value! - _right.value!).abs(),
      );
      if (_maximumDifference > maximumAngleDifference) {
        _errors.add('BILATERAL_ANGLE_DIFFERENCE');
      }
      if (_left.value! - _left.minimum! >= movementDegrees ||
          _right.value! - _right.minimum! >= movementDegrees) {
        stage = 'RETURNING';
      }
      if (stage == 'RETURNING') {
        final returned = _left.returned && _right.returned;
        _returnSince = returned ? (_returnSince ?? time) : null;
        if (_stableLeft == null ||
            (_stableLeft! - _left.value!).abs() > 2 ||
            (_stableRight! - _right.value!).abs() > 2) {
          _stableLeft = _left.value;
          _stableRight = _right.value;
          _stableSince = time;
        }
        final returnHeld =
            _returnSince != null && time - _returnSince! >= returnHoldSeconds;
        final stableAttempt = time - _stableSince! >= stableReturnSeconds;
        if (returnHeld || stableAttempt) {
          completed = _complete(time, returnHeld);
          _lastResult = completed;
          resetTracking();
        }
      }
    }
    final state = _state(
      imageLandmarks,
      true,
      completed?['feedback'] as String? ?? _feedback,
    );
    if (completed != null) {
      final leftFinal =
          completed['arm_metrics']['left']['final_angle'] as double;
      final rightFinal =
          completed['arm_metrics']['right']['final_angle'] as double;
      state.addAll({
        'completed_rep': completed,
        'form': completed['form'],
        'error_type': completed['error_type'],
        'incorrect_step': completed['incorrect_step'],
        'target_reached': completed['target_reached'],
        'target_hold_progress': completed['target_reached'] == true ? 1.0 : 0.0,
        'angle': (leftFinal + rightFinal) / 2,
        'left_angle': leftFinal,
        'right_angle': rightFinal,
        'range_of_motion': completed['range_of_motion'],
        'left_range_of_motion': completed['left_range_of_motion'],
        'right_range_of_motion': completed['right_range_of_motion'],
        'duration': completed['duration'],
      });
    }
    return state;
  }

  String get _feedback => _errors.isNotEmpty
      ? _errors.map(_message).join(' ')
      : switch (stage) {
          'READY' => 'Bend both elbows within your comfortable range.',
          'BENDING' => 'Hold each arm at its own candidate flexion reference.',
          'RETURNING' => 'Return both elbows to their starting extension.',
          _ => 'Hold both elbows extended to establish a starting position.',
        };

  Map<String, dynamic> _complete(double time, bool returnHeld) {
    for (final entry in {'LEFT': _left, 'RIGHT': _right}.entries) {
      if (!entry.value.targetHeld) {
        _errors.add('${entry.key}_TARGET_NOT_HELD');
      }
      if (!entry.value.romReached) {
        _errors.add('${entry.key}_INSUFFICIENT_ROM');
      }
      if (!entry.value.returned || !returnHeld) {
        _errors.add('${entry.key}_INCOMPLETE_RETURN');
      }
    }
    final romDifference = (_left.rom - _right.rom).abs();
    if (romDifference > maximumRomDifference) {
      _errors.add('BILATERAL_ROM_DIFFERENCE');
    }
    final duration = time - _startedAt!;
    if (duration < 1) _errors.add('TOO_FAST');
    final good = _errors.isEmpty;
    final targetReached = _left.targetHeld && _right.targetHeld;
    final rangeScore =
        (100 * math.min(_left.rom / leftRomMin, _right.rom / rightRomMin))
            .clamp(0.0, 100.0);
    final returnScore =
        100 * math.min(_left.returnFraction, _right.returnFraction);
    final paceScore = duration < 1
        ? 30.0
        : duration > 8
        ? 70.0
        : 100.0;
    final agreementScore = _errors.any((code) => code.startsWith('BILATERAL'))
        ? 0.0
        : 100.0;
    final formScore =
        (agreementScore +
            returnScore +
            (_left.targetHeld ? 100 : 0) +
            (_right.targetHeld ? 100 : 0)) /
        4;
    final weightedScore = .45 * formScore + .35 * rangeScore + .20 * paceScore;
    final score = math.min(
      good
          ? 100.0
          : targetReached
          ? 75.0
          : 50.0,
      weightedScore,
    );
    final travel = (_left.travel + _right.travel) / 2;
    final smoothness = (_left.smoothness + _right.smoothness) / 2;
    repCount++;
    if (good) correctCount++;
    return {
      ..._metadata,
      'rep_index': repCount,
      'form': good ? 'correct' : 'incorrect',
      'score': score,
      'score_kind': 'descriptive_movement_quality',
      'score_components': {
        'range': rangeScore,
        'form': formScore,
        'posture': agreementScore,
        'pace': paceScore,
        'return': returnScore,
        'weights': {'form': .45, 'range': .35, 'pace': .20},
      },
      'score_basis': 'Candidate threshold agreement, range and pace; posture component is bilateral agreement, not clinical posture accuracy.',
      'smoothness': smoothness,
      'angular_speed': duration > 0 ? travel / duration : 0.0,
      'angle_trace': List<Map<String, double>>.from(_trace),
      'duration': duration,
      'speed': duration < 1
          ? 'Fast'
          : duration > 8
          ? 'Slow'
          : 'Controlled',
      'range_of_motion': math.min(_left.rom, _right.rom),
      'left_range_of_motion': _left.rom,
      'right_range_of_motion': _right.rom,
      'minimum_angle': math.min(_left.minimum!, _right.minimum!),
      'maximum_angle': math.max(_left.maximum!, _right.maximum!),
      'left_peak_angle': _left.minimum,
      'right_peak_angle': _right.minimum,
      'arm_metrics': {'left': _left.statistics, 'right': _right.statistics},
      'bilateral_metrics': {
        'max_angle_difference': _maximumDifference,
        'rom_difference': romDifference,
      },
      'return_completion': returnScore,
      'target_reached': targetReached,
      'required_target': leftFlexionMax,
      'required_left_target': leftFlexionMax,
      'required_right_target': rightFlexionMax,
      'feedback': good
          ? 'Both candidate targets held and return completed.'
          : _errors.map(_message).join(' '),
      'feedback_details': _errors.map(_message).toList(),
      'error_codes': _errors.toList(),
      'error_type': good ? '' : _errors.first,
      'incorrect_step': good ? null : 'BENDING_OR_RETURNING',
      'hand': 'Both',
    };
  }

  Map<String, dynamic> get _metadata => {
    'exercise': 'elbow_flexion_extension',
    'angle_source': source,
    'assessment_method': 'on_device_angle_rules',
    'model_identity': 'MediaPipe world elbow candidate rules',
    'model_version': 'ElbowWorldRules_v1',
    'calibration_status': provenance,
    'calibration_source_session_id': sourceSessionId,
    'approved_reps': 22,
    'limitations': limitations,
    'experimental': true,
    'clinically_validated': false,
    'thresholds': thresholds,
  };

  String _message(String code) {
    for (final entry in {'LEFT': _left, 'RIGHT': _right}.entries) {
      final label = entry.key == 'LEFT' ? 'Left' : 'Right';
      final arm = entry.value;
      if (code == '${entry.key}_TARGET_NOT_HELD') {
        return '$label elbow did not hold at or below ${arm.flexionMax.toStringAsFixed(2)} deg for 0.2s.';
      }
      if (code == '${entry.key}_INSUFFICIENT_ROM') {
        return '$label elbow range was below ${arm.romMin.toStringAsFixed(2)} deg.';
      }
      if (code == '${entry.key}_INCOMPLETE_RETURN') {
        return '$label elbow must return to at least ${arm.extensionMin.toStringAsFixed(2)} deg and within ${arm.returnErrorMax.toStringAsFixed(2)} deg of its start, held 0.2s.';
      }
    }
    return switch (code) {
      'BILATERAL_ANGLE_DIFFERENCE' =>
        'Arm angle difference exceeded ${maximumAngleDifference.toStringAsFixed(2)} deg.',
      'BILATERAL_ROM_DIFFERENCE' =>
        'Arm range difference exceeded ${maximumRomDifference.toStringAsFixed(2)} deg.',
      'TOO_FAST' => 'Move more slowly; the movement lasted less than 1s.',
      _ => 'Repeat within your comfortable range.',
    };
  }

  Map<String, dynamic> _state(
    List<Map<String, dynamic>> landmarks,
    bool valid,
    String feedback,
  ) => {
    ..._metadata,
    'type': 'live_state',
    'landmarks': landmarks,
    'state': stage,
    'expected_hand': 'Both',
    'angle': _left.value == null ? null : (_left.value! + _right.value!) / 2,
    'left_angle': _left.value,
    'right_angle': _right.value,
    'rep_count': repCount,
    'correct_reps': correctCount,
    'form': !valid || stage == 'POSITIONING'
        ? 'Waiting'
        : _errors.isNotEmpty
        ? 'incorrect'
        : 'correct',
    'feedback': feedback,
    'error_type': _errors.isEmpty ? '' : _errors.first,
    'incorrect_step': _errors.isEmpty ? null : stage,
    'target_reached': _left.targetHeld && _right.targetHeld,
    'required_target': leftFlexionMax,
    'required_left_target': leftFlexionMax,
    'required_right_target': rightFlexionMax,
    'target_hold_progress': math.min(
      _left.progress(_lastTime),
      _right.progress(_lastTime),
    ),
    'range_of_motion': math.min(_left.rom, _right.rom),
    'left_range_of_motion': _left.rom,
    'right_range_of_motion': _right.rom,
    'duration': _startedAt == null ? null : _lastTime! - _startedAt!,
    'score': _lastResult['score'],
    'score_kind': 'descriptive_movement_quality',
    'score_components': _lastResult['score_components'],
    'smoothness': _lastResult['smoothness'],
    'angular_speed': _lastResult['angular_speed'],
    'return_completion': _lastResult['return_completion'],
    'speed': _lastResult['speed'] ?? 'Waiting',
    'tracking_valid': valid,
    'threshold_summary': thresholdSummary,
    'camera_view': 'Both arms visible',
  };

  static double? _angle(List<Map<String, dynamic>>? points, int shoulder) {
    if (points == null || points.length <= shoulder + 4) return null;
    final vectors = <List<double>>[];
    for (final index in [shoulder, shoulder + 2, shoulder + 4]) {
      final point = points[index];
      for (final confidence in ['visibility', 'presence']) {
        if (point.containsKey(confidence)) {
          final value = point[confidence];
          if (value is! num || !value.isFinite || value < .5 || value > 1) {
            return null;
          }
        }
      }
      final coordinates = <double>[];
      for (final axis in ['x', 'y', 'z']) {
        final coordinate = point[axis];
        if (coordinate is! num || !coordinate.isFinite) return null;
        coordinates.add(coordinate.toDouble());
      }
      vectors.add(coordinates);
    }
    double dot = 0;
    double upperLength = 0;
    double lowerLength = 0;
    for (var axis = 0; axis < 3; axis++) {
      final upper = vectors[0][axis] - vectors[1][axis];
      final lower = vectors[2][axis] - vectors[1][axis];
      dot += upper * lower;
      upperLength += upper * upper;
      lowerLength += lower * lower;
    }
    final denominator = math.sqrt(upperLength * lowerLength);
    if (!denominator.isFinite || denominator < 1e-12) return null;
    return math.acos((dot / denominator).clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

class _Arm {
  final double extensionMin;
  final double flexionMax;
  final double romMin;
  final double returnErrorMax;
  double? value;
  double? baseline;
  double? minimum;
  double? maximum;
  double? readySince;
  double? targetSince;
  bool targetHeld = false;
  double travel = 0;
  double? previous;

  _Arm(this.extensionMin, this.flexionMax, this.romMin, this.returnErrorMax);

  void reset() {
    value = baseline = minimum = maximum = readySince = targetSince = null;
    targetHeld = false;
    travel = 0;
    previous = null;
  }

  void filter(double raw, double? delta) {
    final weight = delta == null
        ? 1.0
        : 1 - math.exp(-delta / ElbowWorldAssessment.filterTauSeconds);
    value = value == null ? raw : value! + weight * (raw - value!);
  }

  void ready(double time) {
    readySince = value! >= extensionMin - ElbowWorldAssessment._convergenceEpsilon
        ? (readySince ?? time)
        : null;
  }

  bool extensionHeld(double time) =>
      readySince != null &&
      time - readySince! >= ElbowWorldAssessment.readyHoldSeconds;

  void begin() {
    baseline = minimum = maximum = value;
    previous = value;
  }

  void track(double time) {
    travel += (value! - previous!).abs();
    previous = value;
    minimum = math.min(minimum!, value!);
    maximum = math.max(maximum!, math.max(baseline!, value!));
    targetSince = value! <= flexionMax + ElbowWorldAssessment._convergenceEpsilon
        ? (targetSince ?? time)
        : null;
    if (progress(time) >= 1) targetHeld = true;
  }

  double progress(double? time) => targetHeld
      ? 1
      : targetSince == null || time == null
      ? 0
      : ((time - targetSince!) / ElbowWorldAssessment.targetHoldSeconds).clamp(
          0.0,
          1.0,
        );

  double get rom => minimum == null ? 0 : maximum! - minimum!;
  double get returnError => (value! - baseline!).abs();
  bool get returned =>
      value! >= extensionMin - ElbowWorldAssessment._convergenceEpsilon &&
      returnError <= returnErrorMax + ElbowWorldAssessment._convergenceEpsilon;
  bool get romReached =>
      rom >= romMin - ElbowWorldAssessment._convergenceEpsilon;
  double get returnFraction =>
      rom <= 0 ? 0 : (1 - returnError / rom).clamp(0.0, 1.0);
  double get smoothness => travel <= 0
      ? 0
      : (100 * (2 * rom - returnError) / travel).clamp(0.0, 100.0);

  Map<String, dynamic> get statistics => {
    'initial_angle': baseline,
    'final_angle': value,
    'minimum_angle': minimum,
    'maximum_angle': maximum,
    'range_of_motion': rom,
    'return_error': returnError,
    'target_reached': targetHeld,
    'extension_held': readySince != null,
    'return_completed': returned,
    'angular_travel': travel,
    'smoothness': smoothness,
  };
}

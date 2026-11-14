import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/exercise_utils.dart';
import 'exercise_rules.dart';
import 'local_test_config.dart';

/// How the target angle for one patient and exercise is chosen.
enum CalibrationMode { standard, adaptive, manual }

/// The doctor's choice, stored at `users/{patient}/calibrations/{exercise}`.
class CalibrationSettings {
  final CalibrationMode mode;
  final double? manualTarget;
  const CalibrationSettings({
    this.mode = CalibrationMode.standard,
    this.manualTarget,
  });

  static const standard = CalibrationSettings();

  factory CalibrationSettings.fromMap(Map<String, dynamic>? data) {
    final mode = CalibrationMode.values.where(
      (value) => value.name == data?['mode'],
    );
    final manual = data?['manualTarget'];
    return CalibrationSettings(
      mode: mode.isEmpty ? CalibrationMode.standard : mode.first,
      manualTarget: manual is num && manual.isFinite ? manual.toDouble() : null,
    );
  }
}

/// The target actually used in a session, recorded on every repetition.
class CalibrationResult {
  final String exercise;

  /// `standard`, `adaptive`, `manual`, `insufficient_history` or `unsupported`.
  final String status;
  final double target;
  final double minimumRom;
  final double standardTarget;
  final double? capability;
  final int repsUsed;
  final int sessionsUsed;

  const CalibrationResult({
    required this.exercise,
    required this.status,
    required this.target,
    required this.minimumRom,
    required this.standardTarget,
    this.capability,
    this.repsUsed = 0,
    this.sessionsUsed = 0,
  });

  bool get personalised => status == 'adaptive' || status == 'manual';

  Map<String, dynamic> toMap() => {
    'status': status,
    'target': double.parse(target.toStringAsFixed(1)),
    'minimumRom': double.parse(minimumRom.toStringAsFixed(1)),
    'standardTarget': standardTarget,
    if (capability != null)
      'capability': double.parse(capability!.toStringAsFixed(1)),
    'repsUsed': repsUsed,
    'sessionsUsed': sessionsUsed,
    'algorithm': PatientCalibration.algorithmVersion,
  };
}

/// Adaptive, patient-specific targets for the angle-rule exercises.
///
/// The patient's capability is a robust high percentile of the peak angle
/// they actually reached in recent sessions (p80 of maxima for exercises that
/// increase the angle, p20 of minima for those that decrease it), so one
/// tracking spike cannot move it. The target is set a small progression step
/// beyond that capability, and is always bounded:
///
/// * never beyond the standard target, so it is never harder or deeper than
///   the default prescription (this also keeps the mini-squat depth limit);
/// * at least [minimumMovement] degrees past the rep-onset angle, so a
///   repetition still requires real movement.
///
/// Elbow flexion/extension and shoulder rotation use thresholds measured from
/// supplied calibration files and are deliberately excluded.
class PatientCalibration {
  static const algorithmVersion = 'adaptive_rom_v1';
  static const minimumReps = 6;
  static const minimumSessions = 2;
  static const historyWindow = Duration(days: 30);
  static const progressionStep = 3.0;
  static const minimumMovement = 15.0;

  static const supportedExercises = {
    kAssistedShoulderFlexion,
    kAssistedElbowFlexionV5,
    kHeelSlide,
    kMiniSquat,
    kSeatedKneeExtension,
    kStraightLegRaise,
    kTerminalKneeExtension,
    kSquat,
  };

  static bool supports(String exercise) =>
      supportedExercises.contains(normalizeExerciseId(exercise));

  /// Pure computation; [history] holds saved repetition records
  /// (`users/{uid}/assessments`).
  static CalibrationResult compute({
    required String exercise,
    required CalibrationSettings settings,
    required List<Map<String, dynamic>> history,
    required DateTime now,
  }) {
    final id = normalizeExerciseId(exercise);
    final rule = ExerciseRule.forExercise(id);
    final standard = CalibrationResult(
      exercise: id,
      status: 'standard',
      target: rule.target,
      minimumRom: rule.minimumRom,
      standardTarget: rule.target,
    );
    if (!supports(id) || rule.relative) {
      return CalibrationResult(
        exercise: id,
        status: 'unsupported',
        target: rule.target,
        minimumRom: rule.minimumRom,
        standardTarget: rule.target,
      );
    }
    final direction = rule.increasing ? 1.0 : -1.0;
    final easiest = rule.enter + direction * minimumMovement;

    double bounded(double value) => rule.increasing
        ? value.clamp(math.min(easiest, rule.target), rule.target).toDouble()
        : value.clamp(rule.target, math.max(easiest, rule.target)).toDouble();

    double romFor(double target) => math.min(
      rule.minimumRom,
      math.max(minimumMovement, 0.8 * (target - rule.enter).abs()),
    );

    switch (settings.mode) {
      case CalibrationMode.standard:
        return standard;
      case CalibrationMode.manual:
        final manual = settings.manualTarget;
        if (manual == null) return standard;
        final target = bounded(manual);
        return CalibrationResult(
          exercise: id,
          status: 'manual',
          target: target,
          minimumRom: romFor(target),
          standardTarget: rule.target,
        );
      case CalibrationMode.adaptive:
        break;
    }

    final peaks = <double>[];
    final sessions = <String>{};
    for (final row in history) {
      if (normalizeExerciseId(row['exercise']?.toString()) != id) continue;
      final created = row['createdAt'];
      final when = created is Timestamp
          ? created.toDate()
          : created is DateTime
          ? created
          : null;
      if (when == null || now.difference(when) > historyWindow) continue;
      final peak = row[rule.increasing ? 'maximumAngle' : 'minimumAngle'];
      if (peak is! num || !peak.isFinite || peak < 0 || peak > 180) continue;
      peaks.add(peak.toDouble());
      final session = row['sessionId'];
      if (session is String && session.isNotEmpty) sessions.add(session);
    }
    if (peaks.length < minimumReps || sessions.length < minimumSessions) {
      return CalibrationResult(
        exercise: id,
        status: 'insufficient_history',
        target: rule.target,
        minimumRom: rule.minimumRom,
        standardTarget: rule.target,
        repsUsed: peaks.length,
        sessionsUsed: sessions.length,
      );
    }
    final capability = percentile(peaks, rule.increasing ? 0.8 : 0.2);
    final target = bounded(capability + direction * progressionStep);
    return CalibrationResult(
      exercise: id,
      status: 'adaptive',
      target: target,
      minimumRom: romFor(target),
      standardTarget: rule.target,
      capability: capability,
      repsUsed: peaks.length,
      sessionsUsed: sessions.length,
    );
  }

  /// Linear-interpolated percentile, [fraction] in 0..1.
  static double percentile(List<double> values, double fraction) {
    final sorted = [...values]..sort();
    if (sorted.length == 1) return sorted.first;
    final position = fraction.clamp(0.0, 1.0) * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }

  /// Loads the doctor's setting and recent history for the signed-in patient.
  /// Any failure falls back to the standard target; it never blocks a session.
  static Future<CalibrationResult> load(String exercise) async {
    final id = normalizeExerciseId(exercise);
    final uid = LocalTestConfig.auth.currentUser?.uid;
    final fallback = compute(
      exercise: id,
      settings: CalibrationSettings.standard,
      history: const [],
      now: DateTime.now(),
    );
    if (uid == null || !supports(id)) return fallback;
    try {
      final user = LocalTestConfig.database.collection('users').doc(uid);
      final settings = CalibrationSettings.fromMap(
        (await user
                .collection('calibrations')
                .doc(id)
                .get()
                .timeout(const Duration(seconds: 3)))
            .data(),
      );
      if (settings.mode != CalibrationMode.adaptive) {
        return compute(
          exercise: id,
          settings: settings,
          history: const [],
          now: DateTime.now(),
        );
      }
      final history = await user
          .collection('assessments')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .get()
          .timeout(const Duration(seconds: 4));
      return compute(
        exercise: id,
        settings: settings,
        history: [for (final doc in history.docs) doc.data()],
        now: DateTime.now(),
      );
    } catch (_) {
      return fallback;
    }
  }

  /// Doctor or admin: set the mode for one patient and exercise.
  static Future<void> saveSettings({
    required String patientId,
    required String exercise,
    required CalibrationMode mode,
    double? manualTarget,
  }) async {
    final uid = LocalTestConfig.auth.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in.');
    await LocalTestConfig.database
        .collection('users')
        .doc(patientId)
        .collection('calibrations')
        .doc(normalizeExerciseId(exercise))
        .set({
          'mode': mode.name,
          if (mode == CalibrationMode.manual) 'manualTarget': manualTarget,
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/screens/auth/health_screening_screen.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/services/exercise_tutorial_service.dart';
import 'package:haemophilia_app/services/lower_body_assessment.dart';
import 'package:haemophilia_app/services/patient_calibration.dart';
import 'package:haemophilia_app/services/session_snapshot_service.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/utils/feedback_translations.dart';

Map<String, dynamic> _rep(
  String exercise,
  String session,
  DateTime when, {
  double? max,
  double? min,
}) => {
  'exercise': exercise,
  'sessionId': session,
  'createdAt': when,
  'maximumAngle': ?max,
  'minimumAngle': ?min,
};

List<Map<String, dynamic>> _pose({double shift = 0, double armLift = 0}) => [
  for (var i = 0; i < 33; i++)
    {'x': 0.5 + shift, 'y': 0.5, 'z': 0.0, 'visibility': 0.0},
]..setAll(11, [
  {'x': 0.40 + shift, 'y': 0.30, 'visibility': 1.0}, // 11 left shoulder
  {'x': 0.60 + shift, 'y': 0.30, 'visibility': 1.0}, // 12 right shoulder
  {'x': 0.35 + shift, 'y': 0.45 - armLift, 'visibility': 1.0}, // 13
  {'x': 0.65 + shift, 'y': 0.45 - armLift, 'visibility': 1.0}, // 14
  {'x': 0.33 + shift, 'y': 0.60 - 2 * armLift, 'visibility': 1.0}, // 15
  {'x': 0.67 + shift, 'y': 0.60 - 2 * armLift, 'visibility': 1.0}, // 16
]) ..setAll(23, [
  {'x': 0.42 + shift, 'y': 0.70, 'visibility': 1.0}, // 23 left hip
  {'x': 0.58 + shift, 'y': 0.70, 'visibility': 1.0}, // 24 right hip
  {'x': 0.42 + shift, 'y': 0.85, 'visibility': 1.0},
  {'x': 0.58 + shift, 'y': 0.85, 'visibility': 1.0},
  {'x': 0.42 + shift, 'y': 0.98, 'visibility': 1.0},
  {'x': 0.58 + shift, 'y': 0.98, 'visibility': 1.0},
]);

void main() {
  final now = DateTime(2026, 10, 30, 10);

  group('patient-specific calibration', () {
    const adaptive = CalibrationSettings(mode: CalibrationMode.adaptive);

    test('standard mode keeps the standard target', () {
      final result = PatientCalibration.compute(
        exercise: kAssistedShoulderFlexion,
        settings: CalibrationSettings.standard,
        history: const [],
        now: now,
      );
      expect(result.status, 'standard');
      expect(result.target, 150);
      expect(result.personalised, isFalse);
    });

    test('adaptive needs enough reps across at least two sessions', () {
      final history = [
        for (var i = 0; i < 10; i++)
          _rep(kAssistedShoulderFlexion, 's1', now, max: 110),
      ];
      final result = PatientCalibration.compute(
        exercise: kAssistedShoulderFlexion,
        settings: adaptive,
        history: history,
        now: now,
      );
      expect(result.status, 'insufficient_history');
      expect(result.target, 150);
    });

    test('adaptive target is a small step beyond recent capability', () {
      final history = [
        for (var i = 0; i < 10; i++)
          _rep(
            kAssistedShoulderFlexion,
            i.isEven ? 's1' : 's2',
            now.subtract(const Duration(days: 2)),
            max: 100 + i.toDouble(),
          ),
      ];
      final result = PatientCalibration.compute(
        exercise: kAssistedShoulderFlexion,
        settings: adaptive,
        history: history,
        now: now,
      );
      expect(result.status, 'adaptive');
      expect(result.capability, closeTo(107.2, 0.01));
      expect(result.target, closeTo(110.2, 0.01));
      expect(result.target, lessThanOrEqualTo(result.standardTarget));
      expect(result.minimumRom, lessThanOrEqualTo(75));
    });

    test('adaptive never exceeds the standard target or drops below onset', () {
      final strong = [
        for (var i = 0; i < 8; i++)
          _rep(kAssistedShoulderFlexion, 's$i', now, max: 175),
      ];
      expect(
        PatientCalibration.compute(
          exercise: kAssistedShoulderFlexion,
          settings: adaptive,
          history: strong,
          now: now,
        ).target,
        150,
      );
      final weakSquat = [
        for (var i = 0; i < 8; i++) _rep(kMiniSquat, 's$i', now, min: 160),
      ];
      final squat = PatientCalibration.compute(
        exercise: kMiniSquat,
        settings: adaptive,
        history: weakSquat,
        now: now,
      );
      // Decreasing exercise: target stays between standard (130) and
      // onset (150) minus the minimum movement.
      expect(squat.target, inInclusiveRange(130, 135));
    });

    test('old, foreign and implausible records are ignored', () {
      final history = [
        for (var i = 0; i < 8; i++)
          _rep(
            kAssistedShoulderFlexion,
            's$i',
            now.subtract(const Duration(days: 45)),
            max: 100,
          ),
        for (var i = 0; i < 8; i++) _rep(kHeelSlide, 's$i', now, min: 100),
        for (var i = 0; i < 8; i++)
          _rep(kAssistedShoulderFlexion, 's$i', now, max: 400),
      ];
      expect(
        PatientCalibration.compute(
          exercise: kAssistedShoulderFlexion,
          settings: adaptive,
          history: history,
          now: now,
        ).status,
        'insufficient_history',
      );
    });

    test('manual target is clamped to safe bounds', () {
      final result = PatientCalibration.compute(
        exercise: kAssistedShoulderFlexion,
        settings: const CalibrationSettings(
          mode: CalibrationMode.manual,
          manualTarget: 170,
        ),
        history: const [],
        now: now,
      );
      expect(result.status, 'manual');
      expect(result.target, 150);
    });

    test('measured-threshold exercises are not calibrated', () {
      for (final exercise in [kElbowFlexionExtension, kShoulderRotation]) {
        final result = PatientCalibration.compute(
          exercise: exercise,
          settings: adaptive,
          history: const [],
          now: now,
        );
        expect(result.status, 'unsupported');
        expect(result.personalised, isFalse);
      }
    });

    test('rule engines use the personalised target', () {
      const calibration = CalibrationResult(
        exercise: kAssistedShoulderFlexion,
        status: 'adaptive',
        target: 120,
        minimumRom: 50,
        standardTarget: 150,
      );
      final upper = ExerciseRulesAssessment(
        kAssistedShoulderFlexion,
        calibration: calibration,
      );
      expect(upper.rule.target, 120);
      expect(upper.rule.minimumRom, 50);
      expect(ExerciseRulesAssessment(kAssistedShoulderFlexion).rule.target, 150);

      const squat = CalibrationResult(
        exercise: kMiniSquat,
        status: 'manual',
        target: 140,
        minimumRom: 15,
        standardTarget: 130,
      );
      final lower = LowerBodyAssessment(kMiniSquat, calibration: squat);
      expect(lower.rule.target, 140);
    });
  });

  group('representative snapshot selection', () {
    test('pose vectors are invariant to translation', () {
      final a = RepresentativeSelector.poseVector(_pose())!;
      final b = RepresentativeSelector.poseVector(_pose(shift: 0.1))!;
      expect(RepresentativeSelector.distance(a, b), closeTo(0, 1e-9));
    });

    test('no torso means no vector', () {
      final hidden = _pose();
      hidden[23] = {'x': 0.4, 'y': 0.7, 'visibility': 0.1};
      expect(RepresentativeSelector.poseVector(hidden), isNull);
    });

    test('selects the medoid and its closest match, preferring correct form', () {
      final poses = [
        RepresentativeSelector.poseVector(_pose(armLift: 0.00))!,
        RepresentativeSelector.poseVector(_pose(armLift: 0.10))!,
        RepresentativeSelector.poseVector(_pose(armLift: 0.11))!,
        RepresentativeSelector.poseVector(_pose(armLift: 0.12))!,
        RepresentativeSelector.poseVector(_pose(armLift: 0.30))!,
      ];
      final chosen = RepresentativeSelector.select(poses);
      expect(chosen.first, 2);
      expect(chosen, hasLength(2));
      expect([1, 3], contains(chosen.last));

      final preferred = RepresentativeSelector.select(
        poses,
        preferred: [true, false, false, false, true],
      );
      expect(preferred.toSet(), {0, 4});
    });

    test('a single frame is returned alone', () {
      expect(
        RepresentativeSelector.select([
          RepresentativeSelector.poseVector(_pose())!,
        ]),
        [0],
      );
      expect(RepresentativeSelector.select(const []), isEmpty);
    });

    test('day keys are zero-padded dates', () {
      expect(SessionSnapshotService.dayKey(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('exercise tutorials', () {
    test('accepts common YouTube link forms and canonicalises them', () {
      for (final link in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/watch?v=dQw4w9WgXcQ&t=30s',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ?si=abc',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
      ]) {
        expect(
          ExerciseTutorialService.parseVideoId(link),
          'dQw4w9WgXcQ',
          reason: link,
        );
      }
      expect(
        ExerciseTutorialService.canonicalUrl('dQw4w9WgXcQ'),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('rejects non-YouTube, insecure and malformed links', () {
      for (final link in [
        'http://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://evil.example/watch?v=dQw4w9WgXcQ',
        'https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=short',
        'javascript:alert(1)',
        '',
      ]) {
        expect(ExerciseTutorialService.parseVideoId(link), isNull, reason: link);
      }
    });
  });

  testWidgets('screening prefills the age and sex given at registration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: HealthScreeningScreen(initialAge: 24, initialGender: 'Male'),
      ),
    );
    expect(find.widgetWithText(TextField, '24'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.text('Do you bleed longer than others after minor cuts?'),
      findsOneWidget,
    );
  });

  test('new Hindi strings are present for every key', () {
    expect(feedbackHindi.values.every((v) => v.trim().isNotEmpty), isTrue);
  });
}

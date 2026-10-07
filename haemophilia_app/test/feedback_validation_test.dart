import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:haemophilia_app/utils/account_validation.dart';
import 'package:haemophilia_app/services/session_feedback_service.dart';
import 'package:haemophilia_app/widgets/exercise_demo/exercise_demo.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';

void main() {
  test('shoulder rotation is listed without the work-in-progress label', () {
    expect(isWorkInProgressExercise('shoulder_rotation'), isFalse);
    expect(isWorkInProgressExercise('Shoulder Rotation'), isFalse);
  });

  test('session feedback is grounded in available metrics', () {
    final feedback = generateSessionFeedback(
      total: 4,
      correct: 3,
      target: 3,
      status: 'completed',
      issues: const {},
      exercises: const {'Shoulder Rotation': (3, 4)},
    );
    expect(feedback.brief, contains('3 of 4'));
      expect(feedback.doctorDetails.join(' '), contains('do not establish'));
  });
  test(
    'mobile validation rejects malformed local and India country-code numbers',
    () {
      for (final value in ['9876543210', '+91 98765 43210', '+14155552671']) {
        expect(mobileValidation(value), isNull);
      }
      for (final value in [
        '',
        '1234567890',
        '+911234567890',
        '+91987654321',
        '98765432100',
      ]) {
        expect(mobileValidation(value), isNotNull);
      }
      expect(passwordValidation('abcdefgh'), isNotNull);
      expect(passwordValidation('12345678'), isNotNull);
      expect(passwordValidation('abc123'), isNotNull);
      expect(passwordValidation('Abcdef12!'), isNull);
    },
  );
  test('feedback distinguishes missing observations, unfinished targets and completed targets', () {
    SessionFeedback report(
      int total,
      int correct,
      int target, {
      bool hindi = false,
    }) => generateSessionFeedback(
      total: total,
      correct: correct,
      target: target,
      status: 'paused',
      issues: {'Trunk compensation': 2},
      exercises: {},
      hindi: hindi,
    );
    expect(report(0, 0, 10).brief, contains('not enough information'));
    final partial = report(6, 4, 10);
    expect(partial.brief, contains('4 of 6'));
    expect(partial.brief, contains('not reached'));
    expect(partial.patientDetails.join(' '), contains('stopped or paused'));
    expect(partial.doctorDetails.join(' '), contains('Trunk compensation (2'));
    expect(report(10, 10, 10).brief, contains('target was reached'));
    expect(report(6, 4, 10, hindi: true).brief, contains('लक्ष्य'));
  });
  testWidgets(
    'exercise demonstration controls fit a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ExerciseDemo(
                    exerciseId: 'shoulder_rotation',
                    isDark: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

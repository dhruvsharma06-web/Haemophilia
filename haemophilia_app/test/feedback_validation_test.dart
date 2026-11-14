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
    'new movement-rule flags become readable report feedback in both languages',
    () {
      for (final hindi in [false, true]) {
        final report = generateSessionFeedback(
          total: 3,
          correct: 1,
          target: 3,
          status: 'completed',
          issues: {'TARGET_NOT_HELD': 2, 'SUPPORT_MISSING': 1},
          exercises: {},
          hindi: hindi,
        );
        expect(
          report.doctorDetails.join(' '),
          isNot(contains('TARGET_NOT_HELD')),
        );
        expect(
          report.patientDetails.join(' '),
          contains(hindi ? 'आरामदायक सीमा' : 'comfortable range'),
        );
        expect(
          report.patientDetails.join(' '),
          contains(hindi ? 'सहारा' : 'supporting'),
        );
      }
    },
  );
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
      expect(passwordValidation('Mango#47Rq'), isNull);
    },
  );
  group('password policy', () {
    test('accepts passwords without patterns', () {
      for (final value in ['Mango#47Rq', 'tulip9Vexed', 'B7k!rWq2zp']) {
        expect(passwordValidation(value), isNull, reason: value);
      }
    });
    test('six characters fail with the same 8-character message shown in the hint', () {
      expect(passwordValidation('Ab9#kq'), passwordTooShortMessage);
      expect(passwordRequirementsHint, contains('$passwordMinLength'));
    });
    test('blocks consecutive sequences, keyboard runs and repeats', () {
      for (final value in [
        'Abcdef12!',
        'Rohit@1234',
        'Zebra9cba!',
        'Wq7xyzPlum',
        'Plum4qwerT',
      ]) {
        expect(passwordValidation(value), passwordSequenceMessage, reason: value);
      }
      expect(passwordValidation('Tiger7aaaQ'), passwordRepeatMessage);
      expect(passwordValidation('Lamp222Zeb'), passwordRepeatMessage);
    });
    test('blocks common words and personal details', () {
      expect(passwordValidation('P@ssw0rd97'), passwordCommonMessage);
      expect(passwordValidation('Somaiya#97'), passwordCommonMessage);
      expect(
        passwordValidation('Kavya#97Lm', email: 'kavya.r@example.com'),
        passwordPersonalMessage,
      );
      expect(
        passwordValidation('Mehra#97Lm', name: 'Ravi Mehra'),
        passwordPersonalMessage,
      );
    });
  });
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

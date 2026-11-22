import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/models/user_model.dart';
import 'package:haemophilia_app/screens/profile/edit_profile_screen.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/services/shoulder_rotation_assessment.dart';
import 'package:haemophilia_app/utils/admin_account_policy.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/widgets/exercise_demo/exercise_demo_dialog.dart';
import 'package:haemophilia_app/widgets/exercise_demo/exercise_demo_model.dart';
import 'package:haemophilia_app/widgets/exercise_thresholds.dart';

void main() {
  setUp(() => AppLocaleService.currentLocale.value = 'en');
  tearDown(() => AppLocaleService.currentLocale.value = 'en');

  test('all catalog entries use matching rules and demonstrations', () {
    expect(ExerciseRule.catalog.map((r) => r.id).toSet().length, 10);
    for (final rule in ExerciseRule.catalog) {
      final demo = ExerciseDemoRegistry.get(rule.id);
      expect(normalizeExerciseId(demo.exerciseId), rule.id);
      expect(demo.phases, isNotEmpty);
      expect(demo.keyTips, isNotEmpty);
      expect(rule.thresholdSummary, isNotEmpty);
    }
    final shoulder = ExerciseRule.forExercise(kShoulderRotation);
    expect(shoulder.enter, ShoulderRotationAssessment.appOnsetDegrees);
    expect(shoulder.target, ShoulderRotationAssessment.extremeDegrees);
    expect(
      shoulder.returnBand,
      ShoulderRotationAssessment.appReturnBandDegrees,
    );
  });

  test('static UI copy and every exercise demonstration have Hindi text', () {
    final keys = <String>{};
    final pattern = RegExp(r'''\btr\(\s*(['"])((?:\\.|(?!\1).)*?)\1''');
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        final key = match[2]!;
        if (key.contains(r'$') || key.contains(r'\')) continue;
        keys.add(key);
      }
    }
    for (final rule in ExerciseRule.catalog) {
      final demo = ExerciseDemoRegistry.get(rule.id);
      keys.addAll([demo.displayName, ...demo.keyTips, ...rule.postureGuidance]);
      for (final phase in demo.phases) {
        keys.addAll([phase.title, phase.description]);
      }
    }
    keys.addAll(
      ['patient', 'doctor', 'pending_doctor', 'admin'].map(managedRoleLabel),
    );
    AppLocaleService.currentLocale.value = 'hi';
    expect(keys.length, greaterThan(500));
    expect(keys.where((key) => tr(key) == key), isEmpty);
  });

  test('numeric movement feedback translates while preserving every measured value', () {
    const messages = [
      'Keep both elbows bent between 60 and 120 degrees.',
      'Keep your upper arms within 20 degrees of your torso.',
      'Keep your torso upright; lean stayed over 12 degrees.',
      'Keep your torso steady front to back; lean changed by more than 10 degrees.',
      'Do not twist your torso; shoulder line turned more than 10 degrees.',
      'Keep the wand level; it tilted more than 10 degrees.',
      'Move both arms together; they differed by more than 15 degrees.',
      'Left elbow did not hold at or below 70.76 deg for 0.2s.',
      'Right elbow range was below 70.02 deg.',
      'Left elbow must return to at least 152.59 deg and within 7.76 deg of its start, held 0.2s.',
      'Arm angle difference exceeded 34.76 deg.',
      'Arm range difference exceeded 31.30 deg.',
    ];
    final numbers = RegExp(r'\d+(?:\.\d+)?');
    AppLocaleService.currentLocale.value = 'hi';
    for (final message in messages) {
      final translated = tr(message);
      expect(translated, isNot(message));
      expect(RegExp(r'[\u0900-\u097f]').hasMatch(translated), true);
      expect(
        numbers.allMatches(translated).map((m) => m[0]),
        numbers.allMatches(message).map((m) => m[0]),
      );
    }
  });

  test('movement stages are patient-readable in both languages', () {
    const stages = [
      'POSITIONING',
      'CENTRE',
      'READY',
      'FLEXING',
      'BENDING',
      'EXTENDING',
      'ROTATING_OUT',
      'RETURNING',
      'NEED_CENTRE',
      'BACK_TO_CENTRE',
      'TARGET_REACHED',
      'RAISING',
      'LOWERING',
      'RISING',
    ];
    for (final language in ['en', 'hi']) {
      AppLocaleService.currentLocale.value = language;
      for (final stage in stages) {
        expect(movementStageLabel(stage), isNot(stage));
        expect(movementStageLabel(stage), isNot(contains('_')));
      }
    }
  });

  for (final language in ['en', 'hi']) {
    testWidgets('profile fields validate before saving in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLocaleService.currentLocale.value = language;
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            user: UserModel(
              uid: 'local-test',
              name: 'Test Patient',
              email: 'test@example.com',
              role: 'patient',
              age: 28,
              gender: 'Male',
              phoneNumber: '9876543210',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final fields = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(fields.at(1)).enabled, false);
      await tester.enterText(fields.at(0), '');
      await tester.enterText(fields.at(2), '121');
      await tester.enterText(fields.at(3), '123');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, tr('Save Changes')),
      );
      await tester.tap(find.widgetWithText(FilledButton, tr('Save Changes')));
      await tester.pump();
      expect(find.text(tr('Please enter your full name')), findsOneWidget);
      expect(
        find.text(tr('Please enter a sensible age (up to 120)')),
        findsOneWidget,
      );
      expect(find.text(tr('Saving...')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    for (final width in [320.0, 390.0, 1024.0]) {
      testWidgets(
        'all threshold panels fit $width with large text in $language',
        (tester) async {
          tester.view.physicalSize = Size(width, 780);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          AppLocaleService.currentLocale.value = language;
          for (final rule in ExerciseRule.catalog) {
            for (final compact in [false, true]) {
              await tester.pumpWidget(
                MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.4)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ExerciseThresholds(
                          exercise: rule.id,
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${rule.id} compact=$compact',
              );
              if (language == 'hi') {
                expect(
                  RegExp(r'[\u0900-\u097f]')
                      .hasMatch(localizedThresholds(rule)),
                  true,
                );
              }
            }
          }
        },
      );
    }

    testWidgets(
      'personalized targets appear in the panel and tutorial in $language',
      (tester) async {
        AppLocaleService.currentLocale.value = language;
        final custom = ExerciseRule.forExercise(kAssistedElbowFlexionV5)
            .withTarget(110, 20);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showExerciseDemoDialog(
                    context,
                    exerciseName: kAssistedElbowFlexionV5,
                    ruleOverride: custom,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('110'), findsOneWidget);
        expect(
          tester
              .widget<ExerciseThresholds>(find.byType(ExerciseThresholds))
              .ruleOverride,
          custom,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a rule from another exercise cannot replace the displayed target',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseThresholds(
              exercise: kAssistedElbowFlexionV5,
              compact: true,
              ruleOverride: ExerciseRule.forExercise(kAssistedShoulderFlexion),
            ),
          ),
        ),
      );
      expect(find.textContaining('90'), findsOneWidget);
      expect(find.textContaining('150'), findsNothing);
    },
  );
}

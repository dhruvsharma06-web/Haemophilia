import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';
import 'package:haemophilia_app/widgets/exercise_demo/exercise_demo_dialog.dart';
import 'package:haemophilia_app/widgets/exercise_demo/exercise_demo.dart';
import 'package:haemophilia_app/widgets/exercise_thresholds.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';

void main() {
  for (final language in ['en', 'hi']) {
    testWidgets('threshold tutorial fits 320px with large text in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      AppLocaleService.currentLocale.value = language;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => AppLocaleService.currentLocale.value = 'en');
      for (final exercise in ExerciseRule.catalog.map((r) => r.id)) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showExerciseDemoDialog(context, exerciseName: exercise),
                  child: const Text('Open tutorial'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open tutorial'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: exercise);
        expect(
          tester
              .widget<ExerciseThresholds>(find.byType(ExerciseThresholds))
              .compact,
          true,
        );
        expect(
          tester.getTopLeft(find.byType(ExerciseDemo)).dy,
          lessThan(tester.getTopLeft(find.byType(ExerciseThresholds)).dy),
        );
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}

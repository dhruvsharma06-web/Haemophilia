import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/utils/schedule_utils.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';
import 'package:haemophilia_app/widgets/rep_movement_stats.dart';
import 'package:flutter/material.dart';

void main() {
  final start = DateTime.utc(2026, 10, 7, 9);
  testWidgets(
    'new movement statistics fit narrow screens in English and Hindi',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['en', 'hi']) {
        AppLocaleService.currentLocale.value = language;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: RepMovementStats(
                  rep: {
                    'hand': 'Left',
                    'minimumAngle': 60,
                    'maximumAngle': 160,
                    'smoothness': 81,
                    'returnCompletion': 95,
                    'angularSpeed': 33,
                    'scoreKind': 'descriptive_movement_control',
                  },
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('81/100'), findsOneWidget);
      }
      AppLocaleService.currentLocale.value = 'en';
    },
  );
  test(
    'all unfinished states stop at one hour even with a longer saved expiry',
    () {
      for (final status in unfinishedSessionStatuses) {
        final data = <String, dynamic>{
          'status': status,
          'scheduledAt': start,
          'expiresAt': start.add(const Duration(days: 1)),
        };
        expect(
          assignmentAvailable(
            data,
            start.add(const Duration(minutes: 59, seconds: 59)),
          ),
          true,
        );
        expect(
          assignmentAvailable(data, start.add(const Duration(hours: 1))),
          false,
        );
        expect(sessionExpired(data, start.add(const Duration(hours: 1))), true);
        expect(
          assignmentAvailable(data, start.subtract(const Duration(seconds: 1))),
          false,
        );
      }
    },
  );
  test(
    'legacy creation time works; absent clock never gives unlimited access',
    () {
      expect(
        sessionExpiry({'createdAt': start}),
        start.add(const Duration(hours: 1)),
      );
      expect(assignmentAvailable({'status': 'paused'}, start), false);
      expect(
        assignmentAvailable({
          'status': 'cancelled',
          'scheduledAt': start,
        }, start),
        false,
      );
      expect(
        assignmentAvailable({
          'status': 'completed',
          'scheduledAt': start,
        }, start),
        false,
      );
    },
  );
  test('legacy identity does not change when a recording starts', () {
    final data = <String, dynamic>{'createdAt': start};
    final key = assignmentKey(data);
    data['sessionId'] = 'patient_recording';
    expect(assignmentKey(data), key);
  });
  test('malformed legacy clocks are unavailable without crashing', () {
    for (final value in ['not a timestamp', 123, <String, dynamic>{}]) {
      final data = <String, dynamic>{
        'status': 'paused',
        'scheduledAt': value,
        'expiresAt': value,
      };
      expect(assignmentAvailable(data, start), false);
      expect(sessionExpired(data, start), true);
    }
  });
  test('old assisted elbow prescriptions resolve to the trained option', () {
    expect(
      normalizeExerciseId('assisted_elbow_flexion'),
      kAssistedElbowFlexionV5,
    );
  });
  test(
    'compound movement feedback translates with measured numbers preserved',
    () {
      AppLocaleService.currentLocale.value = 'hi';
      final text = tr(
        'Model accepted this movement. Measured elbow movement: 80 degrees in 3.1 seconds.',
      );
      expect(text, contains('80'));
      expect(text, contains('3.1'));
      expect(text, isNot(contains('Measured elbow movement')));
      AppLocaleService.currentLocale.value = 'en';
    },
  );
}

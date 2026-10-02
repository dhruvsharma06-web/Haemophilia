import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/utils/schedule_utils.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';
import 'package:haemophilia_app/widgets/consent_form.dart';
import 'package:haemophilia_app/widgets/session_safety_dialog.dart';
import 'package:haemophilia_app/widgets/app_text.dart';
import 'package:haemophilia_app/screens/patient/session_reports_screen.dart';
import 'package:haemophilia_app/screens/auth/health_screening_screen.dart';

void main() {
  setUp(() => AppLocaleService.currentLocale.value = 'en');
  tearDown(() => AppLocaleService.currentLocale.value = 'en');
  testWidgets('screening requires explicit demographic and symptom answers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: HealthScreeningScreen()));
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.text('Please answer the question above before proceeding.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Male'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.text('Do you bleed longer than others after minor cuts?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.text('Please answer the question above before proceeding.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Never'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.text(
        'Have you experienced excessive bleeding after surgery or stitches?',
      ),
      findsOneWidget,
    );
  });
  test(
    'week schedule keeps selected weekdays, local time and year boundary',
    () {
      final dates = scheduledOccurrences(
        start: DateTime(2026, 12, 30, 10, 15),
        days: 7,
        weekdays: {1, 3, 5},
      );
      expect(dates.map((d) => d.weekday), [3, 5, 1]);
      expect(dates.last.year, 2027);
      expect(dates.every((d) => d.hour == 10 && d.minute == 15), true);
    },
  );
  test('scheduling validates duration and weekday choices', () {
    expect(
      () => scheduledOccurrences(start: DateTime(2026), days: 0, weekdays: {1}),
      throwsArgumentError,
    );
    expect(
      () =>
          scheduledOccurrences(start: DateTime(2026), days: 367, weekdays: {1}),
      throwsArgumentError,
    );
    expect(
      () => scheduledOccurrences(start: DateTime(2026), days: 7, weekdays: {8}),
      throwsArgumentError,
    );
    expect(
      () => scheduledOccurrences(start: DateTime(2026), days: 7, weekdays: {}),
      throwsArgumentError,
    );
  });
  test('sessions appear only when due, but paused sessions remain resumable after expiry', () {
    final now = DateTime(2026, 10, 2, 12);
    final data = {
      'status': 'assigned',
      'scheduledAt': Timestamp.fromDate(now.add(const Duration(minutes: 1))),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 1))),
    };
    expect(assignmentAvailable(data, now), false);
    data['scheduledAt'] = Timestamp.fromDate(now);
    expect(assignmentAvailable(data, now), true);
    data['expiresAt'] = Timestamp.fromDate(now);
    expect(assignmentAvailable(data, now), false);
    data['status'] = 'paused';
    expect(assignmentAvailable(data, now), true);
  });
  testWidgets('terms required; research remains optional and camera consent is separate', (
    tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConsentForm(
              onAccept: (research) async {
                accepted = research;
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.pump();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(accepted, false);
  });
  testWidgets(
    'recording is blocked until both safety confirmations are checked',
    (tester) async {
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  accepted = await confirmSessionSafety(context);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start session'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start session'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Start session'));
      await tester.pumpAndSettle();
      expect(accepted, true);
    },
  );
  testWidgets('constant interface text updates when Hindi is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppText('Before you start'))),
    );
    expect(find.text('Before you start'), findsOneWidget);
    AppLocaleService.currentLocale.value = 'hi';
    await tester.pump();
    expect(find.text('शुरू करने से पहले'), findsOneWidget);
  });
  testWidgets(
    'report shows cumulative totals and readable date in both languages',
    (tester) async {
      final data = {
        'sessionName': 'Morning session',
        'status': 'paused',
        'startedAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
        'report': {
          'totalReps': 7,
          'correctReps': 5,
          'averageScore': 80,
          'averageRangeOfMotion': 95,
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SessionReportCard(data: data)),
        ),
      );
      expect(find.textContaining('02/10/2026'), findsOneWidget);
      expect(find.text('Completed Reps: 7'), findsOneWidget);
      AppLocaleService.currentLocale.value = 'hi';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SessionReportCard(data: data)),
        ),
      );
      expect(find.textContaining('80'), findsOneWidget);
      expect(find.textContaining('95°'), findsOneWidget);
    },
  );
}

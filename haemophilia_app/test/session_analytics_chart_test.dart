import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/models/assessment_session.dart';
import 'package:haemophilia_app/widgets/session_analytics_chart.dart';

void main() {
  testWidgets('confidence is shown only when a session has a measured value', (
    tester,
  ) async {
    Future<void> showSession(Map<String, dynamic> rep) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionAnalyticsChart(
              sessions: [
                AssessmentSession(
                  id: 'demo',
                  exercise: 'heel_slide',
                  sessionName: 'Demo session',
                  date: DateTime(2026, 11, 27),
                  repsData: [rep],
                ),
              ],
            ),
          ),
        ),
      );
    }

    await showSession({'form': 'correct', 'score': 80});
    expect(find.text('AI Confidence: 0%'), findsNothing);

    await showSession({'form': 'correct', 'score': 80, 'confidence': 0});
    expect(find.text('AI Confidence: 0%'), findsOneWidget);
  });
}

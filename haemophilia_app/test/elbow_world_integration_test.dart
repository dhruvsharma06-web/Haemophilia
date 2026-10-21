import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/services/elbow_world_assessment.dart';
import 'package:haemophilia_app/services/local_pose_service.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/widgets/exercise_thresholds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hemo/local_pose');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('threshold constants exactly match the supplied source JSON', () {
    final reference = jsonDecode(File('../docs/calibration/elbow-flexion-extension.json').readAsStringSync()) as Map;
    expect(ElbowWorldAssessment.thresholds, reference['thresholds']);
    expect(ElbowWorldAssessment.sourceSessionId, reference['source_session_id']);
    expect(ElbowWorldAssessment.provenance, reference['status']);
  });

  test('only ordinary elbow exercise selects MediaPipe world tracking', () async {
    // LocalPoseService rejects non-Android platforms, so the override is
    // scoped to this test rather than the shared setUp: flutter_test asserts
    // that debug globals are restored before a widget test's body completes.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = LocalPoseService();
    for (final rule in ExerciseRule.catalog) {
      await service.initialize(rule.id);
      expect(calls.last.method, 'initialize');
      expect(
        calls.last.arguments['worldPose'],
        rule.id == kElbowFlexionExtension,
        reason: rule.id,
      );
    }
  });

  test('elbow dispatcher never falls back to image-space angles', () {
    final engine = ExerciseRulesAssessment(kElbowFlexionExtension);
    final landmarks = List.generate(
      33,
      (_) => <String, dynamic>{'x': .5, 'y': .5, 'z': 0.0, 'visibility': 1.0},
    );
    final state = engine.update(landmarks, 1000, 1000, 0);
    expect(state['tracking_valid'], false);
    expect(state['rep_count'], 0);
    expect(state['landmarks'], landmarks);
    expect(state['form'], isNot('correct'));
  });

  for (final compact in [false, true]) {
    testWidgets('elbow threshold panel shows candidate targets compact=$compact', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExerciseThresholds(
        exercise: kElbowFlexionExtension,
        compact: compact,
      ))));
      expect(find.textContaining('Person-specific candidate'), findsOneWidget);
      expect(find.text(localizedThresholds(ExerciseRule.forExercise(kElbowFlexionExtension))), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

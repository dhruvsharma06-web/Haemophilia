import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/widgets/exercise_demo/assisted_elbow_flexion_painter.dart';
import 'package:haemophilia_app/widgets/exercise_demo/elbow_flexion_painter.dart';
import 'package:haemophilia_app/widgets/exercise_demo/lower_body_painter.dart';

List<(Offset, Offset)> lines(CustomPainter painter, Size size, double stroke) {
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, size);
  return [
    for (final recorded in canvas.invocations)
      if (recorded.invocation.memberName == #drawLine &&
          (recorded.invocation.positionalArguments[2] as Paint).strokeWidth ==
              stroke)
        (
          recorded.invocation.positionalArguments[0] as Offset,
          recorded.invocation.positionalArguments[1] as Offset,
        ),
  ];
}

double joint(Offset a, Offset b, Offset c) =>
    ExerciseRulesAssessment.angle([a.dx, a.dy], [b.dx, b.dy], [c.dx, c.dy])!;

List<Map<String, dynamic>> lowerDemoPose(String id, double progress) {
  final segments = lines(
    LowerBodyPainter(exercise: id, progress: progress),
    const Size(360, 300),
    9,
  );
  final p = List.generate(
    33,
    (_) => <String, dynamic>{'x': .5, 'y': .5, 'z': 0.0, 'visibility': .1},
  );
  final points = {
    11: segments[0].$1,
    23: segments[0].$2,
    25: segments[1].$2,
    27: segments[2].$2,
    29: segments[2].$2,
  };
  for (final entry in points.entries) {
    p[entry.key] = {
      'x': entry.value.dx / 360,
      'y': entry.value.dy / 300,
      'z': 0.0,
      'visibility': .99,
    };
  }
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final rule in ExerciseRule.catalog.where((r) => !r.isUpperBody)) {
    test(
      '${rule.id}: following the actual animation counts one correct cycle',
      () {
        final engine = ExerciseRulesAssessment(rule.id);
        final progress = [
          ...List.filled(8, 0.0),
          for (var i = 1; i <= 16; i++) .2 + .3 * i / 16,
          ...List.filled(8, .55),
          for (var i = 1; i <= 16; i++) .6 + .35 * i / 16,
          ...List.filled(10, 1.0),
        ];
        final reps = <Map>[];
        for (var i = 0; i < progress.length; i++) {
          final state = engine.update(
            lowerDemoPose(rule.id, progress[i]),
            360,
            300,
            i * .08,
          );
          if (state['completed_rep'] is Map) reps.add(state['completed_rep']);
        }
        expect(reps, hasLength(1));
        expect(reps.single['form'], 'correct');
        expect(reps.single['score'], greaterThan(80));
      },
    );
  }
  test('mini squat demonstration reaches the source branch 130-degree target', () {
    final s = lines(
      LowerBodyPainter(exercise: kMiniSquat, progress: .55),
      const Size(360, 300),
      9,
    );
    expect(joint(s[1].$1, s[1].$2, s[2].$2), closeTo(130, .01));
  });
  test(
    'ordinary curl bends both elbows forward with stationary upper arms',
    () {
      final rest = lines(
        const ElbowFlexionPainter(progress: 0),
        const Size(270, 255),
        5,
      );
      final peak = lines(
        const ElbowFlexionPainter(progress: .55),
        const Size(270, 255),
        5,
      );
      expect(rest, hasLength(4));
      expect(peak, hasLength(4));
      for (final i in [0, 2]) {
        expect(
          joint(rest[i].$1, rest[i].$2, rest[i + 1].$2),
          closeTo(165, .01),
        );
        expect(joint(peak[i].$1, peak[i].$2, peak[i + 1].$2), closeTo(55, .01));
        expect(peak[i], rest[i]);
        expect(peak[i + 1].$2.dx, greaterThan(peak[i].$2.dx));
        expect(peak[i + 1].$2.dy, lessThan(peak[i].$2.dy));
      }
    },
  );
  test('assisted curl begins extended, bends up, and maintains support', () {
    final rest = lines(
      const AssistedElbowFlexionPainter(progress: 0),
      const Size(260, 260),
      5,
    );
    final peak = lines(
      const AssistedElbowFlexionPainter(progress: .55),
      const Size(260, 260),
      5,
    );
    expect(joint(rest[0].$1, rest[0].$2, rest[1].$2), closeTo(160, .01));
    expect(joint(peak[0].$1, peak[0].$2, peak[1].$2), closeTo(60, .01));
    final support = lines(
      const AssistedElbowFlexionPainter(progress: .55),
      const Size(260, 260),
      4,
    ).last.$2;
    expect((support - peak[1].$2).distance, lessThan(6));
  });
  testWidgets(
    'render all lower-body start and target poses for visual review',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const exercises = [
        kHeelSlide,
        kMiniSquat,
        kSeatedKneeExtension,
        kStraightLegRaise,
        kTerminalKneeExtension,
        kSquat,
      ];
      canvas.drawColor(Colors.white, BlendMode.src);
      for (var i = 0; i < exercises.length; i++) {
        for (var j = 0; j < 2; j++) {
          canvas.save();
          canvas.translate(j * 360.0, i * 300.0);
          LowerBodyPainter(
            exercise: exercises[i],
            progress: j == 0 ? 0 : .55,
            isDark: false,
          ).paint(canvas, const Size(360, 300));
          canvas.restore();
        }
      }
      // Rendering checks the same painter code used by the app; not a camera accuracy test.
      await tester.runAsync(() async {
        final image = await recorder.endRecording().toImage(720, 1800);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        final path = Platform.environment['DEMO_REVIEW_PATH'];
        if (path != null) {
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
        }
        image.dispose();
      });
    },
  );
}

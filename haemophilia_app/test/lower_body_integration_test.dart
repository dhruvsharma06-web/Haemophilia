import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';
import 'package:haemophilia_app/widgets/exercise_demo/exercise_demo_model.dart';
import 'package:haemophilia_app/widgets/exercise_demo/lower_body_painter.dart';

void main() {
  const lower = [kHeelSlide, kMiniSquat, kSeatedKneeExtension,
    kStraightLegRaise, kTerminalKneeExtension, kSquat];

  test('ten exercises retain current elbow model and all six new movements', () {
    expect(kAllExercises.map((e) => e.id).toSet().length, 10);
    expect(normalizeExerciseId('assisted_elbow_flexion'), kAssistedElbowFlexionV5);
    for (final id in lower) {
      expect(kAllExercises.any((e) => e.id == id), true);
      expect(isWorkInProgressExercise(id), false);
      expect(ExerciseDemoRegistry.get(id).painterBuilder(.5), isA<LowerBodyPainter>());
    }
  });

  test('lower-body names and status translate to Hindi', () {
    AppLocaleService.currentLocale.value = 'hi';
    addTearDown(() => AppLocaleService.currentLocale.value = 'en');
    for (final id in lower) {
      final name = getExerciseDisplayName(id);
      expect(tr(name), isNot(name));
    }
    expect(tr('Experimental movement feedback'), isNot('Experimental movement feedback'));
  });

  testWidgets('all lower-body diagrams render at narrow and wide sizes', (tester) async {
    for (final id in lower) {
      for (final width in [220.0, 600.0]) {
        for (final progress in [0.0, .35, .55, .8, 1.0]) {
          await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
            width: width, height: 260, child: CustomPaint(
              painter: LowerBodyPainter(exercise: id, progress: progress, isDark: false),
            ),
          ))));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  test('render review contact sheet when requested', () async {
    final output = Platform.environment['HEMO_DEMO_PREVIEW'];
    if (output == null) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    for (var row = 0; row < lower.length; row++) {
      for (var col = 0; col < 3; col++) {
        canvas.save();
        canvas.translate(col * 360.0, row * 330.0);
        final text = TextPainter(text: TextSpan(text: '${getExerciseDisplayName(lower[row])}  ${col + 1}',
          style: const TextStyle(color: Colors.black, fontSize: 17)), textDirection: TextDirection.ltr)..layout();
        text.paint(canvas, const Offset(14, 8));
        canvas.translate(0, 25);
        LowerBodyPainter(exercise: lower[row], progress: [0.0, .55, .95][col], isDark: false)
            .paint(canvas, const Size(360, 300));
        canvas.restore();
      }
    }
    final image = await recorder.endRecording().toImage(1080, 1980);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(output).writeAsBytes(png!.buffer.asUint8List());
  });
}

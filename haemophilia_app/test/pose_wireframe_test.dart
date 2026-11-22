import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/screens/assessment/live_assessment_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'shared wireframe colors reflect form and invalid joints are hidden',
    () async {
      for (final entry in {
        'correct': Colors.greenAccent,
        'incorrect': Colors.redAccent,
        'adjusting': Colors.amberAccent,
        'waiting': Colors.blueGrey.shade300,
      }.entries) {
        final points = List.generate(
          33,
          (_) => const LiveLandmark(x: 0, y: 0, z: 0, visibility: 0),
        );
        points[11] = const LiveLandmark(x: .2, y: .3, z: 0, visibility: .99);
        points[13] = const LiveLandmark(x: .4, y: .5, z: 0, visibility: .99);
        points[12] = const LiveLandmark(x: .8, y: .3, z: 0, visibility: .1);
        points[14] = const LiveLandmark(
          x: double.nan,
          y: .5,
          z: 0,
          visibility: .99,
        );
        points[16] = const LiveLandmark(x: 1.2, y: .7, z: 0, visibility: .99);
        final landmarks = ValueNotifier(points);
        final form = ValueNotifier(entry.key);
        final recorder = ui.PictureRecorder();
        PosePainter(
          landmarksNotifier: landmarks,
          formNotifier: form,
          isFrontCamera: false,
        ).paint(Canvas(recorder), const Size(100, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 200);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (60 * 100 + 20) * 4;
        expect(data.getUint8(offset), (entry.value.r * 255).round());
        expect(data.getUint8(offset + 1), (entry.value.g * 255).round());
        expect(data.getUint8(offset + 2), (entry.value.b * 255).round());
        expect(data.getUint8((60 * 100 + 80) * 4 + 3), 0);
        expect(data.getUint8((140 * 100 + 99) * 4 + 3), 0);
        image.dispose();
        picture.dispose();
        landmarks.dispose();
        form.dispose();
      }
    },
  );
  for (final front in [false, true]) {
    test(
      'wireframe maps normalized joints to portrait viewport front=$front',
      () async {
        final points = List.generate(
          33,
          (_) => const LiveLandmark(x: 0, y: 0, z: 0, visibility: 0),
        );
        points[11] = const LiveLandmark(x: .2, y: .3, z: 0, visibility: .99);
        points[13] = const LiveLandmark(x: .4, y: .5, z: 0, visibility: .99);
        final landmarks = ValueNotifier(points);
        final form = ValueNotifier('correct');
        final painter = PosePainter(
          landmarksNotifier: landmarks,
          formNotifier: form,
          isFrontCamera: front,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(100, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 200);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int alpha(int x, int y) => data.getUint8((y * 100 + x) * 4 + 3);
        expect(alpha(front ? 80 : 20, 60), greaterThan(0));
        expect(alpha(front ? 20 : 80, 60), 0);
        image.dispose();
        picture.dispose();
        landmarks.dispose();
        form.dispose();
      },
    );
  }
}

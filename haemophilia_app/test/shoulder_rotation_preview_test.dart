import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/widgets/exercise_demo/shoulder_rotation_painter.dart';

void main() {
  testWidgets('Bar movement renders centre, side and centre without overflow', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RepaintBoundary(
      key: key,
      child: SizedBox(width: 780, height: 300, child: ColoredBox(
        color: const Color(0xFF0F172A),
        child: Row(children: [
          for (final progress in [0.0, 0.55, 0.99])
            Expanded(child: CustomPaint(
              painter: ShoulderRotationPainter(progress: progress),
              child: const SizedBox.expand(),
            )),
        ]),
      )),
    ))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../reports/shoulder_rotation_integration/tutorial_preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });
}

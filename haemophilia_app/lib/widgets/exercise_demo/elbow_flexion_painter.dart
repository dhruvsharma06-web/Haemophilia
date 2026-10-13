import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_localizations.dart';

/// Bilateral demonstration: upper arms stay beside the torso while both
/// forearms bend and return. The angle label is the elbow joint angle.
class ElbowFlexionPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  const ElbowFlexionPainter({required this.progress, this.isDark = true});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 270, size.height / 255);
    final center = Offset(size.width / 2, size.height / 2);
    Offset point(double x, double y) => center + Offset(x * scale, y * scale);
    final body = Paint()
      ..color = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)
      ..strokeWidth = 4 * scale
      ..strokeCap = StrokeCap.round;
    final arm = Paint()
      ..color = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0F766E)
      ..strokeWidth = 5 * scale
      ..strokeCap = StrokeCap.round;
    double angle = 165;
    if (progress > .2 && progress <= .5) {
      angle = 165 - 75 * Curves.easeInOutCubic.transform((progress - .2) / .3);
    } else if (progress > .5 && progress <= .6) {
      angle = 90;
    } else if (progress > .6 && progress <= .95) {
      angle = 90 + 75 * Curves.easeInOutCubic.transform((progress - .6) / .35);
    }
    canvas.drawCircle(point(0, -82), 12 * scale, body);
    canvas.drawLine(point(0, -69), point(0, 25), body);
    canvas.drawLine(point(-29, -55), point(29, -55), body);
    canvas.drawLine(point(-18, 25), point(18, 25), body);
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(point(side * 18, 25), point(side * 23, 65), body);
      canvas.drawLine(point(side * 23, 65), point(side * 26, 102), body);
      canvas.drawLine(point(side * 26, 102), point(side * 42, 102), body);
      final shoulder = point(side * 29, -55);
      final elbow = point(side * 32, -8);
      final bend = (180 - angle) * math.pi / 180;
      final wrist =
          elbow +
          Offset(
            side * 44 * math.sin(bend) * scale,
            44 * math.cos(bend) * scale,
          );
      final ghost = Paint()
        ..color = arm.color.withValues(alpha: .18)
        ..strokeWidth = 3 * scale
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(elbow, elbow + Offset(side * 44 * scale, 0), ghost);
      canvas.drawLine(shoulder, elbow, arm);
      canvas.drawLine(elbow, wrist, arm);
      for (final joint in [shoulder, elbow, wrist]) {
        canvas.drawCircle(
          joint,
          7 * scale,
          Paint()..color = arm.color.withValues(alpha: .18),
        );
        canvas.drawCircle(joint, 3.5 * scale, Paint()..color = arm.color);
      }
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${tr('Both elbows')}: ${angle.toStringAsFixed(0)}°',
        style: TextStyle(
          fontSize: 12 * scale,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : const Color(0xFF334155),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width);
    label.paint(canvas, Offset((size.width - label.width) / 2, 5));
  }

  @override
  bool shouldRepaint(covariant ElbowFlexionPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../utils/app_localizations.dart';

/// Bar-assisted shoulder rotation: centre -> one side -> centre is one rep.
class ShoulderRotationPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  const ShoulderRotationPainter({required this.progress, this.isDark = true});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 260, size.height / 300);
    final centre = Offset(size.width / 2, size.height * 0.38);
    Offset point(double x, double y) => centre + Offset(x * scale, y * scale);
    final bodyColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final body = Paint()
      ..color = bodyColor
      ..strokeWidth = 5 * scale
      ..strokeCap = StrokeCap.round;
    final arms = Paint()
      ..color = activeColor
      ..strokeWidth = 5 * scale
      ..strokeCap = StrokeCap.round;

    double excursion = 0;
    String phase = 'CENTRE';
    if (progress > 0.20 && progress <= 0.50) {
      excursion = Curves.easeInOutCubic.transform((progress - 0.20) / 0.30);
      phase = 'TO ONE SIDE';
    } else if (progress > 0.50 && progress <= 0.60) {
      excursion = 1;
      phase = 'ONE SIDE';
    } else if (progress > 0.60 && progress <= 0.95) {
      excursion = 1 - Curves.easeInOutCubic.transform((progress - 0.60) / 0.35);
      phase = 'RETURN TO CENTRE';
    }
    final shift = excursion * 24;
    final leftShoulder = point(-28, -35);
    final rightShoulder = point(28, -35);
    final leftElbow = point(-28, 7);
    final rightElbow = point(28, 7);
    final leftWrist = point(-22 + shift, 18);
    final rightWrist = point(22 + shift, 18);

    canvas.drawCircle(point(0, -63), 12 * scale, body);
    canvas.drawLine(point(0, -49), point(0, -35), body);
    canvas.drawLine(leftShoulder, rightShoulder, body);
    canvas.drawLine(point(0, -35), point(0, 50), body);
    canvas.drawLine(point(-18, 50), point(18, 50), body);
    for (final side in [-1, 1]) {
      canvas.drawLine(point(side * 18, 50), point(side * 18, 93), body);
      canvas.drawLine(point(side * 18, 93), point(side * 18, 134), body);
      canvas.drawLine(point(side * 18, 134), point(side * 28, 134), body);
    }

    // A faint bar marks the centre position throughout the excursion.
    canvas.drawLine(point(-52, 18), point(52, 18), Paint()
      ..color = bodyColor.withValues(alpha: 0.18)
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(leftShoulder, leftElbow, arms);
    canvas.drawLine(rightShoulder, rightElbow, arms);
    canvas.drawLine(leftElbow, leftWrist, arms);
    canvas.drawLine(rightElbow, rightWrist, arms);
    canvas.drawLine(point(-52 + shift, 18), point(52 + shift, 18), Paint()
      ..color = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round);
    for (final joint in [leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist]) {
      canvas.drawCircle(joint, 6 * scale, Paint()..color = activeColor.withValues(alpha: 0.22));
      canvas.drawCircle(joint, 2.7 * scale, Paint()..color = activeColor);
    }

    final arrow = Paint()
      ..color = activeColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.7 * scale
      ..strokeCap = StrokeCap.round;
    final returning = progress > 0.60 && progress <= 0.95;
    final tip = returning ? -8.0 : 28.0;
    final tail = returning ? 28.0 : -8.0;
    final wing = returning ? -3.0 : 23.0;
    canvas.drawLine(point(tail, -3), point(tip, -3), arrow);
    canvas.drawLine(point(tip, -3), point(wing, -7), arrow);
    canvas.drawLine(point(tip, -3), point(wing, 1), arrow);

    final caption = TextPainter(
      text: TextSpan(text: tr(phase), style: TextStyle(
        color: activeColor, fontSize: 10 * scale, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    caption.paint(canvas, point(0, 158) - Offset(caption.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant ShoulderRotationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isDark != isDark;
}

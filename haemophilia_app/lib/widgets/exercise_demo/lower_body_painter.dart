import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/exercise_utils.dart';

/// Side-view movement diagrams. The range is illustrative, not a prescription.
class LowerBodyPainter extends CustomPainter {
  final String exercise;
  final double progress;
  final bool isDark;

  LowerBodyPainter({
    required this.exercise,
    required this.progress,
    this.isDark = true,
  });

  double get movement {
    final p = progress.clamp(0.0, 1.0);
    if (p < .2 || p >= .95) return 0;
    if (p <= .5) return (1 - math.cos(math.pi * (p - .2) / .3)) / 2;
    if (p <= .6) return 1;
    return (1 + math.cos(math.pi * (p - .6) / .35)) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 360, size.height / 300);
    canvas.save();
    canvas.translate(
      (size.width - 360 * scale) / 2,
      (size.height - 300 * scale) / 2,
    );
    canvas.scale(scale);
    final color = isDark ? const Color(0xFF63D7D0) : const Color(0xFF007681);
    final body = Paint()
      ..color = color
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final quiet = Paint()
      ..color = color.withValues(alpha: .25)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final support = Paint()
      ..color = (isDark ? Colors.white : Colors.blueGrey).withValues(alpha: .3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final t = movement;
    Offset hip, shoulder, knee, ankle;
    Offset? restingKnee, restingAnkle;
    bool lying = false;
    if (exercise == kSquat || exercise == kMiniSquat) {
      final peak = exercise == kMiniSquat ? 130.0 : 120.0;
      final kneeDegrees = 175 + (peak - 175) * t;
      final distanceToAnkle = 144 * math.sin(kneeDegrees * math.pi / 360);
      final hipOffsetX = 25 + (exercise == kMiniSquat ? 20 : 30) * t;
      ankle = const Offset(200, 270);
      hip =
          ankle -
          Offset(
            hipOffsetX,
            math.sqrt(
              distanceToAnkle * distanceToAnkle - hipOffsetX * hipOffsetX,
            ),
          );
      // Two segments of equal length joined at the knee.
      final delta = ankle - hip;
      final distance = delta.distance;
      final midpoint = (hip + ankle) / 2;
      final height = math.sqrt(
        math.max(0.0, 72 * 72 - distance * distance / 4),
      );
      knee = midpoint + Offset(delta.dy, -delta.dx) / distance * height;
      shoulder = hip + Offset(10 + 25 * t, -75);
      canvas.drawLine(const Offset(65, 282), const Offset(305, 282), support);
    } else if (exercise == kSeatedKneeExtension) {
      hip = const Offset(130, 165);
      shoulder = const Offset(125, 90);
      knee = const Offset(205, 165);
      final a = math.pi / 2 * (1 - t);
      ankle = knee + Offset(math.cos(a), math.sin(a)) * 75;
      canvas.drawLine(const Offset(95, 175), const Offset(165, 175), support);
      canvas.drawLine(const Offset(105, 175), const Offset(105, 265), support);
      canvas.drawLine(const Offset(155, 175), const Offset(155, 265), support);
      restingKnee = knee + const Offset(-6, 8);
      restingAnkle = const Offset(202, 245);
    } else {
      lying = true;
      hip = const Offset(155, 225);
      shoulder = const Offset(85, 225);
      restingKnee = const Offset(230, 225);
      restingAnkle = const Offset(305, 225);
      canvas.drawLine(const Offset(35, 241), const Offset(330, 241), support);
      if (exercise == kStraightLegRaise) {
        restingKnee = hip + const Offset(40, -55);
        restingAnkle = hip + const Offset(80, 0);
        final a = -(40 * math.pi / 180) * t;
        knee = hip + Offset(math.cos(a), math.sin(a)) * 75;
        ankle = hip + Offset(math.cos(a), math.sin(a)) * 150;
      } else if (exercise == kTerminalKneeExtension) {
        knee = const Offset(222, 190);
        final thighDirection = math.atan2(knee.dy - hip.dy, knee.dx - hip.dx);
        final a = thighDirection + (50 * math.pi / 180) * (1 - t);
        ankle = knee + Offset(math.cos(a), math.sin(a)) * 72;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(200, 201, 44, 35),
            const Radius.circular(15),
          ),
          support,
        );
      } else {
        // Heel remains on the mat while the knee rises.
        ankle = Offset(305 - (150 - 150 / math.sqrt(2)) * t, 225);
        final d = (ankle - hip).distance;
        knee =
            (hip + ankle) / 2 +
            Offset(0, -math.sqrt(math.max(0, 75 * 75 - d * d / 4)));
      }
    }
    if (restingKnee != null && restingAnkle != null) {
      canvas.drawLine(hip, restingKnee, quiet);
      canvas.drawLine(restingKnee, restingAnkle, quiet);
    }
    canvas.drawLine(shoulder, hip, body);
    canvas.drawLine(hip, knee, body);
    canvas.drawLine(knee, ankle, body);
    canvas.drawLine(ankle, ankle + const Offset(16, 0), body);
    final head =
        shoulder + (lying ? const Offset(-27, -3) : const Offset(-2, -28));
    canvas.drawCircle(head, 13, body);
    if (lying) {
      canvas.drawLine(
        shoulder + const Offset(8, 9),
        hip + const Offset(-8, 9),
        quiet,
      );
    } else {
      final elbow = shoulder + const Offset(28, 30);
      canvas.drawLine(shoulder, elbow, body);
      canvas.drawLine(elbow, elbow + const Offset(32, -5), body);
    }
    for (final joint in [hip, knee, ankle]) {
      canvas.drawCircle(
        joint,
        6,
        Paint()..color = isDark ? Colors.white : Colors.white,
      );
      canvas.drawCircle(joint, 3, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LowerBodyPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      exercise != oldDelegate.exercise ||
      isDark != oldDelegate.isDark;
}

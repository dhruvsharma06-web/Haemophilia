import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter rendering a clinical/recovery-style skeletal figure performing
/// Elbow Flexion & Extension in sagittal (side) view.
class ElbowFlexionPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final bool isDark;

  const ElbowFlexionPainter({
    required this.progress,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bodyColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeArmColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final jointGlowColor = isDark ? const Color(0xFF06B6D4) : const Color(0xFF0EA5E9);
    final arcColor = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
        : const Color(0xFF0284C7).withValues(alpha: 0.30);
    final arrowColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    final scale = math.min(size.width / 260, size.height / 260);
    final originX = size.width * 0.45;
    final originY = size.height * 0.48;

    final headCenter = Offset(originX, originY - 60 * scale);
    final neck = Offset(originX, originY - 44 * scale);
    final shoulder = Offset(originX, originY - 34 * scale);
    final hip = Offset(originX - 4 * scale, originY + 28 * scale);
    final knee = Offset(originX - 2 * scale, originY + 70 * scale);
    final ankle = Offset(originX - 4 * scale, originY + 110 * scale);
    final foot = Offset(originX + 14 * scale, originY + 114 * scale);

    // Upper arm remains fixed vertically along torso
    final upperArmLen = 38.0 * scale;
    final forearmLen = 38.0 * scale;
    final elbow = Offset(shoulder.dx, shoulder.dy + upperArmLen);

    // Elbow angle:
    // 0.00 - 0.20: Extended down (theta ~ 10 deg)
    // 0.20 - 0.50: Flexing up (theta 10 deg -> 135 deg)
    // 0.50 - 0.60: Peak flexion hold (135 deg)
    // 0.60 - 0.95: Extending down (135 deg -> 10 deg)
    // 0.95 - 1.00: Pause (10 deg)
    double thetaDeg = 10.0;
    bool isFlexing = false;
    bool isExtending = false;

    if (progress <= 0.20) {
      thetaDeg = 10.0;
    } else if (progress <= 0.50) {
      isFlexing = true;
      final t = (progress - 0.20) / 0.30;
      final curved = Curves.easeInOutCubic.transform(t);
      thetaDeg = 10.0 + 125.0 * curved;
    } else if (progress <= 0.60) {
      thetaDeg = 135.0;
    } else if (progress <= 0.95) {
      isExtending = true;
      final t = (progress - 0.60) / 0.35;
      final curved = Curves.easeInOutCubic.transform(t);
      thetaDeg = 135.0 - 125.0 * curved;
    } else {
      thetaDeg = 10.0;
    }

    final thetaRad = thetaDeg * math.pi / 180.0;

    // Wrist position: pivots around elbow forward and up
    final wrist = Offset(
      elbow.dx + forearmLen * math.sin(thetaRad),
      elbow.dy - forearmLen * math.cos(thetaRad),
    );

    // Floor
    final floorY = ankle.dy + 4 * scale;
    final floorPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(originX - 50 * scale, floorY),
      Offset(originX + 80 * scale, floorY),
      floorPaint,
    );

    // Motion arc
    final rect = Rect.fromCircle(center: elbow, radius: forearmLen);
    final arcPaint = Paint()
      ..color = arcColor
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;
    final startRad = (90.0 - 10.0) * math.pi / 180.0;
    final sweepRad = -(135.0 - 10.0) * math.pi / 180.0;
    canvas.drawArc(rect, startRad, sweepRad, false, arcPaint);

    // Direction arrows
    if (isFlexing || isExtending) {
      final arrowPaint = Paint()
        ..color = isFlexing ? arrowColor : const Color(0xFFF59E0B)
        ..strokeWidth = 2.5 * scale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final leadAngleDeg = (thetaDeg + (isFlexing ? 15.0 : -15.0)).clamp(15.0, 130.0);
      final leadRad = leadAngleDeg * math.pi / 180.0;
      final arrowPos = Offset(
        elbow.dx + forearmLen * math.sin(leadRad),
        elbow.dy - forearmLen * math.cos(leadRad),
      );
      canvas.drawCircle(arrowPos, 3 * scale, arrowPaint);
    }

    // Skeletal body
    final bodyPaint = Paint()
      ..color = bodyColor
      ..strokeWidth = 4.5 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final spinePath = Path();
    spinePath.moveTo(neck.dx, neck.dy);
    spinePath.quadraticBezierTo(
      originX - 2 * scale,
      originY - 6 * scale,
      hip.dx,
      hip.dy,
    );
    canvas.drawPath(spinePath, bodyPaint);
    canvas.drawLine(hip, knee, bodyPaint);
    canvas.drawLine(knee, ankle, bodyPaint);
    canvas.drawLine(ankle, foot, bodyPaint);

    // Head
    canvas.drawCircle(
      headCenter,
      11 * scale,
      Paint()
        ..color = bodyColor
        ..style = PaintingStyle.fill,
    );

    // Arm
    final armPaint = Paint()
      ..color = activeArmColor
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(shoulder, elbow, armPaint);
    canvas.drawLine(elbow, wrist, armPaint);

    // Joints
    final jointHalo = Paint()
      ..color = jointGlowColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final jointCenter = Paint()
      ..color = jointGlowColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(shoulder, 7 * scale, jointHalo);
    canvas.drawCircle(shoulder, 4 * scale, jointCenter);

    canvas.drawCircle(elbow, 8 * scale, jointHalo);
    canvas.drawCircle(elbow, 4.5 * scale, jointCenter);

    canvas.drawCircle(wrist, 6 * scale, jointHalo);
    canvas.drawCircle(wrist, 3.2 * scale, jointCenter);
  }

  @override
  bool shouldRepaint(covariant ElbowFlexionPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

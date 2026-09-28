import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter rendering a clinical/recovery-style skeletal figure performing
/// Assisted Elbow Flexion in sagittal (side) view, clearly depicting the contralateral
/// hand supporting and guiding the recovering forearm through flexion and extension.
class AssistedElbowFlexionPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final bool isDark;

  const AssistedElbowFlexionPainter({
    required this.progress,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Theme colors
    final bodyColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeArmColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final assistArmColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final jointGlowColor = isDark ? const Color(0xFF06B6D4) : const Color(0xFF0EA5E9);
    final arcColor = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
        : const Color(0xFF0284C7).withValues(alpha: 0.30);
    final arrowColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    // 2. Geometry scaling based on canvas size
    final scale = math.min(size.width / 260, size.height / 260);
    final originX = size.width * 0.44;
    final originY = size.height * 0.48;

    // Skeletal body landmarks
    final headCenter = Offset(originX, originY - 60 * scale);
    final neck = Offset(originX, originY - 44 * scale);
    final shoulder = Offset(originX, originY - 34 * scale);
    final contralateralShoulder = Offset(originX - 12 * scale, originY - 35 * scale);
    final hip = Offset(originX - 4 * scale, originY + 28 * scale);
    final knee = Offset(originX - 2 * scale, originY + 70 * scale);
    final ankle = Offset(originX - 4 * scale, originY + 110 * scale);
    final foot = Offset(originX + 14 * scale, originY + 114 * scale);

    // Active limb dimensions
    final upperArmLen = 38.0 * scale;
    final forearmLen = 38.0 * scale;
    final elbow = Offset(shoulder.dx, shoulder.dy + upperArmLen);

    // 3. Movement phases:
    // 0.00 - 0.20: Extended starting posture (~10 deg)
    // 0.20 - 0.50: Assisted upward bending (10 deg -> 135 deg)
    // 0.50 - 0.60: Peak flexion hold with support (135 deg)
    // 0.60 - 0.95: Controlled assisted lowering (135 deg -> 10 deg)
    // 0.95 - 1.00: Return to start pause (10 deg)
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

    // Active wrist position: pivots around active elbow forward and upward
    final wrist = Offset(
      elbow.dx + forearmLen * math.sin(thetaRad),
      elbow.dy - forearmLen * math.cos(thetaRad),
    );

    // Contralateral assisting hand supports under the active wrist/distal forearm
    final supportContact = Offset(
      wrist.dx - 4 * scale * math.cos(thetaRad),
      wrist.dy - 4 * scale * math.sin(thetaRad),
    );

    // Contralateral elbow position (reaching across torso to meet supportContact)
    final assistElbow = Offset(
      contralateralShoulder.dx + 16 * scale,
      contralateralShoulder.dy + 34 * scale,
    );

    // 4. Floor guide
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

    // 5. Motion arc
    final rect = Rect.fromCircle(center: elbow, radius: forearmLen);
    final arcPaint = Paint()
      ..color = arcColor
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;
    final startRad = (90.0 - 10.0) * math.pi / 180.0;
    final sweepRad = -(135.0 - 10.0) * math.pi / 180.0;
    canvas.drawArc(rect, startRad, sweepRad, false, arcPaint);

    // 6. Direction arrows
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

    // 7. Contralateral Assisting Arm (Drawn behind body/under active arm)
    final assistPaint = Paint()
      ..color = assistArmColor
      ..strokeWidth = 4.0 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Contralateral shoulder -> assist elbow -> support contact
    canvas.drawLine(contralateralShoulder, assistElbow, assistPaint);
    canvas.drawLine(assistElbow, supportContact, assistPaint);

    // Contralateral supporting hand grip / cradle
    final assistGripPaint = Paint()
      ..color = assistArmColor
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: supportContact, radius: 6 * scale),
      0,
      math.pi * 1.5,
      false,
      assistGripPaint,
    );

    // 8. Skeletal Body (Torso & Legs)
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

    // 9. Active Exercising Arm
    final armPaint = Paint()
      ..color = activeArmColor
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Upper arm fixed along torso
    canvas.drawLine(shoulder, elbow, armPaint);
    // Forearm actively flexing
    canvas.drawLine(elbow, wrist, armPaint);

    // 10. Joint halos and center dots
    final jointHalo = Paint()
      ..color = jointGlowColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final jointCenter = Paint()
      ..color = isDark ? Colors.white : Colors.black87
      ..style = PaintingStyle.fill;

    // Active shoulder & elbow
    canvas.drawCircle(shoulder, 6 * scale, jointHalo);
    canvas.drawCircle(shoulder, 3 * scale, jointCenter);

    canvas.drawCircle(elbow, 7 * scale, jointHalo);
    canvas.drawCircle(elbow, 3.5 * scale, jointCenter);

    // Active wrist
    canvas.drawCircle(wrist, 5 * scale, jointHalo);
    canvas.drawCircle(wrist, 2.5 * scale, jointCenter);

    // Assisting elbow & support hand
    final assistHalo = Paint()
      ..color = assistArmColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(assistElbow, 5 * scale, assistHalo);
    canvas.drawCircle(assistElbow, 2.5 * scale, jointCenter);

    canvas.drawCircle(supportContact, 6 * scale, assistHalo);
    canvas.drawCircle(supportContact, 3 * scale, Paint()..color = assistArmColor);

    // 11. Support cue badge
    _drawSupportBadge(
      canvas,
      Offset(originX + 48 * scale, originY - 48 * scale),
      'Assisted',
      scale,
      isDark,
      assistArmColor,
    );
  }

  void _drawSupportBadge(
    Canvas canvas,
    Offset position,
    String text,
    double scale,
    bool isDark,
    Color badgeColor,
  ) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: badgeColor,
        fontSize: 10 * scale,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final badgeRect = Rect.fromCenter(
      center: position,
      width: textPainter.width + 12 * scale,
      height: textPainter.height + 6 * scale,
    );

    final badgePaint = Paint()
      ..color = (isDark ? const Color(0xFF0F172A) : Colors.white).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = badgeColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;

    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(6 * scale)),
      badgePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, Radius.circular(6 * scale)),
      borderPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant AssistedElbowFlexionPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter rendering a clinical/recovery-style skeletal figure performing
/// Assisted Shoulder Flexion with Bar in sagittal (side) view with animated trajectory and directional guides.
class ShoulderFlexionPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final bool isDark;

  const ShoulderFlexionPainter({
    required this.progress,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Theme colors
    final bodyColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeArmColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final jointGlowColor = isDark ? const Color(0xFF06B6D4) : const Color(0xFF0EA5E9);
    final barColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final arcColor = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
        : const Color(0xFF0284C7).withValues(alpha: 0.30);
    final arrowColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    // 2. Geometry scaling based on canvas size
    final scale = math.min(size.width / 260, size.height / 260);
    final originX = size.width * 0.40;
    final originY = size.height * 0.48;

    // Head and Torso coordinates
    final headCenter = Offset(originX + 2 * scale, originY - 60 * scale);
    final neck = Offset(originX, originY - 44 * scale);
    final shoulder = Offset(originX, originY - 34 * scale);
    final hip = Offset(originX - 6 * scale, originY + 28 * scale);
    final knee = Offset(originX - 4 * scale, originY + 70 * scale);
    final ankle = Offset(originX - 6 * scale, originY + 110 * scale);
    final foot = Offset(originX + 12 * scale, originY + 114 * scale);

    // 3. Calculate arm angle theta (in degrees from vertical down)
    // 0.00 - 0.15: Start position hold (15 deg)
    // 0.15 - 0.50: Upward lift (15 deg -> 165 deg)
    // 0.50 - 0.60: Overhead peak hold (165 deg)
    // 0.60 - 0.95: Downward lowering (165 deg -> 15 deg)
    // 0.95 - 1.00: Return to start pause (15 deg)
    double thetaDeg = 15.0;
    bool isLifting = false;
    bool isLowering = false;

    if (progress <= 0.15) {
      thetaDeg = 15.0;
    } else if (progress <= 0.50) {
      isLifting = true;
      final t = (progress - 0.15) / 0.35;
      final curved = Curves.easeInOutCubic.transform(t);
      thetaDeg = 15.0 + 150.0 * curved;
    } else if (progress <= 0.60) {
      thetaDeg = 165.0;
    } else if (progress <= 0.95) {
      isLowering = true;
      final t = (progress - 0.60) / 0.35;
      final curved = Curves.easeInOutCubic.transform(t);
      thetaDeg = 165.0 - 150.0 * curved;
    } else {
      thetaDeg = 15.0;
    }

    final thetaRad = thetaDeg * math.pi / 180.0;

    // Limb lengths
    final upperArmLen = 38.0 * scale;
    final forearmLen = 40.0 * scale;
    final totalArmRadius = upperArmLen + forearmLen;

    // Arm joint positions (moving forward in sagittal plane, so +X is forward)
    // When theta = 0, arm points down (cos(0)=1, sin(0)=0)
    // When theta = 90, arm points forward (sin(90)=1, cos(90)=0)
    // When theta = 165, arm points upward-forward (sin(165)>0, cos(165)<0)
    final elbow = Offset(
      shoulder.dx + upperArmLen * math.sin(thetaRad),
      shoulder.dy + upperArmLen * math.cos(thetaRad),
    );

    final wrist = Offset(
      elbow.dx + forearmLen * math.sin(thetaRad),
      elbow.dy + forearmLen * math.cos(thetaRad),
    );

    // 4. Draw floor ground guide
    final floorY = ankle.dy + 4 * scale;
    final floorPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(originX - 60 * scale, floorY),
      Offset(originX + 110 * scale, floorY),
      floorPaint,
    );

    // 5. Draw Motion Path Arc (from 15 deg to 165 deg)
    _drawTrajectoryArc(
      canvas,
      shoulder,
      totalArmRadius,
      15.0,
      165.0,
      arcColor,
      scale,
    );

    // 6. Draw Directional Arrows along the arc
    if (isLifting) {
      _drawDirectionArrows(
        canvas,
        shoulder,
        totalArmRadius,
        thetaDeg,
        isUpward: true,
        color: arrowColor,
        scale: scale,
      );
    } else if (isLowering) {
      _drawDirectionArrows(
        canvas,
        shoulder,
        totalArmRadius,
        thetaDeg,
        isUpward: false,
        color: const Color(0xFFF59E0B),
        scale: scale,
      );
    }

    // 7. Draw Skeletal Figure (Torso & Legs)
    final bodyPaint = Paint()
      ..color = bodyColor
      ..strokeWidth = 4.5 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Spine & Neck
    final spinePath = Path();
    spinePath.moveTo(neck.dx, neck.dy);
    spinePath.quadraticBezierTo(
      originX - 2 * scale,
      originY - 6 * scale,
      hip.dx,
      hip.dy,
    );
    canvas.drawPath(spinePath, bodyPaint);

    // Legs
    canvas.drawLine(hip, knee, bodyPaint);
    canvas.drawLine(knee, ankle, bodyPaint);
    canvas.drawLine(ankle, foot, bodyPaint);

    // Head
    final headPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(headCenter, 11 * scale, headPaint);

    // Subtle facial profile indication
    final eyePaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(headCenter.dx + 5 * scale, headCenter.dy - 1 * scale),
      1.8 * scale,
      eyePaint,
    );

    // 8. Draw Active Arm Limbs
    final armPaint = Paint()
      ..color = activeArmColor
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(shoulder, elbow, armPaint);
    canvas.drawLine(elbow, wrist, armPaint);

    // 9. Draw Joints (Glowing circles)
    final jointHaloPaint = Paint()
      ..color = jointGlowColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final jointCenterPaint = Paint()
      ..color = jointGlowColor
      ..style = PaintingStyle.fill;

    // Shoulder joint
    canvas.drawCircle(shoulder, 8 * scale, jointHaloPaint);
    canvas.drawCircle(shoulder, 4.5 * scale, jointCenterPaint);

    // Elbow joint
    canvas.drawCircle(elbow, 7 * scale, jointHaloPaint);
    canvas.drawCircle(elbow, 3.8 * scale, jointCenterPaint);

    // Wrist joint
    canvas.drawCircle(wrist, 6 * scale, jointHaloPaint);
    canvas.drawCircle(wrist, 3.2 * scale, jointCenterPaint);

    // 10. Draw the Bar (Held horizontally in hands)
    _drawBar(canvas, wrist, thetaRad, barColor, scale);

    // 11. Draw Angle Tag
    _drawAngleBadge(canvas, shoulder, thetaDeg, scale);
  }

  void _drawTrajectoryArc(
    Canvas canvas,
    Offset center,
    double radius,
    double startAngleDeg,
    double endAngleDeg,
    Color color,
    double scale,
  ) {
    final arcPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;

    // Path in screen coordinates:
    // angle 0 is vertical down (+Y direction) -> pi/2 in standard trig
    // Sweep is from 15 deg to 165 deg
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startRad = (90.0 - startAngleDeg) * math.pi / 180.0;
    final sweepRad = -(endAngleDeg - startAngleDeg) * math.pi / 180.0;

    canvas.drawArc(rect, startRad, sweepRad, false, arcPaint);
  }

  void _drawDirectionArrows(
    Canvas canvas,
    Offset center,
    double radius,
    double currentAngleDeg, {
    required bool isUpward,
    required Color color,
    required double scale,
  }) {
    final arrowPaint = Paint()
      ..color = color
      ..strokeWidth = 2.5 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Place an arrow just ahead of the current position along the arc
    final leadAngleDeg = currentAngleDeg + (isUpward ? 18.0 : -18.0);
    final clampedDeg = leadAngleDeg.clamp(18.0, 162.0);
    final leadRad = clampedDeg * math.pi / 180.0;

    final arrowPos = Offset(
      center.dx + radius * math.sin(leadRad),
      center.dy + radius * math.cos(leadRad),
    );

    // Tangent angle along arc
    // Normal is (sin, cos), Tangent is (cos, -sin) for upward
    final tangentX = math.cos(leadRad) * (isUpward ? 1 : -1);
    final tangentY = -math.sin(leadRad) * (isUpward ? 1 : -1);

    final arrowLen = 10.0 * scale;
    final tip = arrowPos;
    final base = Offset(tip.dx - tangentX * arrowLen, tip.dy - tangentY * arrowLen);

    // Draw arrow stem
    canvas.drawLine(base, tip, arrowPaint);

    // Draw arrow wings
    final wingLen = 6.0 * scale;
    final normalX = -tangentY;
    final normalY = tangentX;

    final wing1 = Offset(
      tip.dx - tangentX * wingLen + normalX * (wingLen * 0.7),
      tip.dy - tangentY * wingLen + normalY * (wingLen * 0.7),
    );
    final wing2 = Offset(
      tip.dx - tangentX * wingLen - normalX * (wingLen * 0.7),
      tip.dy - tangentY * wingLen - normalY * (wingLen * 0.7),
    );

    canvas.drawLine(tip, wing1, arrowPaint);
    canvas.drawLine(tip, wing2, arrowPaint);
  }

  void _drawBar(
    Canvas canvas,
    Offset wrist,
    double thetaRad,
    Color color,
    double scale,
  ) {
    // Render the rehabilitation bar as a solid rounded bar held in hands
    final barLength = 28.0 * scale;
    final barThickness = 5.0 * scale;

    // Normal to the arm gives horizontal/depth orientation of the bar
    final normalX = -math.cos(thetaRad);
    final normalY = math.sin(thetaRad);

    final p1 = Offset(
      wrist.dx + normalX * (barLength / 2),
      wrist.dy + normalY * (barLength / 2),
    );
    final p2 = Offset(
      wrist.dx - normalX * (barLength / 2),
      wrist.dy - normalY * (barLength / 2),
    );

    final barPaint = Paint()
      ..color = color
      ..strokeWidth = barThickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(p1, p2, barPaint);

    // End caps
    final capPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(p1, 2.5 * scale, capPaint);
    canvas.drawCircle(p2, 2.5 * scale, capPaint);
  }

  void _drawAngleBadge(
    Canvas canvas,
    Offset shoulder,
    double thetaDeg,
    double scale,
  ) {
    final textSpan = TextSpan(
      text: '${thetaDeg.round()}°',
      style: TextStyle(
        color: isDark ? Colors.white70 : Colors.black87,
        fontSize: 11 * scale,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final badgeOffset = Offset(
      shoulder.dx - 45 * scale,
      shoulder.dy - 8 * scale,
    );

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        badgeOffset.dx - 4 * scale,
        badgeOffset.dy - 2 * scale,
        textPainter.width + 8 * scale,
        textPainter.height + 4 * scale,
      ),
      Radius.circular(4 * scale),
    );

    final bgPaint = Paint()
      ..color = (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bgRect, bgPaint);

    textPainter.paint(canvas, badgeOffset);
  }

  @override
  bool shouldRepaint(covariant ShoulderFlexionPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter rendering a clinical/recovery-style skeletal figure performing
/// Bilateral Shoulder Internal/External Rotation in frontal (coronal) view
/// with animated rotational trajectory arcs and form guidance cues.
class ShoulderRotationPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final bool isDark;

  const ShoulderRotationPainter({
    required this.progress,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Theme colors
    final bodyColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final activeArmColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final jointGlowColor = isDark ? const Color(0xFF06B6D4) : const Color(0xFF0EA5E9);
    final arcColor = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
        : const Color(0xFF0284C7).withValues(alpha: 0.30);
    final arrowColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final guideColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    // 2. Geometry scaling based on canvas size
    final scale = math.min(size.width / 260, size.height / 260);
    final originX = size.width * 0.50;
    final originY = size.height * 0.48;

    // Head and Torso coordinates (coronal / front view)
    final headCenter = Offset(originX, originY - 60 * scale);
    final neck = Offset(originX, originY - 44 * scale);
    final leftShoulder = Offset(originX - 32 * scale, originY - 34 * scale);
    final rightShoulder = Offset(originX + 32 * scale, originY - 34 * scale);
    final midChest = Offset(originX, originY - 14 * scale);
    final midPelvis = Offset(originX, originY + 28 * scale);
    final leftHip = Offset(originX - 18 * scale, originY + 28 * scale);
    final rightHip = Offset(originX + 18 * scale, originY + 28 * scale);
    final leftKnee = Offset(originX - 18 * scale, originY + 70 * scale);
    final rightKnee = Offset(originX + 18 * scale, originY + 70 * scale);
    final leftAnkle = Offset(originX - 18 * scale, originY + 110 * scale);
    final rightAnkle = Offset(originX + 18 * scale, originY + 110 * scale);
    final leftFoot = Offset(originX - 26 * scale, originY + 114 * scale);
    final rightFoot = Offset(originX + 26 * scale, originY + 114 * scale);

    // Elbows: upper arm hangs vertically against torso (90-degree flexion)
    final upperArmLength = 36.0 * scale;
    final leftElbow = Offset(leftShoulder.dx, leftShoulder.dy + upperArmLength);
    final rightElbow = Offset(rightShoulder.dx, rightShoulder.dy + upperArmLength);

    // 3. Rotation angle calculation:
    // 0.00 - 0.20: Start position (neutral forward, rotation = 0 deg)
    // 0.20 - 0.50: External rotation outward (0 deg -> 42 deg)
    // 0.50 - 0.60: Peak outward rotation hold (42 deg)
    // 0.60 - 0.95: Internal rotation return to neutral (42 deg -> 0 deg)
    // 0.95 - 1.00: Return to start pause (0 deg)
    double rotationDeg = 0.0;
    bool isRotatingOut = false;
    bool isRotatingIn = false;

    if (progress <= 0.20) {
      rotationDeg = 0.0;
    } else if (progress <= 0.50) {
      isRotatingOut = true;
      final t = (progress - 0.20) / 0.30;
      final curved = Curves.easeInOutCubic.transform(t);
      rotationDeg = 42.0 * curved;
    } else if (progress <= 0.60) {
      rotationDeg = 42.0;
    } else if (progress <= 0.95) {
      isRotatingIn = true;
      final t = (progress - 0.60) / 0.35;
      final curved = Curves.easeInOutCubic.transform(t);
      rotationDeg = 42.0 * (1.0 - curved);
    } else {
      rotationDeg = 0.0;
    }

    final forearmRadius = 34.0 * scale;

    // Forearm positions in frontal projection:
    // At 0 deg rotation (neutral): forearms point forward-slightly-inward
    // dx offset from elbow = 10 * scale toward center, dy = -16 * scale (depth foreshortened)
    // At 42 deg external rotation: forearms swing laterally outward
    // Angle of forearm from horizontal-outward baseline:
    // Start angle is angled inward towards the navel: ~110 deg from outward baseline
    // Outward peak swings toward ~25 deg from outward baseline
    final leftArmAngle = (110.0 - (rotationDeg / 42.0) * 85.0) * math.pi / 180.0;
    final leftWrist = Offset(
      leftElbow.dx - forearmRadius * math.cos(leftArmAngle),
      leftElbow.dy - forearmRadius * math.sin(leftArmAngle) * 0.45,
    );

    final rightArmAngle = (110.0 - (rotationDeg / 42.0) * 85.0) * math.pi / 180.0;
    final rightWrist = Offset(
      rightElbow.dx + forearmRadius * math.cos(rightArmAngle),
      rightElbow.dy - forearmRadius * math.sin(rightArmAngle) * 0.45,
    );

    // 4. Floor line
    final floorY = leftAnkle.dy + 4 * scale;
    final floorPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07)
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(originX - 90 * scale, floorY),
      Offset(originX + 90 * scale, floorY),
      floorPaint,
    );

    // 5. Trunk midline alignment guide
    final midlinePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09)
      ..strokeWidth = 1.2 * scale
      ..style = PaintingStyle.stroke;
    _drawDashedLine(
      canvas,
      Offset(originX, originY - 45 * scale),
      Offset(originX, originY + 30 * scale),
      midlinePaint,
    );

    // 6. Draw Rotational Arcs around elbows
    _drawRotationArc(
      canvas,
      leftElbow,
      forearmRadius,
      isLeft: true,
      currentAngleDeg: rotationDeg,
      maxAngleDeg: 42.0,
      arcColor: arcColor,
      scale: scale,
    );

    _drawRotationArc(
      canvas,
      rightElbow,
      forearmRadius,
      isLeft: false,
      currentAngleDeg: rotationDeg,
      maxAngleDeg: 42.0,
      arcColor: arcColor,
      scale: scale,
    );

    // 7. Draw Directional Rotation Indicators
    if (isRotatingOut || isRotatingIn) {
      final activeIndicatorColor = isRotatingOut ? arrowColor : const Color(0xFFF59E0B);
      _drawRotationDirectionDot(
        canvas,
        leftElbow,
        forearmRadius,
        isLeft: true,
        progressT: rotationDeg / 42.0,
        isOutward: isRotatingOut,
        color: activeIndicatorColor,
        scale: scale,
      );

      _drawRotationDirectionDot(
        canvas,
        rightElbow,
        forearmRadius,
        isLeft: false,
        progressT: rotationDeg / 42.0,
        isOutward: isRotatingOut,
        color: activeIndicatorColor,
        scale: scale,
      );
    }

    // 8. Draw Skeletal Torso & Legs
    final bodyPaint = Paint()
      ..color = bodyColor
      ..strokeWidth = 4.5 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Clavicle
    canvas.drawLine(leftShoulder, rightShoulder, bodyPaint);

    // Spine
    canvas.drawLine(neck, midChest, bodyPaint);
    canvas.drawLine(midChest, midPelvis, bodyPaint);

    // Pelvis
    canvas.drawLine(leftHip, rightHip, bodyPaint);

    // Legs
    canvas.drawLine(leftHip, leftKnee, bodyPaint);
    canvas.drawLine(leftKnee, leftAnkle, bodyPaint);
    canvas.drawLine(leftAnkle, leftFoot, bodyPaint);

    canvas.drawLine(rightHip, rightKnee, bodyPaint);
    canvas.drawLine(rightKnee, rightAnkle, bodyPaint);
    canvas.drawLine(rightAnkle, rightFoot, bodyPaint);

    // Head
    canvas.drawCircle(
      headCenter,
      11 * scale,
      Paint()
        ..color = bodyColor
        ..style = PaintingStyle.fill,
    );

    // 9. Elbow tuck guidance indicators (Keep elbows close to ribs)
    final tuckGuidePaint = Paint()
      ..color = guideColor.withValues(alpha: 0.40)
      ..strokeWidth = 1.5 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(originX - 16 * scale, leftElbow.dy),
      Offset(leftElbow.dx, leftElbow.dy),
      tuckGuidePaint,
    );
    canvas.drawLine(
      Offset(originX + 16 * scale, rightElbow.dy),
      Offset(rightElbow.dx, rightElbow.dy),
      tuckGuidePaint,
    );

    // 10. Upper arms (pinned to sides)
    final armPaint = Paint()
      ..color = activeArmColor
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(leftShoulder, leftElbow, armPaint);
    canvas.drawLine(rightShoulder, rightElbow, armPaint);

    // 11. Forearms (actively rotating outward/inward)
    canvas.drawLine(leftElbow, leftWrist, armPaint);
    canvas.drawLine(rightElbow, rightWrist, armPaint);

    // 12. Joints (Glow halos & white center pips)
    final jointHalo = Paint()
      ..color = jointGlowColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final jointCenter = Paint()
      ..color = isDark ? Colors.white : Colors.black87
      ..style = PaintingStyle.fill;

    // Shoulders
    canvas.drawCircle(leftShoulder, 6.0 * scale, jointHalo);
    canvas.drawCircle(leftShoulder, 3.0 * scale, jointCenter);
    canvas.drawCircle(rightShoulder, 6.0 * scale, jointHalo);
    canvas.drawCircle(rightShoulder, 3.0 * scale, jointCenter);

    // Elbows (Rotational pivot)
    canvas.drawCircle(leftElbow, 7.0 * scale, jointHalo);
    canvas.drawCircle(leftElbow, 3.5 * scale, jointCenter);
    canvas.drawCircle(rightElbow, 7.0 * scale, jointHalo);
    canvas.drawCircle(rightElbow, 3.5 * scale, jointCenter);

    // Wrists / Hands
    canvas.drawCircle(leftWrist, 5.0 * scale, jointHalo);
    canvas.drawCircle(leftWrist, 2.5 * scale, jointCenter);
    canvas.drawCircle(rightWrist, 5.0 * scale, jointHalo);
    canvas.drawCircle(rightWrist, 2.5 * scale, jointCenter);

    // 13. Degrees readout badge above torso
    _drawAngleBadge(
      canvas,
      Offset(originX, originY - 14 * scale),
      rotationDeg,
      scale,
      isDark,
    );
  }

  void _drawRotationArc(
    Canvas canvas,
    Offset elbow,
    double radius, {
    required bool isLeft,
    required double currentAngleDeg,
    required double maxAngleDeg,
    required Color arcColor,
    required double scale,
  }) {
    final arcPaint = Paint()
      ..color = arcColor
      ..strokeWidth = 2.0 * scale
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(
      center: elbow,
      width: radius * 2.0,
      height: radius * 1.1,
    );

    // In coronal perspective:
    // Left arm sweeps from ~110 deg (inward) to ~25 deg (lateral left)
    // Right arm sweeps from ~70 deg (inward) to ~155 deg (lateral right)
    if (isLeft) {
      const startRad = 25.0 * math.pi / 180.0;
      const sweepRad = 85.0 * math.pi / 180.0;
      canvas.drawArc(rect, startRad, sweepRad, false, arcPaint);
    } else {
      const startRad = 70.0 * math.pi / 180.0;
      const sweepRad = 85.0 * math.pi / 180.0;
      canvas.drawArc(rect, startRad, sweepRad, false, arcPaint);
    }
  }

  void _drawRotationDirectionDot(
    Canvas canvas,
    Offset elbow,
    double radius, {
    required bool isLeft,
    required double progressT,
    required bool isOutward,
    required Color color,
    required double scale,
  }) {
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Determine current position along the arc
    final effectiveT = isOutward
        ? (progressT + 0.12).clamp(0.0, 1.0)
        : (progressT - 0.12).clamp(0.0, 1.0);

    final angleDeg = 110.0 - effectiveT * 85.0;
    final angleRad = angleDeg * math.pi / 180.0;

    final dotPos = Offset(
      isLeft
          ? elbow.dx - radius * math.cos(angleRad)
          : elbow.dx + radius * math.cos(angleRad),
      elbow.dy - radius * math.sin(angleRad) * 0.45,
    );

    canvas.drawCircle(dotPos, 3.2 * scale, dotPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double drawn = 0.0;
    while (drawn < distance) {
      final segLen = math.min(dashLength, distance - drawn);
      canvas.drawLine(
        Offset(start.dx + unitX * drawn, start.dy + unitY * drawn),
        Offset(start.dx + unitX * (drawn + segLen), start.dy + unitY * (drawn + segLen)),
        paint,
      );
      drawn += dashLength + gapLength;
    }
  }

  void _drawAngleBadge(
    Canvas canvas,
    Offset position,
    double angleDeg,
    double scale,
    bool isDark,
  ) {
    final textSpan = TextSpan(
      text: '${angleDeg.toStringAsFixed(0)}° ext',
      style: TextStyle(
        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
        fontSize: 10.5 * scale,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
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
      ..color = (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)).withValues(alpha: 0.4)
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
  bool shouldRepaint(covariant ShoulderRotationPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

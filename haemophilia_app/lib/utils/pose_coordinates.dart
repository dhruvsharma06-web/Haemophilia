import 'dart:ui';
import 'dart:math' as math;

/// Sensor-normalized point to an upright, optionally mirrored, centre-cropped view.
Offset mapPosePoint(Offset point, Size image, Size viewport,
    {int rotation = 0, bool mirror = false}) {
  var x = point.dx;
  var y = point.dy;
  switch (rotation % 360) {
    case 90: x = 1 - point.dy; y = point.dx; break;
    case 180: x = 1 - point.dx; y = 1 - point.dy; break;
    case 270: x = point.dy; y = 1 - point.dx; break;
  }
  final rotated = rotation % 180 == 0 ? image : Size(image.height, image.width);
  if (mirror) x = 1 - x;
  final scale = math.max(viewport.width / rotated.width, viewport.height / rotated.height);
  return Offset(x * rotated.width * scale - (rotated.width * scale - viewport.width) / 2,
      y * rotated.height * scale - (rotated.height * scale - viewport.height) / 2);
}

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/exercise_utils.dart';

class LocalPoseService {
  static const _channel = MethodChannel('hemo/local_pose');
  bool _busy = false;
  bool _disposed = false;

  Future<void> initialize(String exercise) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError(
        'On-device exercise tracking currently requires an Android phone.',
      );
    }
    final id = normalizeExerciseId(exercise);
    await _channel.invokeMethod<void>('initialize', {
      'sideways': [
        kHeelSlide,
        kStraightLegRaise,
        kTerminalKneeExtension,
      ].contains(id),
    });
  }

  Future<Map<String, dynamic>?> detect(
    CameraImage frame,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    if (_busy || _disposed) return null;
    _busy = true;
    try {
      final deviceDegrees = switch (orientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };
      final rotation = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + deviceDegrees) % 360
          : (camera.sensorOrientation - deviceDegrees + 360) % 360;
      final raw = await _channel.invokeMapMethod<String, dynamic>('detect', {
        'width': frame.width,
        'height': frame.height,
        'rotation': rotation,
        'planes': [
          for (final plane in frame.planes)
            {
              'bytes': plane.bytes,
              'rowStride': plane.bytesPerRow,
              'pixelStride': plane.bytesPerPixel ?? 1,
            },
        ],
      });
      return raw == null ? null : Map<String, dynamic>.from(raw);
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List?> reviewImage() =>
      _channel.invokeMethod<Uint8List>('reviewImage');
  Future<void> reset() => _channel.invokeMethod<void>('reset');
  void dispose() {
    _disposed = true;
    unawaited(
      reset().catchError((Object error) {
        debugPrint('Pose cleanup: $error');
      }),
    );
  }
}

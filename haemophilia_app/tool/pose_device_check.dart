// Device-only diagnostic entrypoint. No Firebase initialization or record writes.
// Run: flutter run -t tool/pose_device_check.dart -d DEVICE --no-resident
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:haemophilia_app/services/local_pose_service.dart';
import 'package:haemophilia_app/services/exercise_rules.dart';
import 'package:haemophilia_app/utils/exercise_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Check()));
}

class _Check extends StatefulWidget {
  const _Check();
  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> {
  CameraController? camera;
  String status = 'Checking native frame decoding…';
  @override
  void initState() {
    super.initState();
    unawaited(check());
  }

  Future<void> check() async {
    const channel = MethodChannel('hemo/local_pose');
    try {
      for (final world in [false, true]) {
        await channel.invokeMethod<void>('initialize', {
          'worldPose': world,
          'sideways': false,
        });
        for (final rotation in [0, 90, 180, 270]) {
          final output = await channel.invokeMapMethod<String, dynamic>(
            'detect',
            {
              'width': 64,
              'height': 64,
              'rotation': rotation,
              'planes': [
                {
                  'bytes': Uint8List(4096)..fillRange(0, 4096, 16),
                  'rowStride': 64,
                  'pixelStride': 1,
                },
                for (var i = 0; i < 2; i++)
                  {
                    'bytes': Uint8List(1024)..fillRange(0, 1024, 128),
                    'rowStride': 32,
                    'pixelStride': 1,
                  },
              ],
            },
          );
          if (output == null || output['landmarks'] is! List) {
            throw StateError('Invalid native response');
          }
          debugPrint(
            'POSE_DEVICE_CHECK blank world=$world rotation=$rotation PASS',
          );
        }
      }
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      camera = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camera!.initialize();
      final controller = camera!;
      for (final exercise in [
        kShoulderRotation,
        kElbowFlexionExtension,
        kAssistedShoulderFlexion,
      ]) {
        final pose = LocalPoseService();
        final engine = ExerciseRulesAssessment(exercise);
        await pose.initialize(exercise);
        if (mounted) {
          setState(
            () => status =
                'Checking $exercise. Keep shoulders, elbows, wrists and hips visible.',
          );
        }
        final clock = Stopwatch()..start();
        final done = Completer<void>();
        var frames = 0, detected = 0, valid = 0;
        bool busy = false;
        await controller.startImageStream((frame) async {
          if (busy || done.isCompleted) return;
          busy = true;
          try {
            final result = await pose.detect(
              frame,
              front,
              controller.value.deviceOrientation,
            );
            if (result == null) return;
            frames++;
            final landmarks = (result['landmarks'] as List)
                .map((p) => Map<String, dynamic>.from(p as Map))
                .toList();
            if (landmarks.isNotEmpty) detected++;
            final state = engine.update(
              landmarks,
              (result['width'] as num).toDouble(),
              (result['height'] as num).toDouble(),
              clock.elapsedMicroseconds / 1e6,
              worldLandmarks: (result['world_landmarks'] as List?)
                  ?.map((p) => Map<String, dynamic>.from(p as Map))
                  .toList(),
              angleSource: result['angle_source'] as String?,
            );
            if (state['tracking_valid'] == true) valid++;
            if (frames == 1 || frames % 15 == 0) {
              debugPrint(
                'POSE_DEVICE_CHECK camera exercise=$exercise frames=$frames detected=$detected valid=$valid stage=${state['state']} feedback=${state['feedback']}',
              );
            }
            if (clock.elapsedMilliseconds > 8000 && !done.isCompleted) {
              done.complete();
            }
          } catch (error, stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          } finally {
            busy = false;
          }
        });
        try {
          await done.future.timeout(const Duration(seconds: 20));
        } finally {
          await controller.stopImageStream();
          await pose.reset();
        }
        debugPrint(
          'POSE_DEVICE_CHECK camera exercise=$exercise PASS frames=$frames detected=$detected valid=$valid',
        );
      }
      await camera!.dispose();
      camera = null;
      debugPrint('POSE_DEVICE_CHECK ALL PASS');
      if (mounted) {
        setState(
          () => status = 'Native checks passed. Restoring the main app next.',
        );
      }
    } catch (error, stack) {
      debugPrint('POSE_DEVICE_CHECK FAIL $error\n$stack');
      if (mounted) setState(() => status = 'Check failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        if (camera?.value.isInitialized == true)
          Center(child: CameraPreview(camera!)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(status),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/assessment_history_service.dart';
import '../../services/notification_service.dart';
import '../../utils/exercise_utils.dart';
import '../../widgets/exercise_demo/exercise_demo_dialog.dart';

// ================================================================
// BACKGROUND ISOLATE FRAME CONVERSION (ULTRA-FAST YUV420 -> JPEG)
// ================================================================

class _CameraFrameData {
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int width;
  final int height;
  final int yRowStride;
  final int uRowStride;
  final int vRowStride;
  final int uPixelStride;
  final int vPixelStride;
  final int sensorOrientation;
  final bool isFrontCamera;

  const _CameraFrameData({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uRowStride,
    required this.vRowStride,
    required this.uPixelStride,
    required this.vPixelStride,
    required this.sensorOrientation,
    required this.isFrontCamera,
  });
}

Uint8List? _convertFrameToJpegIsolate(_CameraFrameData data) {
  try {
    const int step = 2; // Downscale by 2 for lightweight MediaPipe input (e.g. 640x480 -> 240x320)
    final int srcW = data.width;
    final int srcH = data.height;

    // Sensor frame is in landscape. Determine rotation needed to produce
    // an upright portrait image for MediaPipe.
    // On Android:
    // - Front camera sensorOrientation is typically 270 degrees (requires 270° clockwise rotation)
    // - Back camera sensorOrientation is typically 90 degrees (requires 90° clockwise rotation)
    final int rotation = data.sensorOrientation % 360;
    final bool rotate90or270 = (rotation == 90 || rotation == 270);
    final int outW = (rotate90or270 ? srcH : srcW) ~/ step;
    final int outH = (rotate90or270 ? srcW : srcH) ~/ step;

    final img.Image rgbImage = img.Image(
      width: outW,
      height: outH,
    );

    final Uint8List yBytes = data.yBytes;
    final Uint8List uBytes = data.uBytes;
    final Uint8List vBytes = data.vBytes;

    final int yRowStride = data.yRowStride;
    final int uRowStride = data.uRowStride;
    final int vRowStride = data.vRowStride;
    final int uPixelStride = data.uPixelStride;
    final int vPixelStride = data.vPixelStride;

    for (int srcY = 0; srcY < srcH; srcY += step) {
      final int yRowStart = srcY * yRowStride;
      final int uvRow = srcY ~/ 2;
      final int uRowStart = uvRow * uRowStride;
      final int vRowStart = uvRow * vRowStride;

      final int scaledY = srcY ~/ step;

      for (int srcX = 0; srcX < srcW; srcX += step) {
        final int yIndex = yRowStart + srcX;
        final int uvCol = srcX ~/ 2;
        final int uIndex = uRowStart + uvCol * uPixelStride;
        final int vIndex = vRowStart + uvCol * vPixelStride;

        final int yVal = yBytes[yIndex];
        final int uVal = uBytes[uIndex] - 128;
        final int vVal = vBytes[vIndex] - 128;

        // Fast integer YUV to RGB approximation
        final int r = (yVal + ((1436 * vVal) >> 10)).clamp(0, 255);
        final int g = (yVal - ((352 * uVal + 731 * vVal) >> 10)).clamp(0, 255);
        final int b = (yVal + ((1815 * uVal) >> 10)).clamp(0, 255);

        final int scaledX = srcX ~/ step;

        final int tgtX;
        final int tgtY;
        switch (rotation) {
          case 270:
            // 270 degrees clockwise: (x, y) -> (y, (outH - 1) - x)
            tgtX = scaledY;
            tgtY = (outH - 1) - scaledX;
            break;
          case 90:
            // 90 degrees clockwise: (x, y) -> ((outW - 1) - y, x)
            tgtX = (outW - 1) - scaledY;
            tgtY = scaledX;
            break;
          case 180:
            // 180 degrees: (x, y) -> ((outW - 1) - x, (outH - 1) - y)
            tgtX = (outW - 1) - scaledX;
            tgtY = (outH - 1) - scaledY;
            break;
          default:
            // 0 degrees: (x, y) -> (x, y)
            tgtX = scaledX;
            tgtY = scaledY;
            break;
        }

        rgbImage.setPixelRgb(tgtX, tgtY, r, g, b);
      }
    }

    return Uint8List.fromList(img.encodeJpg(rgbImage, quality: 60));
  } catch (_) {
    return null;
  }
}

class LiveAssessmentScreen extends StatefulWidget {
  final String exerciseName;

  final List<Map<String, dynamic>>? assignedExercises;

  final String? assignedDoctorId;

  final String? sessionName;

  final String? sessionId;

  final int initialExerciseIndex;

  final int initialCorrectReps;

  final int initialTotalReps;

  final int initialRepSequence;

  final List<Map<String, dynamic>>? initialExerciseProgress;

  const LiveAssessmentScreen({
    super.key,
    required this.exerciseName,
    this.assignedExercises,
    this.assignedDoctorId,
    this.sessionName,
    this.sessionId,
    this.initialExerciseIndex = 0,
    this.initialCorrectReps = 0,
    this.initialTotalReps = 0,
    this.initialRepSequence = 0,
    this.initialExerciseProgress,
  });

  bool get isAssignedSession =>
      assignedExercises != null &&
      assignedExercises!.isNotEmpty;

  @override
  State<LiveAssessmentScreen> createState() =>
      _LiveAssessmentScreenState();
}

class _LiveAssessmentScreenState
    extends State<LiveAssessmentScreen> with WidgetsBindingObserver {

  // ============================================================
  // CONFIGURATION
  // ============================================================

  static const String websocketUrl =
        'wss://displays-lotus-joined-polyester.trycloudflare.com/v1/assessments/live';

  static const Duration frameInterval =
      Duration(milliseconds: 50);

  // ============================================================
  // CAMERA
  // ============================================================

  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _initializing = true;
  bool _cameraReady = false;
  bool _streaming = false;

  // ============================================================
  // WEBSOCKET
  // ============================================================

  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;

  bool _socketConnecting = false;
  bool _socketConnected = false;

  String _connectionStatus = 'Connecting...';
  String? _connectionError;

  // ============================================================
  // FRAME CONTROL & BACKPRESSURE
  // ============================================================

  DateTime _lastAiFrameDispatched = DateTime.fromMillisecondsSinceEpoch(0);
  bool _processingFrame = false;
  int _inFlightFrames = 0;
  DateTime _lastStatsUpdated = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastBackendState = '';

  // ============================================================
  // LIVE AI STATE & POSE NOTIFIERS
  // ============================================================

  final ValueNotifier<List<LiveLandmark>> _landmarksNotifier =
      ValueNotifier<List<LiveLandmark>>([]);
  final ValueNotifier<String> _formNotifier =
      ValueNotifier<String>('Waiting');

  int _repCount = 0;

  String _form = 'Waiting';
  String _errorType = '';
  String _feedback = 'Position yourself in front of the camera.';

  double _score = 0;
  double _rom = 0;
  double _smoothness = 0;

  String _speed = 'Waiting';

  // Last completed rep returned by the backend.
  Map<String, dynamic>? _lastCompletedRep;

  final AssessmentHistoryService _historyService =
      AssessmentHistoryService();
  String? _lastSavedRepSignature;
  int _sessionRepSequence = 0;

  // Persistent session ID reused across pauses/resumes.
  late final String _sessionId;
  bool _isExitingOrSaving = false;
  List<Map<String, dynamic>> _exerciseProgress = [];

  // ============================================================
  // ASSIGNED ASSESSMENT
  // ============================================================

  bool _assignedMode = false;
  bool _switchingExercise = false;
  bool _completed = false;

  int _currentAssignedIndex = 0;
  int _currentCorrectReps = 0;
  int _currentTotalReps = 0;

  List<Map<String, dynamic>> _assignedExercises = [];

  // ============================================================
  // UI VIEW MODE (COMPACT / EXPANDED)
  // ============================================================

  bool _isCompactView = false;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final user = FirebaseAuth.instance.currentUser;
    _sessionId = (widget.sessionId != null && widget.sessionId!.isNotEmpty)
        ? widget.sessionId!
        : (user != null
            ? '${user.uid}_${DateTime.now().millisecondsSinceEpoch}'
            : DateTime.now().microsecondsSinceEpoch.toString());

    if (widget.assignedExercises != null &&
        widget.assignedExercises!.isNotEmpty) {
      _assignedMode = true;

      _assignedExercises = widget.assignedExercises!
          .map(
            (exercise) => Map<String, dynamic>.from(exercise),
          )
          .toList();

      // Defensive sort so the live screen always follows the doctor's
      // intended sequence even if the caller did not pre-sort the list.
      _assignedExercises.sort(
        (a, b) => _toInt(a['order']).compareTo(
          _toInt(b['order']),
        ),
      );

      final safeIndex = widget.initialExerciseIndex.clamp(
        0,
        _assignedExercises.length - 1,
      );
      _currentAssignedIndex = safeIndex;
      _currentCorrectReps = widget.initialCorrectReps;
      _currentTotalReps = widget.initialTotalReps;
      _sessionRepSequence = widget.initialRepSequence;
      _repCount = widget.initialTotalReps;

      if (widget.initialExerciseProgress != null &&
          widget.initialExerciseProgress!.isNotEmpty) {
        _exerciseProgress = widget.initialExerciseProgress!
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        _exerciseProgress = _assignedExercises.map((e) {
          final target = _toInt(e['targetCorrectReps']);
          return {
            'exercise': e['exercise'],
            'name': _assignedExerciseDisplayName(e['exercise']?.toString() ?? ''),
            'targetCorrectReps': target,
            'completedCorrectReps': 0,
            'completedTotalReps': 0,
            'status': 'pending',
          };
        }).toList();
      }

      if (_currentAssignedIndex < _exerciseProgress.length) {
        if (_exerciseProgress[_currentAssignedIndex]['status'] != 'completed') {
          _exerciseProgress[_currentAssignedIndex]['status'] = 'in_progress';
          _exerciseProgress[_currentAssignedIndex]['completedCorrectReps'] = _currentCorrectReps;
          _exerciseProgress[_currentAssignedIndex]['completedTotalReps'] = _currentTotalReps;
        }
      }
    }

    _initialize();
  }

  String _currentAssignedExercise() {
    if (!_assignedMode ||
        _assignedExercises.isEmpty ||
        _currentAssignedIndex >= _assignedExercises.length) {
      return widget.exerciseName;
    }

    return _assignedExercises[_currentAssignedIndex]['exercise']
            ?.toString() ??
        widget.exerciseName;
  }

  int _currentAssignedTarget() {
    if (!_assignedMode ||
        _assignedExercises.isEmpty ||
        _currentAssignedIndex >= _assignedExercises.length) {
      return 0;
    }

    return _toInt(
      _assignedExercises[_currentAssignedIndex]['targetCorrectReps'],
    );
  }

  String _assignedExerciseDisplayName(String exercise) {
    return getExerciseDisplayName(exercise);
  }

  String _currentExerciseDisplayName() {
    if (!_assignedMode) {
      return widget.exerciseName;
    }

    return _assignedExerciseDisplayName(
      _currentAssignedExercise(),
    );
  }

  Future<void> _initialize() async {
    try {
      await _initializeCamera();
      await _connectWebSocket();

      if (mounted) {
        setState(() {
          _initializing = false;
        });
      }

      await _startImageStream();
    } catch (e) {
      debugPrint('Live assessment initialization error: $e');

      if (!mounted) return;

      setState(() {
        _initializing = false;
        _connectionError = e.toString();
      });
    }
  }

  // ============================================================
  // CAMERA INITIALIZATION
  // ============================================================

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();

    if (_cameras.isEmpty) {
      throw Exception('No camera was found.');
    }

    CameraDescription selectedCamera = _cameras.first;

    for (final camera in _cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    final controller = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _cameraReady = true;
    });
  }

  // ============================================================
  // WEBSOCKET CONNECTION
  // ============================================================

  Future<void> _connectWebSocket() async {
    if (_socketConnecting || _socketConnected) {
      return;
    }

    _socketConnecting = true;

    if (mounted) {
      setState(() {
        _connectionStatus = 'Connecting to AI...';
        _connectionError = null;
      });
    }

    debugPrint('Connecting to WebSocket: $websocketUrl');

    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse(websocketUrl),
        connectTimeout: const Duration(seconds: 10),
      );

      _channel = channel;

      await channel.ready;

      debugPrint('WebSocket connected successfully.');

      _socketConnected = true;
      _socketConnecting = false;

      // If resuming at an exercise beyond index 0, tell backend AI to switch to it
      if (_assignedMode && _currentAssignedIndex > 0) {
        final currentEx = _currentAssignedExercise();
        try {
          channel.sink.add(
            jsonEncode({
              'type': 'switch_exercise',
              'exercise': currentEx,
            }),
          );
          debugPrint('Resumed session: sent switch_exercise for $currentEx');
        } catch (e) {
          debugPrint('Failed to send switch_exercise on resume: $e');
        }
      }

      if (mounted) {
        setState(() {
          _connectionStatus = 'AI Live';
          _connectionError = null;
        });
      }

      _socketSubscription = channel.stream.listen(
        _handleSocketMessage,
        onError: (error) {
          debugPrint('WebSocket error: $error');

          _socketConnected = false;
          _socketConnecting = false;

          if (mounted) {
            setState(() {
              _connectionStatus = 'AI Connection Error';
              _connectionError = error.toString();
            });
          }
        },
        onDone: () {
          debugPrint('WebSocket connection closed.');

          _socketConnected = false;
          _socketConnecting = false;

          if (mounted) {
            setState(() {
              _connectionStatus = 'AI Disconnected';
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');

      _socketConnected = false;
      _socketConnecting = false;

      if (mounted) {
        setState(() {
          _connectionStatus = 'AI Connection Failed';
          _connectionError = e.toString();
        });
      }
    }
  }

  // ============================================================
  // WEBSOCKET MESSAGE HANDLING
  // ============================================================

  void _handleSocketMessage(dynamic message) {
    try {
      if (message is! String) {
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(message) as Map<String, dynamic>;

      if (data['type'] == 'error') {
        debugPrint(
          'Backend error: ${data['message']}',
        );

        if (mounted) {
          setState(() {
            _connectionStatus = 'AI Error';
            _connectionError =
                data['message']?.toString() ?? 'Unknown backend error';
          });
        }

        return;
      }

      if (data['type'] != 'live_state') {
        return;
      }

      final landmarksData = data['landmarks'];

      final List<LiveLandmark> newLandmarks = [];

      if (landmarksData is List) {
        for (final item in landmarksData) {
          if (item is Map) {
            newLandmarks.add(
              LiveLandmark(
                x: _toDouble(item['x']),
                y: _toDouble(item['y']),
                z: _toDouble(item['z']),
                visibility: _toDouble(item['visibility']),
              ),
            );
          }
        }
      }

      final completedRep = data['completed_rep'];
      final bool hasCompletedRep = completedRep is Map;

      // Release backpressure immediately: backend has returned a response
      if (_inFlightFrames > 0) {
        _inFlightFrames--;
      }

      // State transition debugging (only emits when state actually changes)
      final String backendState = data['state']?.toString().toUpperCase() ?? '';
      if (backendState.isNotEmpty && backendState != _lastBackendState) {
        if (backendState == 'RAISING') {
          debugPrint('[REP DEBUG] movement started');
        } else if (backendState == 'TOP') {
          debugPrint('[REP DEBUG] top reached');
        } else if (backendState == 'LOWERING') {
          debugPrint('[REP DEBUG] movement returned');
        }
        _lastBackendState = backendState;
      }

      // Handle completed rep immediately and synchronously
      if (hasCompletedRep) {
        final form = completedRep['form']?.toString().toLowerCase() ??
            completedRep['label']?.toString().toLowerCase() ??
            completedRep['session_record']?['predicted_label']?.toString().toLowerCase() ??
            '';

        final bool correct = form == 'correct' ||
            (form.contains('correct') && !form.contains('incorrect'));

        _currentTotalReps++;
        if (correct) {
          _currentCorrectReps++;
        }

        final target = _currentAssignedTarget();

        debugPrint('[REP DEBUG] REP COMPLETED');
        debugPrint('[REP DEBUG] correct=$correct');
        debugPrint('[REP DEBUG] total=$_currentTotalReps');
        debugPrint('[REP DEBUG] correct=$_currentCorrectReps');

        // Assignment progress is based on completed correct repetitions
        if (_assignedMode && !_switchingExercise && !_completed) {
          if (_currentAssignedIndex < _exerciseProgress.length) {
            _exerciseProgress[_currentAssignedIndex]['completedCorrectReps'] =
                _currentCorrectReps;
            _exerciseProgress[_currentAssignedIndex]['completedTotalReps'] =
                _currentTotalReps;
            if (_currentCorrectReps >= target && target > 0) {
              _exerciseProgress[_currentAssignedIndex]['status'] = 'completed';
            } else {
              _exerciseProgress[_currentAssignedIndex]['status'] = 'in_progress';
            }
          }

          if (target > 0 && _currentCorrectReps >= target) {
            _switchingExercise = true;
            unawaited(_handleAssignedTargetReached());
          }
        }

        final rep = Map<String, dynamic>.from(completedRep);
        final backendRepNumber = _toInt(rep['rep_number'] ?? rep['session_record']?['rep_number']);
        final normalizedRepNumber =
            backendRepNumber > 0 ? backendRepNumber : ++_sessionRepSequence;
        if (backendRepNumber > 0 && backendRepNumber > _sessionRepSequence) {
          _sessionRepSequence = backendRepNumber;
        }
        rep['rep_number'] = normalizedRepNumber;

        final repSignature =
            '${_currentExerciseDisplayName()}_rep_${normalizedRepNumber}_${_sessionId}_${rep['score']}';
        if (repSignature != _lastSavedRepSignature) {
          _lastSavedRepSignature = repSignature;
          unawaited(_saveCompletedRepToHistory(rep));
        }

        _lastCompletedRep = rep;
      }

      // 1. Update pose landmarks and form immediately without widget tree rebuild
      final newForm = data['form']?.toString() ?? _form;
      _formNotifier.value = newForm;
      _updateLandmarksAdaptive(newLandmarks);

      // 2. Extract stats & check if UI rebuild is needed
      final newRepCount = _toInt(data['rep_count'], defaultValue: _repCount);
      final bool repCountChanged = newRepCount != _repCount;
      final now = DateTime.now();
      final bool throttleElapsed =
          now.difference(_lastStatsUpdated).inMilliseconds >= 150;

      _score = _toDouble(data['score']);
      _rom = _toDouble(data['range_of_motion']);
      _speed = data['speed']?.toString() ?? 'Waiting';
      _smoothness = _toDouble(data['smoothness']);
      _errorType = data['error_type']?.toString() ?? '';
      _feedback = data['feedback']?.toString() ??
          'Keep following the exercise instructions.';
      _form = newForm;

      // Rebuild UI immediately when rep completes, rep count changes, or throttle interval elapsed
      if (hasCompletedRep || repCountChanged || throttleElapsed) {
        _lastStatsUpdated = now;
        if (mounted) {
          setState(() {
            _socketConnected = true;
            _connectionStatus = 'AI Live';
            _repCount = math.max(newRepCount, _currentTotalReps);
          });
        }
      }
    } catch (e) {
      debugPrint(
        'Could not process WebSocket message: $e',
      );
    }
  }

  Future<void> _handleAssignedTargetReached() async {
    final bool hasNext =
        _currentAssignedIndex + 1 < _assignedExercises.length;

    if (!hasNext) {
      await _completeAssignedSession();
    } else {
      await _switchToNextAssignedExercise();
    }
  }

  Future<void> _switchToNextAssignedExercise() async {
    final nextIndex = _currentAssignedIndex + 1;
    if (nextIndex >= _assignedExercises.length) {
      _switchingExercise = false;
      return;
    }

    final nextExercise =
        _assignedExercises[nextIndex]['exercise']?.toString();

    if (nextExercise == null || nextExercise.isEmpty) {
      debugPrint(
        'Cannot switch exercise: missing exercise name at index $nextIndex',
      );
      _switchingExercise = false;
      return;
    }

    try {
      if (_channel == null || !_socketConnected) {
        throw StateError(
          'WebSocket is not connected.',
        );
      }

      _channel!.sink.add(
        jsonEncode({
          'type': 'switch_exercise',
          'exercise': nextExercise,
        }),
      );

      debugPrint(
        'Requested exercise switch: '
        '${_currentAssignedExercise()} -> $nextExercise',
      );
    } catch (e) {
      debugPrint(
        'Could not switch exercise: $e',
      );

      _switchingExercise = false;

      if (mounted) {
        setState(() {
          _feedback =
              'Could not start the next exercise. Please try again.';
        });
      }

      return;
    }

    if (!mounted) {
      _switchingExercise = false;
      return;
    }

    setState(() {
      _currentAssignedIndex = nextIndex;

      _currentCorrectReps = 0;
      _currentTotalReps = 0;

      _lastCompletedRep = null;

      _repCount = 0;

      _form = 'Waiting';

      _feedback =
          'Starting ${_assignedExerciseDisplayName(nextExercise)}...';

      _score = 0;
      _rom = 0;
      _smoothness = 0;

      _speed = 'Waiting';
      _errorType = '';
    });

    // Give the backend a short moment to replace the assessment object before
    // the next live frames are evaluated.
    await Future<void>.delayed(
      const Duration(milliseconds: 500),
    );

    _switchingExercise = false;
  }

  Future<void> _completeAssignedSession() async {
    if (_completed) return;
    _completed = true;
    _switchingExercise = false;

    debugPrint('All assigned exercises completed. Finalizing session.');

    // 1. Immediately stop the camera stream
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error stopping camera stream: $e');
    }
    _streaming = false;

    // 2. Close WebSocket and cancel subscription
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _channel?.sink.close();
    } catch (e) {
      debugPrint('Error closing WebSocket: $e');
    }
    _channel = null;
    _socketConnected = false;

    final user = FirebaseAuth.instance.currentUser;
    final patientId = user?.uid;
    final sessionName = widget.sessionName ?? 'Physiotherapy Session';

    // 4. Mark session completed in Firestore
    if (patientId != null) {
      try {
        // Update exerciseAssignments to completed so patient cannot re-start it
        await FirebaseFirestore.instance
            .collection('exerciseAssignments')
            .doc(patientId)
            .set({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Create / update assessmentSessions
        await FirebaseFirestore.instance
            .collection('assessmentSessions')
            .doc(_sessionId)
            .set({
          'sessionId': _sessionId,
          'patientId': patientId,
          'doctorId': widget.assignedDoctorId ?? '',
          'sessionName': sessionName,
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'endedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'exercises': _assignedExercises.map((e) => {
            'exercise': e['exercise'],
            'name': _assignedExerciseDisplayName(e['exercise']?.toString() ?? ''),
            'targetCorrectReps': _toInt(e['targetCorrectReps']),
            'status': 'completed',
          }).toList(),
        }, SetOptions(merge: true));

        // Notify doctor if assignedDoctorId is present
        if (widget.assignedDoctorId != null &&
            widget.assignedDoctorId!.isNotEmpty) {
          final patientDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(patientId)
              .get();
          final patientName =
              patientDoc.data()?['name']?.toString() ?? 'Patient';

          await NotificationService().sendNotification(
            targetUserId: widget.assignedDoctorId!,
            title: 'Session Completed',
            body: '$patientName completed $sessionName.',
            data: {
              'type': 'session_completed',
              'patientId': patientId,
              'sessionId': _sessionId,
              'sessionName': sessionName,
            },
          );
        }
      } catch (e) {
        debugPrint('Error saving completed session to Firestore: $e');
      }
    }

    if (!mounted) return;

    // 5. Show Session Completed dialog with Done button
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.green,
            size: 56,
          ),
          title: const Text(
            'Session Completed!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Great job! You have completed all exercises for '
            '"$sessionName". Your progress has been saved.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(this.context); // Pop LiveAssessmentScreen
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveCompletedRepToHistory(
    Map<String, dynamic> rep,
  ) async {
    try {
      debugPrint(
        'Saving assessment history for Firebase UID: '
        '${_historyService.currentUserId}',
      );

      await _historyService.saveCompletedRep(
        exercise: _currentExerciseDisplayName(),
        sessionId: _sessionId,
        rep: rep,
        sessionName: widget.sessionName,
        errorFrameUrl: _errorFrameUrl(rep),
      );
    } catch (e, stackTrace) {
      debugPrint('Could not save assessment history: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assessment result could not be saved: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _updateLandmarksAdaptive(List<LiveLandmark> next) {
    if (next.length != 33) return;

    final current = _landmarksNotifier.value;
    if (current.length != 33) {
      _landmarksNotifier.value = next;
      return;
    }

    final List<LiveLandmark> smoothed = List<LiveLandmark>.generate(33, (i) {
      final a = current[i];
      final b = next[i];

      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final distSq = dx * dx + dy * dy;

      // Adaptive smoothing factor:
      // Fast movement (distSq >= 0.0016, i.e. delta >= 0.04): alpha = 0.92 (immediate tracking, zero lag)
      // Slow movement (distSq <= 0.0001, i.e. delta <= 0.01): alpha = 0.50 (smooth noise reduction)
      final double alpha;
      if (distSq >= 0.0016) {
        alpha = 0.92;
      } else if (distSq <= 0.0001) {
        alpha = 0.50;
      } else {
        final t = (distSq - 0.0001) / 0.0015;
        alpha = 0.50 + 0.42 * t;
      }

      return LiveLandmark(
        x: a.x + dx * alpha,
        y: a.y + dy * alpha,
        z: a.z + (b.z - a.z) * alpha,
        visibility: a.visibility + (b.visibility - a.visibility) * alpha,
      );
    });

    _landmarksNotifier.value = smoothed;
  }

  Future<void> _showErrorFrame(
    String url,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (dialogContext) => _ErrorFrameViewerDialog(url: url),
    );
  }

  // ============================================================
  // CAMERA IMAGE STREAM
  // ============================================================

  Future<void> _startImageStream() async {
    if (_controller == null) {
      return;
    }

    if (_streaming) {
      return;
    }

    if (!_socketConnected) {
      debugPrint(
        'Waiting for WebSocket before starting image stream.',
      );

      return;
    }

    try {
      await _controller!.startImageStream(
        _processCameraImage,
      );

      _streaming = true;

      debugPrint('Camera image stream started.');
    } catch (e) {
      debugPrint(
        'Could not start camera image stream: $e',
      );

      if (mounted) {
        setState(() {
          _connectionError =
              'Could not start camera stream: $e';
        });
      }
    }
  }

  Future<void> _processCameraImage(
    CameraImage cameraImage,
  ) async {
    if (!_socketConnected || _channel == null) {
      return;
    }

    // 1. Drop frame if local conversion is currently busy
    if (_processingFrame) {
      return;
    }

    final now = DateTime.now();

    // 2. Bound network in-flight queue to max 3 frames (~150ms buffer).
    // This allows full 20 FPS throughput over typical mobile/network latency,
    // while strictly preventing buffer queue accumulation if network stalls.
    if (_inFlightFrames >= 3) {
      if (now.difference(_lastAiFrameDispatched).inMilliseconds < 500) {
        return; // Drop intermediate camera frame: latest frame wins!
      }
      // Timed out waiting for network response: allow next frame
      _inFlightFrames = 0;
    }

    // 3. Minimum interval throttle (50ms = 20 FPS AI inference rate expected by backend)
    if (now.difference(_lastAiFrameDispatched) < frameInterval) {
      return;
    }

    if (cameraImage.format.group != ImageFormatGroup.yuv420 ||
        cameraImage.planes.length < 3) {
      return;
    }

    _processingFrame = true;

    try {
      // Extract raw plane data on main isolate (instantaneous < 0.1ms)
      final frameData = _CameraFrameData(
        yBytes: cameraImage.planes[0].bytes,
        uBytes: cameraImage.planes[1].bytes,
        vBytes: cameraImage.planes[2].bytes,
        width: cameraImage.width,
        height: cameraImage.height,
        yRowStride: cameraImage.planes[0].bytesPerRow,
        uRowStride: cameraImage.planes[1].bytesPerRow,
        vRowStride: cameraImage.planes[2].bytesPerRow,
        uPixelStride: cameraImage.planes[1].bytesPerPixel ?? 1,
        vPixelStride: cameraImage.planes[2].bytesPerPixel ?? 1,
        sensorOrientation: _controller?.description.sensorOrientation ?? 0,
        isFrontCamera: _controller?.description.lensDirection ==
            CameraLensDirection.front,
      );

      // Run fast conversion + in-place rotation + JPEG compression in background isolate
      final Uint8List? jpegBytes =
          await compute(_convertFrameToJpegIsolate, frameData);

      if (jpegBytes == null || jpegBytes.isEmpty) {
        return;
      }

      if (!_socketConnected || _channel == null) {
        return;
      }

      _inFlightFrames++;
      _lastAiFrameDispatched = DateTime.now();
      _channel!.sink.add(jpegBytes);
    } catch (e) {
      debugPrint('Frame processing error: $e');
      if (_inFlightFrames > 0) {
        _inFlightFrames--;
      }
    } finally {
      _processingFrame = false;
    }
  }

  // ============================================================
  // PROGRESS GETTERS & LIFECYCLE
  // ============================================================

  int get _totalCompletedCorrectReps {
    int sum = 0;
    for (int i = 0; i < _exerciseProgress.length; i++) {
      if (i == _currentAssignedIndex) {
        sum += _currentCorrectReps;
      } else {
        sum += _toInt(_exerciseProgress[i]['completedCorrectReps']);
      }
    }
    return sum;
  }

  int get _totalCompletedReps {
    int sum = 0;
    for (int i = 0; i < _exerciseProgress.length; i++) {
      if (i == _currentAssignedIndex) {
        sum += _currentTotalReps;
      } else {
        sum += _toInt(_exerciseProgress[i]['completedTotalReps']);
      }
    }
    return sum;
  }

  int get _totalTargetCorrectReps {
    int sum = 0;
    for (final ex in _assignedExercises) {
      sum += _toInt(ex['targetCorrectReps']);
    }
    return sum;
  }

  double get _progressPercentage {
    final target = _totalTargetCorrectReps;
    if (target <= 0) return 0.0;
    return (_totalCompletedCorrectReps / target).clamp(0.0, 1.0) * 100;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (!_completed && !_isExitingOrSaving && _assignedMode) {
        unawaited(_autoPauseStateInBackground());
      }
    }
  }

  Future<void> _autoPauseStateInBackground() async {
    final user = FirebaseAuth.instance.currentUser;
    final patientId = user?.uid;
    if (patientId == null) return;

    try {
      final progressPct = _progressPercentage;
      final totalCorrect = _totalCompletedCorrectReps;
      final totalReps = _totalCompletedReps;

      await FirebaseFirestore.instance
          .collection('exerciseAssignments')
          .doc(patientId)
          .set({
        'status': 'paused',
        'sessionId': _sessionId,
        'currentExerciseIndex': _currentAssignedIndex,
        'currentExercise': _currentAssignedExercise(),
        'completedCorrectReps': totalCorrect,
        'totalCompletedReps': totalReps,
        'progressPercentage': progressPct,
        'exerciseProgress': _exerciseProgress,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('assessmentSessions')
          .doc(_sessionId)
          .set({
        'sessionId': _sessionId,
        'assignmentId': patientId,
        'patientId': patientId,
        'doctorId': widget.assignedDoctorId ?? '',
        'sessionName': widget.sessionName ?? 'Physiotherapy Session',
        'status': 'paused',
        'currentExerciseIndex': _currentAssignedIndex,
        'currentExercise': _currentAssignedExercise(),
        'progressPercentage': progressPct,
        'exercises': _exerciseProgress,
        'totalCorrectReps': totalCorrect,
        'totalReps': totalReps,
        'targetCorrectReps': _totalTargetCorrectReps,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error auto-pausing session in background: $e');
    }
  }

  // ============================================================
  // PAUSE / SAVE / RESUME / DISCARD
  // ============================================================

  Future<void> _saveAndExit() async {
    if (_isExitingOrSaving) return;
    _isExitingOrSaving = true;

    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}
    _streaming = false;

    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _socketConnected = false;

    final user = FirebaseAuth.instance.currentUser;
    final patientId = user?.uid;
    final sessionName = widget.sessionName ?? 'Physiotherapy Session';

    if (_currentAssignedIndex < _exerciseProgress.length) {
      _exerciseProgress[_currentAssignedIndex]['completedCorrectReps'] = _currentCorrectReps;
      _exerciseProgress[_currentAssignedIndex]['completedTotalReps'] = _currentTotalReps;
      if (_currentCorrectReps >= _currentAssignedTarget() && _currentAssignedTarget() > 0) {
        _exerciseProgress[_currentAssignedIndex]['status'] = 'completed';
      } else {
        _exerciseProgress[_currentAssignedIndex]['status'] = 'in_progress';
      }
    }

    if (patientId != null) {
      try {
        final progressPct = _progressPercentage;
        final totalCorrect = _totalCompletedCorrectReps;
        final totalReps = _totalCompletedReps;
        final targetReps = _totalTargetCorrectReps;

        await FirebaseFirestore.instance
            .collection('exerciseAssignments')
            .doc(patientId)
            .set({
          'status': 'paused',
          'sessionId': _sessionId,
          'currentExerciseIndex': _currentAssignedIndex,
          'currentExercise': _currentAssignedExercise(),
          'completedCorrectReps': totalCorrect,
          'totalCompletedReps': totalReps,
          'progressPercentage': progressPct,
          'exerciseProgress': _exerciseProgress,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance
            .collection('assessmentSessions')
            .doc(_sessionId)
            .set({
          'sessionId': _sessionId,
          'assignmentId': patientId,
          'patientId': patientId,
          'doctorId': widget.assignedDoctorId ?? '',
          'sessionName': sessionName,
          'status': 'paused',
          'currentExerciseIndex': _currentAssignedIndex,
          'currentExercise': _currentAssignedExercise(),
          'progressPercentage': progressPct,
          'exercises': _exerciseProgress,
          'totalCorrectReps': totalCorrect,
          'totalReps': totalReps,
          'targetCorrectReps': targetReps,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint('Session $_sessionId saved and paused successfully.');
      } catch (e) {
        debugPrint('Error saving paused session to Firestore: $e');
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _discardAndExit() async {
    if (_isExitingOrSaving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
          size: 48,
        ),
        title: const Text(
          'Discard Session?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to discard your progress? '
          'This session will be marked as discarded and cannot be resumed.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _isExitingOrSaving = true;

    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}
    _streaming = false;

    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _socketConnected = false;

    final user = FirebaseAuth.instance.currentUser;
    final patientId = user?.uid;
    final sessionName = widget.sessionName ?? 'Physiotherapy Session';

    if (patientId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('exerciseAssignments')
            .doc(patientId)
            .set({
          'status': 'discarded',
          'discardedAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance
            .collection('assessmentSessions')
            .doc(_sessionId)
            .set({
          'sessionId': _sessionId,
          'assignmentId': patientId,
          'patientId': patientId,
          'doctorId': widget.assignedDoctorId ?? '',
          'sessionName': sessionName,
          'status': 'discarded',
          'discardedAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint('Session $_sessionId marked as discarded.');
      } catch (e) {
        debugPrint('Error marking session as discarded: $e');
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleExitAttempt() async {
    if (_completed || _isExitingOrSaving) return;

    if (!_assignedMode) {
      await _endAssessment();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Assessment in progress',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You have not completed all exercises for "${widget.sessionName ?? 'this session'}". What would you like to do?',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _saveAndExit();
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text(
                    'Save & Exit',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _discardAndExit();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text(
                    'Discard Progress',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                  },
                  child: const Text(
                    'Continue Assessment',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _endAssessment() async {
    try {
      if (_controller != null &&
          _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (_) {}

    _streaming = false;

    await _socketSubscription?.cancel();
    _socketSubscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
    _socketConnected = false;

    if (mounted) {
      Navigator.pop(context);
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  double _toDouble(
    dynamic value, {
    double defaultValue = 0,
  }) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? defaultValue;
    }

    return defaultValue;
  }

  int _toInt(
    dynamic value, {
    int defaultValue = 0,
  }) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }

    return defaultValue;
  }

  String _errorLabel(dynamic raw) {
    final value = raw?.toString() ?? '';

    switch (value) {
      case 'RIGHT_ARM_LOW':
        return 'RIGHT ARM TOO LOW';
      case 'LEFT_ARM_LOW':
        return 'LEFT ARM TOO LOW';
      case 'ARM_ASYMMETRY':
        return 'ARMS NOT SYMMETRIC';
      case 'BODY_TILT':
        return 'BODY TILT DETECTED';
      case 'GENERAL_FORM_ERROR':
        return 'GENERAL FORM ERROR';
      default:
        return value.replaceAll('_', ' ').toUpperCase();
    }
  }

  static const String errorFrameBaseUrl =
      'https://displays-lotus-joined-polyester.trycloudflare.com/v1/assets/error-frames/';

  String? _errorFrameUrl(Map<String, dynamic> rep) {
    // Support all versions of the backend payload so the image keeps working
    // even if the backend calls the field error_frame_url, errorFrameUrl,
    // error_frame_path, or errorFramePath.
    dynamic raw = rep['error_frame_url'] ??
        rep['errorFrameUrl'] ??
        rep['error_frame_path'] ??
        rep['errorFramePath'];

    // Some backend versions place the artifact information inside
    // session_record.
    if ((raw == null || raw.toString().trim().isEmpty) &&
        rep['session_record'] is Map) {
      final record = Map<String, dynamic>.from(
        rep['session_record'] as Map,
      );
      raw = record['error_frame_url'] ??
          record['errorFrameUrl'] ??
          record['error_frame_path'] ??
          record['errorFramePath'];
    }

    if (raw == null) {
      return null;
    }

    final value = raw.toString().trim();
    if (value.isEmpty) {
      return null;
    }

    // If the backend already supplied a complete URL, use it directly.
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    // Backend paths are Windows paths on the development machine. Only the
    // filename is needed by the /v1/assets/error-frames/{filename} endpoint.
    final normalized = value.replaceAll(r'\', '/');
    final filename = normalized.split('/').last.trim();

    if (filename.isEmpty) {
      return null;
    }

    return '$errorFrameBaseUrl${Uri.encodeComponent(filename)}';
  }

  double _completedDouble(
    Map<String, dynamic> rep,
    String key, {
    double fallback = 0,
  }) {
    return _toDouble(rep[key], defaultValue: fallback);
  }

  Widget _buildGlassContainer({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    BorderRadius? borderRadius,
    Color? backgroundColor,
    Border? border,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(14);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.black.withValues(alpha: 0.65),
        borderRadius: radius,
        border: border ??
            Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.0,
            ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _completedMetric(
    String title,
    String value,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedRepPanel() {
    final rep = _lastCompletedRep;

    if (rep == null) {
      return const SizedBox.shrink();
    }

    final form = rep['form']?.toString() ??
        rep['label']?.toString() ?? 'Unknown';
    final incorrect = form.toLowerCase().contains('incorrect');
    final error = rep['error_type']?.toString() ??
        rep['error']?.toString() ?? '';
    final feedback = rep['feedback']?.toString() ??
        'Rep completed.';

    final score = _completedDouble(rep, 'score');
    final rom = _completedDouble(
      rep,
      'range_of_motion',
      fallback: _completedDouble(rep, 'rom'),
    );
    final duration = _completedDouble(rep, 'duration');
    final speed = rep['speed']?.toString() ?? 'Unknown';
    final confidence = _completedDouble(
      rep,
      'confidence',
      fallback: _completedDouble(rep, 'lstm_confidence'),
    );

    final errorFrameUrl = _errorFrameUrl(rep);

    // Compact mode: show a slim single-line summary with a dismiss button
    if (_isCompactView) {
      return _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(
              incorrect ? Icons.warning_amber_rounded : Icons.check_circle,
              color: incorrect ? Colors.redAccent : Colors.greenAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'REP ${rep['rep_number'] ?? _repCount} ${form.toUpperCase()}'
                '${incorrect && error.isNotEmpty ? ' — ${_errorLabel(error)}' : ' • Score: ${score.toStringAsFixed(0)} • ROM: ${rom.toStringAsFixed(0)}°'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: incorrect ? Colors.redAccent : Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
            if (incorrect && errorFrameUrl != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showErrorFrame(errorFrameUrl),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_search_rounded,
                        color: Colors.redAccent,
                        size: 14,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'View Error',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            InkWell(
              onTap: () {
                setState(() {
                  _lastCompletedRep = null;
                });
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  color: Colors.white70,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Expanded mode: semi-transparent, compact card with dismiss button
    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                incorrect
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle,
                color: incorrect
                    ? Colors.redAccent
                    : Colors.greenAccent,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'REP ${rep['rep_number'] ?? _repCount} — '
                  '${form.toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _lastCompletedRep = null;
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),

          if (incorrect && error.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              _errorLabel(error),
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],

          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  feedback,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.2,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
              if (incorrect &&
                  errorFrameUrl != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _showErrorFrame(errorFrameUrl);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      errorFrameUrl,
                      width: 84,
                      height: 58,
                      fit: BoxFit.contain,
                      errorBuilder: (
                        context,
                        error,
                        stackTrace,
                      ) {
                        return Container(
                          width: 84,
                          height: 58,
                          color: Colors.white10,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.white38,
                            size: 16,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              _completedMetric(
                'SCORE',
                '${score.toStringAsFixed(0)}/100',
              ),
              _completedMetric(
                'ROM',
                '${rom.toStringAsFixed(1)}°',
              ),
              _completedMetric(
                'SPEED',
                speed,
              ),
              _completedMetric(
                'DUR',
                '${duration.toStringAsFixed(1)}s',
              ),
            ],
          ),

          const SizedBox(height: 4),

          Row(
            children: [
              _completedMetric(
                'LSTM',
                '${confidence.toStringAsFixed(0)}%',
              ),
              _completedMetric(
                'SMOOTH',
                '${(_completedDouble(rep, 'smoothness_raw').clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isWip = isWorkInProgressExercise(_currentAssignedExercise());

    return PopScope(
      canPop: _completed || _isExitingOrSaving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExitAttempt();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleExitAttempt,
          ),
          title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.sessionName != null && widget.sessionName!.isNotEmpty)
              Text(
                widget.sessionName!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _currentExerciseDisplayName(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isWip) ...[
                  const SizedBox(width: 8),
                  buildWipBadge(isDark: true, compact: true),
                ],
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(
                    color: Color(0xFF38BDF8),
                    width: 1.0,
                  ),
                ),
              ),
              onPressed: () {
                showExerciseDemoDialog(
                  context,
                  exerciseName: _currentExerciseDisplayName(),
                );
              },
              icon: const Icon(
                Icons.play_circle_outline_rounded,
                size: 16,
                color: Color(0xFF38BDF8),
              ),
              label: const Text(
                'How to perform',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
              onPressed: () {
                setState(() {
                  _isCompactView = !_isCompactView;
                });
              },
              icon: Icon(
                _isCompactView
                    ? Icons.unfold_more_rounded
                    : Icons.unfold_less_rounded,
                size: 16,
                color: Colors.greenAccent,
              ),
              label: Text(
                _isCompactView ? 'Expand UI' : 'Compact UI',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!_cameraReady || _controller == null) {
      return _buildErrorScreen(
        _connectionError ??
            'Camera could not be started.',
      );
    }

    final double screenHeight = MediaQuery.sizeOf(context).height;

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),

        // Skeleton overlay isolated with RepaintBoundary
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: PosePainter(
                  landmarksNotifier: _landmarksNotifier,
                  formNotifier: _formNotifier,
                  isFrontCamera: _controller?.description.lensDirection ==
                      CameraLensDirection.front,
                ),
              ),
            ),
          ),
        ),

        // Top information panel.
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: _buildTopPanel(),
        ),

        // Completed-rep result panel.
        if (_lastCompletedRep != null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 70,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: screenHeight * (_isCompactView ? 0.14 : 0.26),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _buildCompletedRepPanel(),
              ),
            ),
          )
        else
          Positioned(
            left: 10,
            right: 10,
            bottom: 70,
            child: _buildFeedbackPanel(),
          ),

        // End assessment button.
        Positioned(
          left: _isCompactView ? null : 20,
          right: 20,
          bottom: 14,
          child: SizedBox(
            height: _isCompactView ? 38 : 46,
            child: _isCompactView
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.82),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(19),
                      ),
                    ),
                    onPressed: _handleExitAttempt,
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text(
                      'End',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _handleExitAttempt,
                    icon: const Icon(Icons.stop_rounded, size: 20),
                    label: const Text(
                      'End Assessment',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopPanel() {
    final bool aiLive = _socketConnected;
    final bool isWip = isWorkInProgressExercise(_currentAssignedExercise());

    Color statusColor;

    if (aiLive) {
      statusColor = Colors.greenAccent;
    } else if (_socketConnecting) {
      statusColor = Colors.orangeAccent;
    } else {
      statusColor = Colors.redAccent;
    }

    // Compact mode: ultra-slim single-line header with small exercise name & rep counter
    if (_isCompactView) {
      return _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _currentExerciseDisplayName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
            if (isWip) ...[
              const SizedBox(width: 6),
              buildWipBadge(isDark: true, compact: true),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _assignedMode
                    ? '$_currentCorrectReps/${_currentAssignedTarget()} reps'
                    : 'REP $_repCount',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'How to perform',
              child: InkWell(
                onTap: () {
                  showExerciseDemoDialog(
                    context,
                    exerciseName: _currentExerciseDisplayName(),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_circle_outline_rounded,
                    color: Color(0xFF38BDF8),
                    size: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Expand UI',
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isCompactView = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.unfold_more_rounded,
                    color: Colors.white70,
                    size: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Expanded mode: compact translucent glass card with stats strip
    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _connectionStatus,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
              if (isWip) ...[
                const SizedBox(width: 6),
                buildWipBadge(isDark: true, compact: true),
              ],
              const Spacer(),
              if (_assignedMode) ...[
                Text(
                  '$_currentCorrectReps/${_currentAssignedTarget()} Correct',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(Ex ${_currentAssignedIndex + 1}/${_assignedExercises.length})',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'REP $_repCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Streamlined stats strip: SCORE, ROM, SPEED, SMOOTH, FORM
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _compactStat('SCORE', _score.toStringAsFixed(0)),
              _compactStat('ROM', '${_rom.toStringAsFixed(1)}°'),
              _compactStat('SPEED', _speed),
              _compactStat(
                'SMOOTH',
                '${(_smoothness.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
              ),
              _compactStat(
                'FORM',
                _form,
                valueColor: _form.toLowerCase().contains('correct')
                    ? Colors.greenAccent
                    : _form.toLowerCase().contains('incorrect')
                        ? Colors.redAccent
                        : Colors.white,
              ),
            ],
          ),

          if (_connectionError != null) ...[
            const SizedBox(height: 4),
            Text(
              _connectionError!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 10,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactStat(
    String title,
    String value, {
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackPanel() {
    final bool incorrect =
        _form.toLowerCase().contains('incorrect');

    if (_isCompactView) {
      return _buildGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(
              incorrect
                  ? Icons.warning_amber_rounded
                  : Icons.accessibility_new_rounded,
              color: incorrect ? Colors.redAccent : Colors.greenAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorType.isNotEmpty
                    ? '${_errorLabel(_errorType)}: $_feedback'
                    : _feedback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildGlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            incorrect
                ? Icons.warning_amber_rounded
                : Icons.accessibility_new_rounded,
            color: incorrect
                ? Colors.redAccent
                : Colors.greenAccent,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorType.isNotEmpty) ...[
                  Text(
                    _errorLabel(_errorType),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  _feedback,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    height: 1.2,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Live Assessment Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _landmarksNotifier.dispose();
    _formNotifier.dispose();

    _socketSubscription?.cancel();

    try {
      _channel?.sink.close();
    } catch (_) {}

    _controller?.dispose();

    super.dispose();
  }
}

// ================================================================
// LANDMARK MODEL
// ================================================================

class LiveLandmark {
  final double x;
  final double y;
  final double z;
  final double visibility;

  const LiveLandmark({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });
}

// ================================================================
// POSE PAINTER (OPTIMIZED + ISOLATED REPAINT)
// ================================================================

class PosePainter extends CustomPainter {
  final ValueNotifier<List<LiveLandmark>> landmarksNotifier;
  final ValueNotifier<String> formNotifier;
  final bool isFrontCamera;

  PosePainter({
    required this.landmarksNotifier,
    required this.formNotifier,
    this.isFrontCamera = true,
  }) : super(repaint: Listenable.merge([landmarksNotifier, formNotifier]));

  static const List<List<int>> connections = [
    // Face
    [0, 1],
    [1, 2],
    [2, 3],
    [3, 7],
    [0, 4],
    [4, 5],
    [5, 6],
    [6, 8],

    // Torso
    [11, 12],
    [11, 23],
    [12, 24],
    [23, 24],

    // Left arm
    [11, 13],
    [13, 15],

    // Right arm
    [12, 14],
    [14, 16],

    // Left hand
    [15, 17],
    [15, 19],
    [15, 21],

    // Right hand
    [16, 18],
    [16, 20],
    [16, 22],

    // Left leg
    [23, 25],
    [25, 27],
    [27, 29],
    [29, 31],

    // Right leg
    [24, 26],
    [26, 28],
    [28, 30],
    [30, 32],
  ];

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final landmarks = landmarksNotifier.value;
    final form = formNotifier.value;

    if (landmarks.length != 33) {
      return;
    }

    final bool incorrect =
        form.toLowerCase().contains('incorrect');

    final bool active =
        form.toLowerCase().contains('correct') ||
        form.toLowerCase().contains('incorrect') ||
        form.toLowerCase().contains('raising') ||
        form.toLowerCase().contains('top') ||
        form.toLowerCase().contains('lowering');

    final Paint linePaint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = incorrect
          ? Colors.redAccent
          : active
              ? Colors.greenAccent
              : const Color(0xFF38BDF8);

    final Paint pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = incorrect
          ? Colors.redAccent
          : active
              ? Colors.greenAccent
              : const Color(0xFF38BDF8);

    // Precompute all 33 screen offsets once to avoid over 100 allocations per frame
    final points = List<Offset>.filled(33, Offset.zero);
    final double w = size.width;
    final double h = size.height;

    for (int i = 0; i < 33; i++) {
      final lm = landmarks[i];
      // The image sent to MediaPipe is rotated into upright portrait in isolate.
      // For front camera, Flutter's CameraPreview mirrors horizontally, so mirror X.
      // For back camera, preview is not mirrored.
      final double x = isFrontCamera
          ? (1.0 - lm.x).clamp(0.0, 1.0)
          : lm.x.clamp(0.0, 1.0);
      final double y = lm.y.clamp(0.0, 1.0);
      points[i] = Offset(x * w, y * h);
    }

    for (final connection in connections) {
      final int first = connection[0];
      final int second = connection[1];

      if (landmarks[first].visibility < 0.25 ||
          landmarks[second].visibility < 0.25) {
        continue;
      }

      canvas.drawLine(
        points[first],
        points[second],
        linePaint,
      );
    }

    for (int i = 0; i < 33; i++) {
      if (landmarks[i].visibility < 0.25) {
        continue;
      }

      canvas.drawCircle(
        points[i],
        4,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) => false;
}

// ================================================================
// ERROR FRAME VIEWER DIALOG (MAXIMIZE / MINIMIZE / ZOOM)
// ================================================================

class _ErrorFrameViewerDialog extends StatefulWidget {
  final String url;

  const _ErrorFrameViewerDialog({required this.url});

  @override
  State<_ErrorFrameViewerDialog> createState() =>
      _ErrorFrameViewerDialogState();
}

class _ErrorFrameViewerDialogState extends State<_ErrorFrameViewerDialog> {
  bool _isFullscreen = false;
  final TransformationController _transformationController =
      TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    if (_isFullscreen) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              // Zoomable Image
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: Center(
                    child: Image.network(
                      widget.url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Text(
                            'Error frame unavailable.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Fullscreen Top Bar Controls
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'WHERE THE FORM WENT WRONG',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reset Zoom',
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: _resetZoom,
                      ),
                      IconButton(
                        tooltip: 'Minimize',
                        icon: const Icon(
                          Icons.fullscreen_exit_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () {
                          setState(() {
                            _isFullscreen = false;
                          });
                        },
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom hint
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Pinch or drag to zoom and inspect form error',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal dialog mode
    return Dialog(
      backgroundColor: Colors.grey.shade900,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: screenSize.height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'WHERE THE FORM WENT WRONG',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Maximize to Fullscreen',
                    icon: const Icon(
                      Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _isFullscreen = true;
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 22,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),

            // Zoomable Image
            Flexible(
              child: Container(
                color: Colors.black,
                constraints: BoxConstraints(
                  minHeight: 220,
                  maxHeight: screenSize.height * 0.55,
                ),
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.network(
                      widget.url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Error frame unavailable.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            const Divider(height: 1, color: Colors.white12),

            // Footer actions / tips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.pinch_outlined,
                    color: Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Pinch to zoom • Tap maximize for fullscreen',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _resetZoom,
                    child: const Text('Reset Zoom',
                        style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
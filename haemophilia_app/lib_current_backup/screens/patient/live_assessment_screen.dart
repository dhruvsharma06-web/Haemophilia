import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/assessment_history_service.dart';

class LiveAssessmentScreen extends StatefulWidget {
  final String exerciseName;

  // Optional ordered assignment supplied by the patient assignment flow.
  // When this is null, the screen behaves exactly like the original
  // single-exercise assessment screen.
  final List<Map<String, dynamic>>? assignedExercises;

  const LiveAssessmentScreen({
    super.key,
    required this.exerciseName,
    this.assignedExercises,
  });

  @override
  State<LiveAssessmentScreen> createState() =>
      _LiveAssessmentScreenState();
}

class _LiveAssessmentScreenState
    extends State<LiveAssessmentScreen> {
  // ============================================================
  // CONFIGURATION
  // ============================================================

  static const String websocketUrl =
      'ws://192.168.1.43:8000/v1/assessments/live';

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
  // FRAME CONTROL
  // ============================================================

  DateTime _lastFrameSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _processingFrame = false;

  // ============================================================
  // LIVE AI STATE
  // ============================================================

  int _repCount = 0;

  String _form = 'Waiting';
  String _errorType = '';
  String _feedback = 'Position yourself in front of the camera.';

  double _score = 0;
  double _rom = 0;
  double _smoothness = 0;

  String _speed = 'Waiting';

  List<LiveLandmark> _landmarks = [];

  // Smooth visual interpolation between AI landmark updates.
  List<LiveLandmark> _targetLandmarks = [];
  Timer? _landmarkTimer;

  // Last completed rep returned by the backend.
  Map<String, dynamic>? _lastCompletedRep;

  final AssessmentHistoryService _historyService =
      AssessmentHistoryService();
  String? _lastSavedRepSignature;
  int _sessionRepSequence = 0;

  // Every time the patient opens an assessment screen, a new session begins.
  // Individual completed reps are stored under this session id in Firestore.
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  // ============================================================
  // ASSIGNED ASSESSMENT
  // ============================================================

  bool _assignedMode = false;
  bool _switchingExercise = false;

  int _currentAssignedIndex = 0;
  int _currentCorrectReps = 0;
  int _currentTotalReps = 0;

  List<Map<String, dynamic>> _assignedExercises = [];

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();

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

      _currentAssignedIndex = 0;
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
    switch (exercise) {
      case 'assisted_shoulder_flexion':
        return 'Assisted Shoulder Flexion';

      case 'elbow_flexion':
        return 'Elbow Flexion & Extension';

      case 'shoulder_rotation':
        return 'Shoulder Rotation';

      default:
        return exercise;
    }
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

      if (completedRep is Map) {
        debugPrint(
          'Completed rep: ${jsonEncode(completedRep)}',
        );
      }

      // Assignment progress is based ONLY on completed correct repetitions.
      // Incorrect repetitions are still saved in history, but they do not
      // advance the doctor's prescribed target.
      if (completedRep is Map &&
          _assignedMode &&
          !_switchingExercise) {
        final form =
            completedRep['form']
                    ?.toString()
                    .toLowerCase() ??
                completedRep['label']
                    ?.toString()
                    .toLowerCase() ??
                '';

        final bool correct =
            form == 'correct' ||
            form.contains('correct') &&
            !form.contains('incorrect');

        _currentTotalReps++;

        if (correct) {
          _currentCorrectReps++;
        }

        final target = _currentAssignedTarget();

        debugPrint(
          'Assignment progress: '
          '$_currentCorrectReps/$target correct '
          '(total=$_currentTotalReps)',
        );

        if (target > 0 &&
            _currentCorrectReps >= target) {
          unawaited(
            _switchToNextAssignedExercise(),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _socketConnected = true;
        _connectionStatus = 'AI Live';

        _repCount =
            _toInt(data['rep_count'], defaultValue: _repCount);

        _form =
            data['form']?.toString() ?? _form;

        _errorType =
            data['error_type']?.toString() ?? '';

        _feedback =
            data['feedback']?.toString() ??
                'Keep following the exercise instructions.';

        _score =
            _toDouble(data['score']);

        _rom =
            _toDouble(data['range_of_motion']);

        _speed =
            data['speed']?.toString() ?? 'Waiting';

        _smoothness =
            _toDouble(data['smoothness']);

        if (completedRep is Map) {
          _lastCompletedRep =
              Map<String, dynamic>.from(completedRep);

          final rep = Map<String, dynamic>.from(completedRep);
          // The backend may return rep_number=0 (or omit it). For the patient
          // history, repetitions should always be displayed as 1, 2, 3...
          // within the current session. Preserve a valid positive backend
          // number when one is supplied.
          final backendRepNumber = _toInt(rep['rep_number']);
          final normalizedRepNumber =
              backendRepNumber > 0 ? backendRepNumber : ++_sessionRepSequence;
          if (backendRepNumber > 0 && backendRepNumber > _sessionRepSequence) {
            _sessionRepSequence = backendRepNumber;
          }
          rep['rep_number'] = normalizedRepNumber;

          // Save every completed repetition once. The JSON signature prevents
          // duplicate writes if the same completed_rep message is received twice.
          final repSignature = jsonEncode(rep);
          if (repSignature != _lastSavedRepSignature) {
            _lastSavedRepSignature = repSignature;
            unawaited(_saveCompletedRepToHistory(rep));
          }
        }

      });

      _updateLandmarksSmooth(newLandmarks);
    } catch (e) {
      debugPrint(
        'Could not process WebSocket message: $e',
      );
    }
  }

  Future<void> _switchToNextAssignedExercise() async {
    if (!_assignedMode || _switchingExercise) {
      return;
    }

    _switchingExercise = true;

    final bool hasNext =
        _currentAssignedIndex + 1 <
        _assignedExercises.length;

    // All assigned exercises have reached their correct-rep targets.
    if (!hasNext) {
      _switchingExercise = false;

      if (mounted) {
        setState(() {
          _feedback = 'Assessment complete.';
        });
      }

      // The current implementation keeps the same camera/WebSocket session
      // open until the patient explicitly ends it. This prevents the camera
      // and working pose overlay from being disturbed.
      return;
    }

    final nextIndex = _currentAssignedIndex + 1;

    final nextExercise =
        _assignedExercises[nextIndex]['exercise']
            ?.toString();

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

  void _updateLandmarksSmooth(
    List<LiveLandmark> next,
  ) {
    if (next.length != 33) {
      return;
    }

    _targetLandmarks = next;

    if (_landmarks.length != 33) {
      if (!mounted) return;
      setState(() {
        _landmarks = next;
      });
      return;
    }

    _landmarkTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (!mounted || _targetLandmarks.length != 33) {
          _landmarkTimer?.cancel();
          _landmarkTimer = null;
          return;
        }

        final current = _landmarks;

        if (current.length != 33) {
          setState(() {
            _landmarks = _targetLandmarks;
          });
          return;
        }

        const double alpha = 0.42;
        bool closeEnough = true;

        final smoothed = <LiveLandmark>[];

        for (int i = 0; i < 33; i++) {
          final a = current[i];
          final b = _targetLandmarks[i];

          final x = a.x + (b.x - a.x) * alpha;
          final y = a.y + (b.y - a.y) * alpha;
          final z = a.z + (b.z - a.z) * alpha;
          final visibility =
              a.visibility +
              (b.visibility - a.visibility) * alpha;

          if ((b.x - x).abs() > 0.001 ||
              (b.y - y).abs() > 0.001) {
            closeEnough = false;
          }

          smoothed.add(
            LiveLandmark(
              x: x,
              y: y,
              z: z,
              visibility: visibility,
            ),
          );
        }

        setState(() {
          _landmarks = smoothed;
        });

        if (closeEnough) {
          _landmarks = _targetLandmarks;
          _landmarkTimer?.cancel();
          _landmarkTimer = null;
        }
      },
    );
  }

  Future<void> _showErrorFrame(
    String url,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'WHERE THE FORM WENT WRONG',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text(
                        'Error frame unavailable.',
                        style: TextStyle(
                          color: Colors.white70,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
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
    if (!_socketConnected) {
      return;
    }

    if (_processingFrame) {
      return;
    }

    final now = DateTime.now();

    if (now.difference(_lastFrameSent) < frameInterval) {
      return;
    }

    _lastFrameSent = now;
    _processingFrame = true;

    try {
      final jpegBytes =
          await _convertCameraImageToJpeg(cameraImage);

      if (jpegBytes == null || jpegBytes.isEmpty) {
        return;
      }

      if (!_socketConnected || _channel == null) {
        return;
      }

      _channel!.sink.add(jpegBytes);

      debugPrint(
        'Sent AI frame: ${jpegBytes.length} bytes',
      );
    } catch (e) {
      debugPrint(
        'Frame processing error: $e',
      );
    } finally {
      _processingFrame = false;
    }
  }

  // ============================================================
  // YUV420 -> JPEG
  // ============================================================

  Future<Uint8List?> _convertCameraImageToJpeg(
    CameraImage image,
  ) async {
    if (image.format.group != ImageFormatGroup.yuv420) {
      debugPrint(
        'Unsupported camera format: ${image.format.group}',
      );
      return null;
    }

    final int width = image.width;
    final int height = image.height;

    final img.Image rgbImage = img.Image(
      width: width,
      height: height,
    );

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final Uint8List yBytes = yPlane.bytes;
    final Uint8List uBytes = uPlane.bytes;
    final Uint8List vBytes = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int uRowStride = uPlane.bytesPerRow;
    final int vRowStride = vPlane.bytesPerRow;

    final int uPixelStride =
        uPlane.bytesPerPixel ?? 1;

    final int vPixelStride =
        vPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final int yRowStart = y * yRowStride;

      final int uvRow =
          (y ~/ 2);

      final int uRowStart =
          uvRow * uRowStride;

      final int vRowStart =
          uvRow * vRowStride;

      for (int x = 0; x < width; x++) {
        final int yIndex =
            yRowStart + x;

        final int uvColumn =
            x ~/ 2;

        final int uIndex =
            uRowStart +
            uvColumn * uPixelStride;

        final int vIndex =
            vRowStart +
            uvColumn * vPixelStride;

        final int yValue =
            yBytes[yIndex];

        final int uValue =
            uBytes[uIndex];

        final int vValue =
            vBytes[vIndex];

        final double r =
            yValue +
            1.402 * (vValue - 128);

        final double g =
            yValue -
            0.344136 * (uValue - 128) -
            0.714136 * (vValue - 128);

        final double b =
            yValue +
            1.772 * (uValue - 128);

        final int red =
            r.round().clamp(0, 255);

        final int green =
            g.round().clamp(0, 255);

        final int blue =
            b.round().clamp(0, 255);

        rgbImage.setPixelRgb(
          x,
          y,
          red,
          green,
          blue,
        );
      }
    }

    // The Android camera stream is generally delivered according
    // to the sensor orientation rather than the displayed portrait
    // orientation. Rotate the image so MediaPipe receives an upright
    // person.
    img.Image processedImage = rgbImage;

    final int sensorOrientation =
        _controller?.description.sensorOrientation ?? 0;

    if (sensorOrientation == 90) {
      processedImage = img.copyRotate(
        rgbImage,
        angle: 90,
      );
    } else if (sensorOrientation == 270) {
      processedImage = img.copyRotate(
        rgbImage,
        angle: 270,
      );
    } else if (sensorOrientation == 180) {
      processedImage = img.copyRotate(
        rgbImage,
        angle: 180,
      );
    }

    final Uint8List jpeg =
        Uint8List.fromList(
      img.encodeJpg(
        processedImage,
        quality: 75,
      ),
    );

    return jpeg;
  }

  // ============================================================
  // END ASSESSMENT
  // ============================================================

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

  String? _errorFrameUrl(Map<String, dynamic> rep) {
    final raw = rep['error_frame_path']?.toString();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    final normalized = raw.replaceAll(r'\', '/');
    final filename = normalized.split('/').last;

    if (filename.isEmpty) {
      return null;
    }

    return 'http://192.168.1.43:8000/v1/assets/error-frames/'
        '${Uri.encodeComponent(filename)}';
  }

  double _completedDouble(
    Map<String, dynamic> rep,
    String key, {
    double fallback = 0,
  }) {
    return _toDouble(rep[key], defaultValue: fallback);
  }

  Widget _completedMetric(
    String title,
    String value,
  ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
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
    final leftMax = _completedDouble(rep, 'left_max_angle');
    final rightMax = _completedDouble(rep, 'right_max_angle');
    final duration = _completedDouble(rep, 'duration');
    final speed = rep['speed']?.toString() ?? 'Unknown';
    final confidence = _completedDouble(
      rep,
      'confidence',
      fallback: _completedDouble(rep, 'lstm_confidence'),
    );

    return Card(
      color: Colors.black.withValues(alpha: 0.92),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
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
                  size: 21,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'REP ${rep['rep_number'] ?? _repCount} — '
                    '${form.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (incorrect && error.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _errorLabel(error),
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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
                      fontSize: 10.5,
                    ),
                  ),
                ),
                if (incorrect &&
                    _errorFrameUrl(rep) != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      final url = _errorFrameUrl(rep);
                      if (url != null) {
                        _showErrorFrame(url);
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        _errorFrameUrl(rep)!,
                        width: 72,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (
                          context,
                          error,
                          stackTrace,
                        ) {
                          return Container(
                            width: 72,
                            height: 48,
                            color: Colors.white10,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white38,
                              size: 18,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 7),

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
              ],
            ),

            const SizedBox(height: 5),

            Row(
              children: [
                _completedMetric(
                  'LEFT MAX',
                  '${leftMax.toStringAsFixed(0)}°',
                ),
                _completedMetric(
                  'RIGHT MAX',
                  '${rightMax.toStringAsFixed(0)}°',
                ),
                _completedMetric(
                  'DURATION',
                  '${duration.toStringAsFixed(2)}s',
                ),
              ],
            ),

            const SizedBox(height: 5),

            Row(
              children: [
                _completedMetric(
                  'LSTM',
                  '${confidence.toStringAsFixed(1)}%',
                ),
                _completedMetric(
                  'SMOOTH',
                  '${(_completedDouble(rep, 'smoothness_raw').clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                ),
                const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_currentExerciseDisplayName()),
      ),
      body: _buildBody(),
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

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),

        // Skeleton overlay.
        if (_landmarks.length == 33)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: PosePainter(
                  landmarks: _landmarks,
                  form: _form,
                ),
              ),
            ),
          ),

        // Top information panel.
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _buildTopPanel(),
        ),

        // Completed-rep result panel.
        if (_lastCompletedRep != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 86,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 215,
              ),
              child: _buildCompletedRepPanel(),
            ),
          )
        else
          Positioned(
            left: 12,
            right: 12,
            bottom: 86,
            child: _buildFeedbackPanel(),
          ),

        // End assessment button.
        Positioned(
          left: 24,
          right: 24,
          bottom: 20,
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _endAssessment,
              icon: const Icon(Icons.stop),
              label: const Text(
                'End Assessment',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
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

    Color statusColor;

    if (aiLive) {
      statusColor = Colors.greenAccent;
    } else if (_socketConnecting) {
      statusColor = Colors.orangeAccent;
    } else {
      statusColor = Colors.redAccent;
    }

    return Card(
      color: Colors.black.withValues(alpha: 0.78),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _connectionStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  'REP $_repCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),

            if (_assignedMode) ...[
              const SizedBox(height: 8),
              Text(
                'EXERCISE ${_currentAssignedIndex + 1} OF '
                '${_assignedExercises.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_currentCorrectReps}/${_currentAssignedTarget()} '
                'correct reps',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _stat(
                    'FORM',
                    _form,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'SCORE',
                    '${_score.toStringAsFixed(0)}',
                  ),
                ),
                Expanded(
                  child: _stat(
                    'ROM',
                    '${_rom.toStringAsFixed(1)}°',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _stat(
                    'SPEED',
                    _speed,
                  ),
                ),
                Expanded(
                  child: _stat(
                    'SMOOTH',
                    '${(_smoothness.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                  ),
                ),
              ],
            ),

            if (_connectionError != null) ...[
              const SizedBox(height: 8),
              Text(
                _connectionError!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackPanel() {
    final bool incorrect =
        _form.toLowerCase().contains('incorrect');

    return Card(
      color: Colors.black.withValues(alpha: 0.82),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              incorrect
                  ? Icons.warning_amber_rounded
                  : Icons.accessibility_new,
              color: incorrect
                  ? Colors.redAccent
                  : Colors.greenAccent,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  if (_errorType.isNotEmpty)
                    Text(
                      _errorLabel(_errorType),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    _feedback,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    _landmarkTimer?.cancel();
    _landmarkTimer = null;

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
// POSE PAINTER
// ================================================================

class PosePainter extends CustomPainter {
  final List<LiveLandmark> landmarks;
  final String form;

  PosePainter({
    required this.landmarks,
    required this.form,
  });

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
              : Colors.blueAccent;

    final Paint pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = incorrect
          ? Colors.redAccent
          : active
              ? Colors.greenAccent
              : Colors.blueAccent;

    Offset point(int index) {
  final landmark = landmarks[index];

  // Camera buffer is landscape while the preview is portrait.
  // Rotate the MediaPipe coordinates 90 degrees clockwise
  // to match the portrait CameraPreview.
  final double x =
      (1.0 - landmark.y).clamp(0.0, 1.0);

  final double y =
      landmark.x.clamp(0.0, 1.0);

  return Offset(
    x * size.width,
    y * size.height,
  );
}

    for (final connection in connections) {
      final int first = connection[0];
      final int second = connection[1];

      if (landmarks[first].visibility < 0.25 ||
          landmarks[second].visibility < 0.25) {
        continue;
      }

      canvas.drawLine(
        point(first),
        point(second),
        linePaint,
      );
    }

    for (int i = 0; i < landmarks.length; i++) {
      if (landmarks[i].visibility < 0.25) {
        continue;
      }

      final Offset p = point(i);

      canvas.drawCircle(
        p,
        4,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant PosePainter oldDelegate,
  ) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.form != form;
  }
}
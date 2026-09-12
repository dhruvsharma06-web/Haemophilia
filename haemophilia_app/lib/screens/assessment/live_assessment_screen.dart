import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LiveAssessmentScreen extends StatefulWidget {
  final String exerciseName;

  const LiveAssessmentScreen({
    super.key,
    required this.exerciseName,
  });

  @override
  State<LiveAssessmentScreen> createState() =>
      _LiveAssessmentScreenState();
}

class _LiveAssessmentScreenState
    extends State<LiveAssessmentScreen> {
  // ============================================================
  // BACKEND CONFIGURATION
  // ============================================================

  // Your laptop IPv4 address.
  static const String backendHost = '192.168.1.43';

  static const int backendPort = 8000;

  static const String websocketUrl =
      'ws://192.168.1.43:8000/v1/assessments/live';

  // ============================================================
  // CAMERA
  // ============================================================

  CameraController? _cameraController;

  bool _cameraReady = false;
  bool _startingCamera = true;

  // Prevent sending too many frames at once.
  bool _sendingFrame = false;

  DateTime _lastFrameSent =
      DateTime.fromMillisecondsSinceEpoch(0);

  // Approximately 8 FPS.
  static const Duration frameInterval =
      Duration(milliseconds: 120);

  // ============================================================
  // WEBSOCKET
  // ============================================================

  WebSocketChannel? _channel;

  StreamSubscription? _socketSubscription;

  bool _socketConnected = false;
  bool _connectingSocket = false;

  String? _connectionError;

  // ============================================================
  // LIVE AI DATA
  // ============================================================

  int _repCount = 0;

  String _form = 'waiting';

  String _state = 'DOWN';

  String _feedback =
      'Get ready — raise your arm.';

  String? _errorType;

  double _score = 0.0;

  double _rom = 0.0;

  double _smoothness = 0.0;

  String _speed = 'Waiting';

  List<LiveLandmark> _landmarks = [];

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeCamera();
    await _connectWebSocket();
  }

  // ============================================================
  // CAMERA
  // ============================================================

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception(
          'No camera was found on this device.',
        );
      }

      CameraDescription selectedCamera =
          cameras.first;

      // Prefer front camera.
      for (final camera in cameras) {
        if (camera.lensDirection ==
            CameraLensDirection.front) {
          selectedCamera = camera;
          break;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup:
            ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;

      setState(() {
        _cameraReady = true;
        _startingCamera = false;
      });

      await controller.startImageStream(
        _onCameraImage,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _startingCamera = false;
        _cameraReady = false;
        _connectionError =
            'Camera error: $e';
      });
    }
  }

  // ============================================================
  // CAMERA FRAME
  // ============================================================

  Future<void> _onCameraImage(
    CameraImage image,
  ) async {
    if (!_cameraReady) {
      return;
    }

    if (!_socketConnected) {
      return;
    }

    if (_sendingFrame) {
      return;
    }

    final now = DateTime.now();

    if (now.difference(_lastFrameSent) <
        frameInterval) {
      return;
    }

    _lastFrameSent = now;

    _sendingFrame = true;

    try {
      final jpegBytes =
          _convertCameraImageToJpeg(image);

      if (jpegBytes == null) {
        return;
      }

      _channel?.sink.add(
        jpegBytes,
      );
    } catch (e) {
      debugPrint(
        'Frame send error: $e',
      );
    } finally {
      _sendingFrame = false;
    }
  }

  // ============================================================
  // YUV420 -> JPEG
  // ============================================================

  Uint8List? _convertCameraImageToJpeg(
    CameraImage image,
  ) {
    try {
      if (image.format.group !=
          ImageFormatGroup.yuv420) {
        debugPrint(
          'Unsupported camera format: '
          '${image.format.group}',
        );

        return null;
      }

      final int width = image.width;
      final int height = image.height;

      final Plane yPlane =
          image.planes[0];

      final Plane uPlane =
          image.planes[1];

      final Plane vPlane =
          image.planes[2];

      final Uint8List yBytes =
          yPlane.bytes;

      final Uint8List uBytes =
          uPlane.bytes;

      final Uint8List vBytes =
          vPlane.bytes;

      final int yRowStride =
          yPlane.bytesPerRow;

      final int uRowStride =
          uPlane.bytesPerRow;

      final int vRowStride =
          vPlane.bytesPerRow;

      final int uPixelStride =
          uPlane.bytesPerPixel ?? 1;

      final int vPixelStride =
          vPlane.bytesPerPixel ?? 1;

      final Uint8List rgb =
          Uint8List(
        width * height * 3,
      );

      int outputIndex = 0;

      for (int y = 0;
          y < height;
          y++) {
        final int yRowStart =
            y * yRowStride;

        final int uvY =
            y ~/ 2;

        final int uRowStart =
            uvY * uRowStride;

        final int vRowStart =
            uvY * vRowStride;

        for (int x = 0;
            x < width;
            x++) {
          final int yIndex =
              yRowStart + x;

          final int uvX =
              x ~/ 2;

          final int uIndex =
              uRowStart +
              uvX * uPixelStride;

          final int vIndex =
              vRowStart +
              uvX * vPixelStride;

          final double yValue =
              yBytes[yIndex].toDouble();

          final double uValue =
              uBytes[uIndex].toDouble()
              - 128.0;

          final double vValue =
              vBytes[vIndex].toDouble()
              - 128.0;

          int r =
              (yValue +
                      1.402 * vValue)
                  .round();

          int g =
              (yValue -
                      0.344136 * uValue -
                      0.714136 * vValue)
                  .round();

          int b =
              (yValue +
                      1.772 * uValue)
                  .round();

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          rgb[outputIndex++] = r;
          rgb[outputIndex++] = g;
          rgb[outputIndex++] = b;
        }
      }

      final img.Image rgbImage =
          img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgb.buffer,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );

      // Rotate the sensor image so that MediaPipe receives
      // an upright portrait image.
      final img.Image rotatedImage =
          img.copyRotate(
        rgbImage,
        angle: 90,
      );

      final Uint8List jpeg =
          Uint8List.fromList(
        img.encodeJpg(
          rotatedImage,
          quality: 70,
        ),
      );

      return jpeg;
    } catch (e) {
      debugPrint(
        'JPEG conversion error: $e',
      );

      return null;
    }
  }

  // ============================================================
  // WEBSOCKET CONNECTION
  // ============================================================

  Future<void> _connectWebSocket() async {
    if (_connectingSocket ||
        _socketConnected) {
      return;
    }

    _connectingSocket = true;

    if (mounted) {
      setState(() {
        _connectionError = null;
      });
    }

    try {
      final Uri uri =
          Uri.parse(websocketUrl);

      final IOWebSocketChannel channel =
          IOWebSocketChannel.connect(
        uri,
        pingInterval:
            const Duration(seconds: 20),
      );

      _channel = channel;

      await channel.ready;

      if (!mounted) {
        return;
      }

      setState(() {
        _socketConnected = true;
        _connectingSocket = false;
      });

      _socketSubscription =
          channel.stream.listen(
        _handleSocketMessage,
        onError: _handleSocketError,
        onDone: _handleSocketClosed,
        cancelOnError: false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _socketConnected = false;
        _connectingSocket = false;
        _connectionError =
            'Could not connect to AI server.\n\n'
            'Server: $websocketUrl\n\n'
            '$e';
      });
    }
  }

  // ============================================================
  // WEBSOCKET MESSAGE
  // ============================================================

  void _handleSocketMessage(
    dynamic message,
  ) {
    try {
      if (message is! String) {
        return;
      }

      final dynamic decoded =
          jsonDecode(message);

      if (decoded is! Map) {
        return;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(
        decoded,
      );

      // Backend error.
      if (data['type'] == 'error') {
        if (!mounted) {
          return;
        }

        setState(() {
          _connectionError =
              data['message']
                      ?.toString() ??
                  'AI server error.';
        });

        return;
      }

      if (data['type'] !=
          'live_state') {
        return;
      }

      // --------------------------------------------------------
      // LANDMARKS
      // --------------------------------------------------------

      final List<LiveLandmark>
          landmarks = [];

      final dynamic rawLandmarks =
          data['landmarks'];

      if (rawLandmarks is List) {
        for (final dynamic item
            in rawLandmarks) {
          if (item is Map) {
            landmarks.add(
              LiveLandmark.fromJson(
                Map<String, dynamic>.from(
                  item,
                ),
              ),
            );
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _repCount =
            _toInt(
          data['rep_count'],
        );

        _form =
            data['form']
                    ?.toString()
                    .toLowerCase() ??
                'waiting';

        _state =
            data['state']
                    ?.toString() ??
                'DOWN';

        _feedback =
            data['feedback']
                    ?.toString() ??
                'Get ready — raise your arm.';

        _errorType =
            data['error_type']
                ?.toString();

        _score =
            _toDouble(
          data['score'],
        );

        _rom =
            _toDouble(
          data['range_of_motion'],
        );

        _speed =
            data['speed']
                    ?.toString() ??
                'Waiting';

        _smoothness =
            _toDouble(
          data['smoothness'],
        );

        _landmarks =
            landmarks;

        _connectionError = null;
      });
    } catch (e) {
      debugPrint(
        'Socket message parsing error: $e',
      );
    }
  }

  void _handleSocketError(
    Object error,
  ) {
    debugPrint(
      'WebSocket error: $error',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _socketConnected = false;

      _connectionError =
          'AI connection error:\n$error';
    });
  }

  void _handleSocketClosed() {
    debugPrint(
      'AI WebSocket closed.',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _socketConnected = false;
    });
  }

  // ============================================================
  // DATA HELPERS
  // ============================================================

  int _toInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  double _toDouble(
    dynamic value,
  ) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0.0;
  }

  // ============================================================
  // MAIN UI
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF07111F),
      body: SafeArea(
        child: Stack(
          children: [
            _buildCamera(),

            _buildTopBar(),

            _buildStatus(),

            _buildMetrics(),

            _buildFeedback(),

            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CAMERA UI
  // ============================================================

  Widget _buildCamera() {
    if (_startingCamera) {
      return const Positioned.fill(
        child: Center(
          child:
              CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    if (!_cameraReady ||
        _cameraController == null) {
      return Positioned.fill(
        child: Center(
          child: Padding(
            padding:
                const EdgeInsets.all(24),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_off_rounded,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(
                  height: 16,
                ),
                const Text(
                  'Camera unavailable',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  _connectionError ??
                      'Unable to start camera.',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller =
        _cameraController!;

    final Size? previewSize =
        controller.value.previewSize;

    if (previewSize == null) {
      return const Positioned.fill(
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final double width =
              constraints.maxWidth;

          final double height =
              constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(
                controller,
              ),

              if (_landmarks.length ==
                  33)
                Positioned.fill(
                  child: CustomPaint(
                    painter:
                        SkeletonPainter(
                      landmarks:
                          _landmarks,
                      form: _form,
                    ),
                  ),
                ),

              // Dark gradient over the camera
              // to make UI readable.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration:
                        BoxDecoration(
                      gradient:
                          LinearGradient(
                        begin:
                            Alignment.topCenter,
                        end:
                            Alignment.bottomCenter,
                        colors: [
                          Colors.black
                              .withValues(
                            alpha: 0.45,
                          ),
                          Colors.transparent,
                          Colors.black
                              .withValues(
                            alpha: 0.50,
                          ),
                        ],
                        stops: const [
                          0.0,
                          0.45,
                          1.0,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          8,
          8,
          12,
          12,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed:
                  _endAssessment,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
              ),
            ),

            const SizedBox(
              width: 4,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LIVE ASSESSMENT',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight:
                          FontWeight.w700,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    widget.exerciseName,
                    style:
                        const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            _buildConnectionStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final bool connected =
        _socketConnected;

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration:
          BoxDecoration(
        color: Colors.black
            .withValues(
          alpha: 0.55,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(
              shape:
                  BoxShape.circle,
              color: connected
                  ? Colors.greenAccent
                  : Colors.orangeAccent,
            ),
          ),
          const SizedBox(
            width: 6,
          ),
          Text(
            connected
                ? 'AI LIVE'
                : 'CONNECTING',
            style:
                const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS
  // ============================================================

  Widget _buildStatus() {
    final bool incorrect =
        _form == 'incorrect';

    final bool correct =
        _form == 'correct';

    final Color statusColor;

    if (incorrect) {
      statusColor =
          Colors.redAccent;
    } else if (correct) {
      statusColor =
          Colors.greenAccent;
    } else {
      statusColor =
          Colors.lightBlueAccent;
    }

    final String title;

    if (incorrect) {
      title = 'INCORRECT';
    } else if (correct) {
      title = 'GOOD FORM';
    } else {
      title = 'READY';
    }

    return Positioned(
      top: 88,
      left: 16,
      right: 16,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.all(
                14,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.black
                    .withValues(
                  alpha: 0.60,
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
                border: Border.all(
                  color:
                      statusColor.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      color:
                          statusColor,
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        title,
                        style:
                            TextStyle(
                          color:
                              statusColor,
                          fontSize: 15,
                          fontWeight:
                              FontWeight
                                  .w800,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        _state,
                        style:
                            const TextStyle(
                          color:
                              Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Container(
            width: 80,
            padding:
                const EdgeInsets.symmetric(
              vertical: 10,
            ),
            decoration:
                BoxDecoration(
              color: Colors.black
                  .withValues(
                alpha: 0.65,
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '$_repCount',
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const Text(
                  'REPS',
                  style:
                      TextStyle(
                    color:
                        Colors.white54,
                    fontSize: 9,
                    fontWeight:
                        FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // METRICS
  // ============================================================

  Widget _buildMetrics() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 154,
      child: Row(
        children: [
          Expanded(
            child: _metric(
              'SCORE',
              _score.toStringAsFixed(0),
              Icons.star_rounded,
            ),
          ),

          const SizedBox(
            width: 7,
          ),

          Expanded(
            child: _metric(
              'ROM',
              '${_rom.toStringAsFixed(0)}°',
              Icons.swap_vert_rounded,
            ),
          ),

          const SizedBox(
            width: 7,
          ),

          Expanded(
            child: _metric(
              'SPEED',
              _speed,
              Icons.speed_rounded,
            ),
          ),

          const SizedBox(
            width: 7,
          ),

          Expanded(
            child: _metric(
              'SMOOTH',
              '${_smoothness.toStringAsFixed(0)}%',
              Icons.timeline_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 9,
        horizontal: 4,
      ),
      decoration:
          BoxDecoration(
        color: Colors.black
            .withValues(
          alpha: 0.70,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: Colors.white70,
            size: 17,
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            value,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            label,
            style:
                const TextStyle(
              color: Colors.white54,
              fontSize: 7,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FEEDBACK
  // ============================================================

  Widget _buildFeedback() {
    final bool hasError =
        _form == 'incorrect' ||
        _errorType != null;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 88,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        decoration:
            BoxDecoration(
          color: hasError
              ? Colors.red.shade900
                  .withValues(
                  alpha: 0.90,
                )
              : Colors.black
                  .withValues(
                  alpha: 0.72,
                ),
          borderRadius:
              BorderRadius.circular(
            14,
          ),
          border: hasError
              ? Border.all(
                  color:
                      Colors.redAccent,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              hasError
                  ? Icons.warning_rounded
                  : Icons.auto_awesome,
              color: hasError
                  ? Colors.redAccent
                  : Colors.lightBlueAccent,
              size: 19,
            ),
            const SizedBox(
              width: 9,
            ),
            Expanded(
              child: Text(
                _feedback,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // END BUTTON
  // ============================================================

  Widget _buildBottomButton() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SizedBox(
        height: 54,
        child: FilledButton.icon(
          onPressed:
              _endAssessment,
          style:
              FilledButton.styleFrom(
            backgroundColor:
                Colors.red.shade700,
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),
          ),
          icon: const Icon(
            Icons.stop_rounded,
          ),
          label: const Text(
            'END ASSESSMENT',
            style: TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> _endAssessment() async {
    await _cleanup();

    if (!mounted) {
      return;
    }

    Navigator.pop(context);
  }

  Future<void> _cleanup() async {
    try {
      await _socketSubscription?.cancel();
    } catch (_) {}

    _socketSubscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;

    try {
      if (_cameraController != null &&
          _cameraController!
              .value
              .isStreamingImages) {
        await _cameraController!
            .stopImageStream();
      }
    } catch (_) {}

    try {
      await _cameraController?.dispose();
    } catch (_) {}

    _cameraController = null;
  }

  @override
  void dispose() {
    _cleanup();

    SystemChrome.setPreferredOrientations(
      DeviceOrientation.values,
    );

    super.dispose();
  }
}


// ================================================================
// LIVE LANDMARK
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

  factory LiveLandmark.fromJson(
    Map<String, dynamic> json,
  ) {
    return LiveLandmark(
      x: _number(json['x']),
      y: _number(json['y']),
      z: _number(json['z']),
      visibility:
          _number(json['visibility']),
    );
  }

  static double _number(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0.0;
  }
}


// ================================================================
// SKELETON PAINTER
// ================================================================

class SkeletonPainter
    extends CustomPainter {
  final List<LiveLandmark> landmarks;
  final String form;

  SkeletonPainter({
    required this.landmarks,
    required this.form,
  });

  static const List<List<int>>
      connections = [
    // Face
    [0, 1],
    [1, 2],
    [2, 3],
    [3, 7],
    [0, 4],
    [4, 5],
    [5, 6],
    [6, 8],

    // Shoulders
    [11, 12],

    // Left arm
    [11, 13],
    [13, 15],

    // Right arm
    [12, 14],
    [14, 16],

    // Torso
    [11, 23],
    [12, 24],
    [23, 24],

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
        form == 'incorrect';

    final bool waiting =
        form == 'waiting';

    final Color skeletonColor =
        incorrect
            ? Colors.redAccent
            : waiting
                ? Colors.lightBlueAccent
                : Colors.greenAccent;

    final Paint linePaint =
        Paint()
          ..strokeWidth = 4
          ..strokeCap =
              StrokeCap.round
          ..color = skeletonColor;

    final Paint pointPaint =
        Paint()
          ..style =
              PaintingStyle.fill
          ..color = skeletonColor;

    // Draw bones.
    for (final connection
        in connections) {
      final LiveLandmark start =
          landmarks[connection[0]];

      final LiveLandmark end =
          landmarks[connection[1]];

      if (start.visibility < 0.35 ||
          end.visibility < 0.35) {
        continue;
      }

      final Offset startPoint =
          Offset(
        start.x * size.width,
        start.y * size.height,
      );

      final Offset endPoint =
          Offset(
        end.x * size.width,
        end.y * size.height,
      );

      canvas.drawLine(
        startPoint,
        endPoint,
        linePaint,
      );
    }

    // Draw joints.
    for (final landmark
        in landmarks) {
      if (landmark.visibility <
          0.35) {
        continue;
      }

      final Offset point =
          Offset(
        landmark.x * size.width,
        landmark.y * size.height,
      );

      canvas.drawCircle(
        point,
        5,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant SkeletonPainter
        oldDelegate,
  ) {
    return true;
  }
}
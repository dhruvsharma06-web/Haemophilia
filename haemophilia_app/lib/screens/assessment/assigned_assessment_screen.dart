import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class AssignedAssessmentScreen extends StatefulWidget {
  const AssignedAssessmentScreen({
    super.key,
  });

  @override
  State<AssignedAssessmentScreen> createState() =>
      _AssignedAssessmentScreenState();
}

class _AssignedAssessmentScreenState
    extends State<AssignedAssessmentScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  WebSocketChannel? _channel;
  StreamSubscription? _socketSubscription;

  bool _loading = true;
  bool _ending = false;
  bool _completed = false;

  String? _error;

  String? _sessionId;

  List<Map<String, dynamic>> _exercises = [];

  int _currentIndex = 0;

  int _currentCorrectReps = 0;
  int _currentTotalReps = 0;

  double _currentAverageScore = 0;

  final Map<String, List<Map<String, dynamic>>>
      _exerciseReps = {};

  String get _currentExercise {
    if (_exercises.isEmpty) {
      return '';
    }

    return _exercises[_currentIndex]
            ['exercise']
        ?.toString() ??
        '';
  }

  String get _currentExerciseName {
    if (_exercises.isEmpty) {
      return '';
    }

    return _exercises[_currentIndex]
            ['name']
        ?.toString() ??
        'Exercise';
  }

  int get _currentTarget {
    if (_exercises.isEmpty) {
      return 0;
    }

    return int.tryParse(
          _exercises[_currentIndex]
                  ['targetCorrectReps']
              ?.toString() ??
              '0',
        ) ??
        0;
  }

  String get _websocketUrl {
    final exercise =
        Uri.encodeQueryComponent(
      _currentExercise,
    );

    return 'wss://than-varieties-aims-computation.trycloudflare.com'
        '/v1/assessments/live'
        '?exercise=$exercise';
  }

  @override
  void initState() {
    super.initState();
    _loadAssignment();
  }

  Future<void> _loadAssignment() async {
    try {
      final uid =
          _auth.currentUser?.uid;

      if (uid == null) {
        throw Exception(
          'Patient account not found.',
        );
      }

      final doc = await _firestore
          .collection('exerciseAssignments')
          .doc(uid)
          .get();

      if (!doc.exists) {
        throw Exception(
          'No exercise assignment found.',
        );
      }

      final data =
          doc.data() ?? {};

      final rawExercises =
          data['exercises'];

      if (rawExercises is! List ||
          rawExercises.isEmpty) {
        throw Exception(
          'No exercises have been assigned.',
        );
      }

      final exercises =
          rawExercises
              .whereType<Map>()
              .map(
                (item) =>
                    Map<String, dynamic>.from(
                  item,
                ),
              )
              .toList();

      exercises.sort(
        (a, b) =>
            ((a['order'] as num?) ??
                    0)
                .compareTo(
              ((b['order'] as num?) ??
                      0),
            ),
      );

      _sessionId =
          DateTime.now()
              .microsecondsSinceEpoch
              .toString();

      for (final exercise
          in exercises) {
        final key =
            exercise['exercise']
                .toString();

        _exerciseReps[key] = [];
      }

      if (!mounted) return;

      setState(() {
        _exercises = exercises;
        _loading = false;
      });

      await _createSession();

      await _connectWebSocket();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createSession() async {
    final uid =
        _auth.currentUser?.uid;

    if (uid == null ||
        _sessionId == null) {
      return;
    }

    final assignment =
        await _firestore
            .collection('exerciseAssignments')
            .doc(uid)
            .get();

    final assignmentData =
        assignment.data() ?? {};

    await _firestore
        .collection('assessmentSessions')
        .doc(_sessionId)
        .set({
      'patientId': uid,
      'doctorId':
          assignmentData['doctorId'],
      'assignmentId': uid,
      'status': 'in_progress',
      'startedAt':
          FieldValue.serverTimestamp(),
      'endedAt': null,
      'exercises':
          _buildExerciseSummary(),
    });
  }

  List<Map<String, dynamic>>
      _buildExerciseSummary() {
    return _exercises.map((exercise) {
      final key =
          exercise['exercise']
              .toString();

      final reps =
          _exerciseReps[key] ?? [];

      final correct =
          reps.where(
        (rep) =>
            rep['form']
                ?.toString()
                .toLowerCase() ==
            'correct',
      ).length;

      final total = reps.length;

      final scores = reps
          .map(
            (rep) =>
                double.tryParse(
                  rep['score']
                          ?.toString() ??
                      '',
                ) ??
                0,
          )
          .toList();

      final average =
          scores.isEmpty
              ? 0.0
              : scores.reduce(
                    (a, b) => a + b,
                  ) /
                  scores.length;

      final target =
          int.tryParse(
                exercise[
                        'targetCorrectReps']
                    ?.toString() ??
                    '0',
              ) ??
              0;

      String status;

      if (correct >= target &&
          target > 0) {
        status = 'completed';
      } else if (total > 0) {
        status = 'incomplete';
      } else {
        status = 'not_done';
      }

      return {
        'exercise': key,
        'name': exercise['name'],
        'targetCorrectReps':
            target,
        'correctReps': correct,
        'totalReps': total,
        'status': status,
        'averageScore':
            double.parse(
          average.toStringAsFixed(1),
        ),
      };
    }).toList();
  }

  Future<void> _connectWebSocket() async {
    if (_currentExercise.isEmpty) {
      return;
    }

    final channel =
        IOWebSocketChannel.connect(
      Uri.parse(_websocketUrl),
      connectTimeout:
          const Duration(seconds: 10),
    );

    _channel = channel;

    try {
      await channel.ready;
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error =
            'Could not connect to AI: $e';
      });

      return;
    }

    _socketSubscription =
        channel.stream.listen(
      _handleSocketMessage,
      onError: (error) {
        debugPrint(
          'Assessment WebSocket error: $error',
        );
      },
      onDone: () {
        debugPrint(
          'Assessment WebSocket closed.',
        );
      },
    );
  }

  void _handleSocketMessage(
    dynamic message,
  ) {
    if (message is! String) {
      return;
    }

    try {
      final data =
          jsonDecode(message)
              as Map<String, dynamic>;

      if (data['type'] == 'error') {
        debugPrint(
          'AI error: ${data['message']}',
        );
        return;
      }

      if (data['type'] !=
          'live_state') {
        return;
      }

      final completed =
          data['completed_rep'];

      if (completed is! Map) {
        return;
      }

      final rep =
          Map<String, dynamic>.from(
        completed,
      );

      final form =
          rep['form']
              ?.toString()
              .toLowerCase() ??
              '';

      final score =
          double.tryParse(
                rep['score']
                        ?.toString() ??
                    '0',
              ) ??
              0;

      final exercise =
          _currentExercise;

      _currentTotalReps++;

      if (form == 'correct') {
        _currentCorrectReps++;
      }

      _currentAverageScore =
          _calculateRunningAverage(
        _currentAverageScore,
        _currentTotalReps,
        score,
      );

      _exerciseReps[
              exercise]!
          .add({
        ...rep,
        'exercise': exercise,
        'timestamp':
            DateTime.now()
                .toIso8601String(),
      });

      if (mounted) {
        setState(() {});
      }

      unawaited(
        _saveSessionProgress(),
      );

      if (
          form == 'correct' &&
          _currentCorrectReps >=
              _currentTarget) {
        unawaited(
          _finishCurrentExercise(),
        );
      }
    } catch (e) {
      debugPrint(
        'Could not process assessment message: $e',
      );
    }
  }

  double _calculateRunningAverage(
    double oldAverage,
    int count,
    double newScore,
  ) {
    if (count <= 1) {
      return newScore;
    }

    return ((oldAverage *
                (count - 1)) +
            newScore) /
        count;
  }

  Future<void> _finishCurrentExercise()
      async {
    if (_ending ||
        _completed) {
      return;
    }

    if (_currentCorrectReps <
        _currentTarget) {
      return;
    }

    await _saveSessionProgress();

    if (_currentIndex >=
        _exercises.length - 1) {
      await _completeSession();
      return;
    }

    final nextIndex =
        _currentIndex + 1;

    final nextExercise =
        _exercises[nextIndex]
                ['exercise']
            .toString();

    if (mounted) {
      setState(() {
        _currentIndex =
            nextIndex;
        _currentCorrectReps = 0;
        _currentTotalReps = 0;
        _currentAverageScore = 0;
      });
    }

    _channel?.sink.add(
      jsonEncode({
        'type':
            'switch_exercise',
        'exercise':
            nextExercise,
      }),
    );
  }

  Future<void>
      _saveSessionProgress() async {
    final id = _sessionId;

    if (id == null) {
      return;
    }

    try {
      await _firestore
          .collection('assessmentSessions')
          .doc(id)
          .set({
        'status': 'in_progress',
        'exercises':
            _buildExerciseSummary(),
        'updatedAt':
            FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'Could not save session progress: $e',
      );
    }
  }

  Future<void> _completeSession()
      async {
    if (_completed) {
      return;
    }

    _completed = true;

    await _firestore
        .collection('assessmentSessions')
        .doc(_sessionId)
        .set({
      'status': 'completed',
      'exercises':
          _buildExerciseSummary(),
      'endedAt':
          FieldValue.serverTimestamp(),
      'updatedAt':
          FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _channel?.sink.close();
    await _socketSubscription
        ?.cancel();

    if (!mounted) return;

    await _showFinishedDialog(
      completed: true,
    );
  }

  Future<void> _endAssessment()
      async {
    if (_ending ||
        _completed) {
      return;
    }

    final shouldEnd =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'End assessment?',
          ),
          content: const Text(
            'Your current progress will be saved. '
            'Exercises that have not reached their '
            'correct-repetition target will be marked incomplete.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child: const Text(
                'Continue',
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child: const Text(
                'End Assessment',
              ),
            ),
          ],
        );
      },
    );

    if (shouldEnd != true) {
      return;
    }

    setState(() {
      _ending = true;
    });

    try {
      await _firestore
          .collection('assessmentSessions')
          .doc(_sessionId)
          .set({
        'status': 'incomplete',
        'exercises':
            _buildExerciseSummary(),
        'endedAt':
            FieldValue.serverTimestamp(),
        'updatedAt':
            FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _channel?.sink.close();

      await _socketSubscription
          ?.cancel();

      if (!mounted) return;

      await _showFinishedDialog(
        completed: false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _ending = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Could not end assessment: $e',
          ),
        ),
      );
    }
  }

  Future<void> _showFinishedDialog({
    required bool completed,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(
            completed
                ? 'Assessment Complete'
                : 'Assessment Incomplete',
          ),
          content: Text(
            completed
                ? 'All assigned exercises have been completed.'
                : 'Your progress has been saved. '
                    'Incomplete exercises are marked accordingly.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);

                Navigator.pop(
                  this.context,
                  true,
                );
              },
              child: const Text(
                'Done',
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _channel?.sink.close();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Assessment',
          ),
        ),
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign:
                  TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_exercises.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            'No exercises assigned.',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _currentExerciseName,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressHeader(),

            Expanded(
              child: Center(
                child: Text(
                  'Camera assessment is active.\n'
                  'Use the live camera area here.',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed:
                      _ending
                          ? null
                          : _endAssessment,
                  icon: const Icon(
                    Icons.stop,
                  ),
                  label: Text(
                    _ending
                        ? 'Saving...'
                        : 'End Assessment',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        14,
      ),
      color: Colors.black87,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            'Exercise ${_currentIndex + 1} '
            'of ${_exercises.length}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _currentExerciseName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$_currentCorrectReps/'
                '$_currentTarget correct',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'Total reps: '
                '$_currentTotalReps',
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value:
                _currentTarget <= 0
                    ? 0
                    : (_currentCorrectReps /
                            _currentTarget)
                        .clamp(
                            0.0,
                            1.0),
          ),
        ],
      ),
    );
  }
}
import '../../widgets/app_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../assessment/live_assessment_screen.dart';
import '../../utils/app_localizations.dart';
import '../../utils/exercise_utils.dart';
import '../../utils/schedule_utils.dart';
import '../../widgets/exercise_demo/exercise_demo_dialog.dart';

class AssignedAssessmentScreen extends StatefulWidget {
  const AssignedAssessmentScreen({super.key});

  @override
  State<AssignedAssessmentScreen> createState() =>
      _AssignedAssessmentScreenState();
}

class _AssignedAssessmentScreenState
    extends State<AssignedAssessmentScreen> {
  bool _loading = true;
  String? _error;
  bool _isCompleted = false;
  bool _isNotAssigned = false;
  bool _isPaused = false;
  String? _savedSessionId;
  int _savedExerciseIndex = 0;
  int _savedCorrectReps = 0;
  int _savedTotalReps = 0;
  List<Map<String, dynamic>>? _savedExerciseProgress;

  String _sessionName = '';
  String _doctorId = '';
  List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _loadAssignment();
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizeExercise(dynamic value) {
    return normalizeExerciseId(value?.toString());
  }

  String _displayName(String exercise) {
    return getExerciseDisplayName(exercise);
  }

  IconData _exerciseIcon(String exercise) {
    return getExerciseIcon(exercise);
  }

  Future<void> _loadAssignment() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Patient is not logged in.');
      }

      final doc = await FirebaseFirestore.instance
          .collection('exerciseAssignments')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        if (!mounted) return;
        setState(() {
          _isNotAssigned = true;
          _loading = false;
        });
        return;
      }

      final data = doc.data();

      if (data == null) {
        if (!mounted) return;
        setState(() {
          _isNotAssigned = true;
          _loading = false;
        });
        return;
      }

      // 1. Verify patient ownership
      final patientId = data['patientId']?.toString();
      if (patientId != null && patientId.isNotEmpty && patientId != user.uid) {
        throw Exception('Assignment does not belong to the logged-in patient.');
      }

      // 2. Verify status is active 'assigned', 'paused', or 'in_progress'
      final status = data['status']?.toString().trim().toLowerCase() ?? '';
      if (!assignmentAvailable(data, DateTime.now())) {
        if (!mounted) return;
        setState(() {
          if (status == 'completed') {
            _isCompleted = true;
          } else {
            _isNotAssigned = true;
          }
          _loading = false;
        });
        return;
      }

      final isPaused = status == 'paused' || status == 'in_progress';
      final savedSessionId = isPaused ? data['sessionId']?.toString() : null;
      final savedExerciseIndex = isPaused ? _toInt(data['currentExerciseIndex']) : 0;
      final savedCorrectReps = isPaused ? _toInt(data['completedCorrectReps']) : 0;
      final savedTotalReps = isPaused ? _toInt(data['totalCompletedReps']) : 0;
      List<Map<String, dynamic>>? savedProg;
      final rawProg = data['exerciseProgress'];
      if (rawProg is List) {
        savedProg = rawProg
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // 3. Verify doctorId exists
      final doctorId = data['doctorId']?.toString().trim() ?? '';
      if (doctorId.isEmpty) {
        throw Exception('The assigned session has no associated doctor.');
      }

      // 4. Read sessionName
      final sessionName = data['sessionName']?.toString().trim() ?? '';
      if (sessionName.isEmpty) {
        throw Exception('The assigned session does not have a session name.');
      }

      // 5. Read and validate exercises
      final rawExercises = data['exercises'];

      if (rawExercises is! List || rawExercises.isEmpty) {
        throw Exception('No exercises have been assigned by your doctor.');
      }

      final exercises = rawExercises
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((exercise) {
            final exerciseName = _normalizeExercise(exercise['exercise']);
            final target = _toInt(exercise['targetCorrectReps']);
            return exerciseName.isNotEmpty && target > 0;
          })
          .map((exercise) {
            final normalized = Map<String, dynamic>.from(exercise);
            normalized['exercise'] = _normalizeExercise(normalized['exercise']);
            return normalized;
          })
          .toList();

      exercises.sort(
        (a, b) => _toInt(a['order']).compareTo(_toInt(b['order'])),
      );

      if (exercises.isEmpty) {
        throw Exception('The assigned exercises are invalid.');
      }

      if (!mounted) return;

      setState(() {
        _sessionName = sessionName;
        _doctorId = doctorId;
        _exercises = exercises;
        _isPaused = isPaused;
        _savedSessionId = savedSessionId;
        _savedExerciseIndex = savedExerciseIndex;
        _savedCorrectReps = savedCorrectReps;
        _savedTotalReps = savedTotalReps;
        _savedExerciseProgress = savedProg;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _discardSession() async {
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
        title: Text(
          tr('Discard Session?'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          tr('Are you sure you want to discard your progress? This session will be marked as discarded and cannot be resumed.'),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Discard')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('exerciseAssignments')
          .doc(user.uid)
          .set({
        'status': 'discarded',
        'discardedAt': FieldValue.serverTimestamp(),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (_savedSessionId != null && _savedSessionId!.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('assessmentSessions')
            .doc(_savedSessionId)
            .set({
          'sessionId': _savedSessionId,
          'assignmentId': user.uid,
          'patientId': user.uid,
          'status': 'discarded',
          'discardedAt': FieldValue.serverTimestamp(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    if (mounted) {
      setState(() {
        _isNotAssigned = true;
        _isPaused = false;
      });
    }
  }

  void _startAssessment() {
    if (_exercises.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    // VERY IMPORTANT: Only reuse _savedSessionId if session is genuinely paused/in_progress.
    // Starting a new assignment MUST ALWAYS generate a fresh unique sessionId.
    final sessionId = (_isPaused && _savedSessionId != null && _savedSessionId!.isNotEmpty)
        ? _savedSessionId!
        : (user != null
            ? '${user.uid}_${DateTime.now().millisecondsSinceEpoch}'
            : DateTime.now().microsecondsSinceEpoch.toString());

    debugPrint('AssignedAssessment: launching session $sessionId (isPaused: $_isPaused, sessionName: $_sessionName)');

    final initialIndex = _isPaused
        ? _savedExerciseIndex.clamp(0, _exercises.length - 1)
        : 0;
    final exerciseToStart = _exercises[initialIndex]['exercise'].toString();

    int currentExCorrect = 0;
    int currentExTotal = 0;
    if (_isPaused && _savedExerciseProgress != null && initialIndex < _savedExerciseProgress!.length) {
      final exProg = _savedExerciseProgress![initialIndex];
      currentExCorrect = _toInt(exProg['completedCorrectReps']);
      currentExTotal = _toInt(exProg['completedTotalReps']);
    } else if (_isPaused) {
      currentExCorrect = _savedCorrectReps;
      currentExTotal = _savedTotalReps;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAssessmentScreen(
          exerciseName: exerciseToStart,
          assignedExercises: _exercises,
          assignedDoctorId: _doctorId,
          sessionName: _sessionName,
          sessionId: sessionId,
          initialExerciseIndex: initialIndex,
          initialCorrectReps: currentExCorrect,
          initialTotalReps: currentExTotal,
          initialRepSequence: _isPaused ? _savedTotalReps : 0,
          initialExerciseProgress: _isPaused ? _savedExerciseProgress : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isCompleted || _isNotAssigned) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            tr('Assigned Assessment'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: const [
            LanguageToggleButton(),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _isCompleted
                        ? Colors.green.withValues(alpha: .1)
                        : Colors.grey.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    _isCompleted
                        ? Icons.check_circle_outline_rounded
                        : Icons.assignment_late_outlined,
                    size: 38,
                    color: _isCompleted ? Colors.green.shade600 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr('All done for now'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isCompleted
                      ? tr('Your doctor will assign your next session when you are ready.')
                      : tr('No exercise session is currently assigned.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(tr('Back to Dashboard')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            tr('Assigned Assessment'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: const [
            LanguageToggleButton(),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.assignment_late_outlined,
                  size: 56,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _loadAssignment();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr('Try Again')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Assigned Session'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [
          LanguageToggleButton(),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ======================================================
              // SESSION NAME CARD
              // ======================================================
              Card(
                elevation: 0,
                color: primary.withValues(alpha: 0.07),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.assignment_rounded,
                          color: primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tr('SESSION NAME'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (_isPaused) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade700,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      tr('IN PROGRESS'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _sessionName,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Text(
                tr('Exercises'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Complete each exercise in the assigned order. Only correct repetitions count.'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: ListView.separated(
                  itemCount: _exercises.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    final rawName = exercise['exercise'].toString();
                    final name = _displayName(rawName);
                    final target = _toInt(exercise['targetCorrectReps']);

                    final isWip = isWorkInProgressExercise(rawName);

                    final isDone = _isPaused && index < _savedExerciseIndex;
                    final isCurrent = _isPaused && index == _savedExerciseIndex;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: isDone
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : (isCurrent
                                        ? Colors.amber.withValues(alpha: 0.15)
                                        : primary.withValues(alpha: 0.08)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: isDone
                                  ? const Icon(Icons.check, color: Colors.green, size: 22)
                                  : AppText(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: isCurrent ? Colors.amber.shade900 : primary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                   AppText(
                                    '${tr('Exercise')} ${index + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tr(name),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (isWip) ...[
                                        const SizedBox(width: 8),
                                        buildWipBadge(compact: true),
                                      ],
                                    ],
                                  ),
                                  if (isWip) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      tr('Work in progress'),
                                      style: TextStyle(
                                        color: Colors.amber.shade900,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (isDone) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          size: 14,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 4),
                                        AppText(
                                          '${tr('Completed')} ($target/$target ${tr('correct reps')})',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else if (isCurrent) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.play_circle_outline_rounded,
                                          size: 14,
                                          color: Colors.amber.shade800,
                                        ),
                                        const SizedBox(width: 4),
                                        AppText(
                                          '${tr('In Progress')} • $_savedCorrectReps/$target ${tr('correct reps')}',
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 3),
                                    AppText(
                                      '${tr('Target')}: $target ${tr('correct reps')}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () {
                                      showExerciseDemoDialog(
                                        context,
                                        exerciseName: rawName,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.play_circle_outline_rounded,
                                            size: 15,
                                            color: primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            tr('How to perform'),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                showExerciseDemoDialog(
                                  context,
                                  exerciseName: rawName,
                                );
                              },
                              tooltip: '${tr('How to perform')} ${tr(name)}',
                              icon: Icon(
                                _exerciseIcon(rawName),
                                color: isDone
                                    ? Colors.green
                                    : (isCurrent ? Colors.amber.shade800 : primary),
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 14),

              if (_isPaused) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _startAssessment,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      tr('Continue Session'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    onPressed: _discardSession,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(
                      tr('Discard Session'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _startAssessment,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      tr('Start Session'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
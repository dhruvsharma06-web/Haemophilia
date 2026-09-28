import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/clinical_data_service.dart';
import '../patient/patient_history.dart';
import 'doctor_messages.dart';
import 'doctor_session_detail.dart';
import 'assign_exercises_screen.dart';
import '../../utils/exercise_utils.dart';
import '../../widgets/session_analytics_chart.dart';

class DoctorPatientDetail extends StatelessWidget {
  final String patientId;
  final UserModel patient;

  const DoctorPatientDetail({
    super.key,
    required this.patientId,
    required this.patient,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          patient.name.isEmpty ? 'Patient' : patient.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ClinicalDataService().watchPatientAssessments(patientId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load patient data.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          final sessions = groupAssessmentSessions(docs);

          final totalRepsAll = sessions.fold<int>(0, (acc, s) => acc + s.reps);
          final totalCorrectAll = sessions.fold<int>(0, (acc, s) => acc + s.correctReps);
          final accuracyPct = totalRepsAll > 0 ? (totalCorrectAll / totalRepsAll * 100) : 0.0;

          final avg = sessions.isEmpty
              ? 0.0
              : sessions
                      .map((session) => session.averageScore)
                      .reduce((a, b) => a + b) /
                  sessions.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _ProfileCard(patient: patient),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DoctorMessages(
                        patientId: patientId,
                        patient: patient,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Message patient'),
              ),
              const SizedBox(height: 10),

OutlinedButton.icon(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignExercisesScreen(
          patientId: patientId,
          patient: patient,
        ),
      ),
    );
  },
  icon: const Icon(
    Icons.assignment_outlined,
  ),
  label: const Text(
    'Assign Exercises',
  ),
),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('exerciseAssignments')
                    .doc(patientId)
                    .snapshots(),
                builder: (context, assignmentSnap) {
                  if (!assignmentSnap.hasData ||
                      !assignmentSnap.data!.exists ||
                      assignmentSnap.data!.data() == null) {
                    return const SizedBox.shrink();
                  }

                  final data = assignmentSnap.data!.data()!;
                  final status = data['status']?.toString().toLowerCase() ?? 'assigned';
                  final sessionName = data['sessionName']?.toString().trim() ?? 'Physiotherapy Session';
                  final rawExercises = data['exercises'];
                  final exercises = rawExercises is List ? rawExercises : [];
                  final totalExercises = exercises.length;

                  final rawProg = data['exerciseProgress'];
                  final progressList = rawProg is List ? rawProg : [];

                  int completedExCount = 0;
                  int totalCorrect = 0;
                  int totalTarget = 0;
                  int totalAttempted = int.tryParse(data['totalCompletedReps']?.toString() ?? '0') ?? 0;

                  for (final ex in exercises) {
                    if (ex is Map) {
                      totalTarget += int.tryParse(ex['targetCorrectReps']?.toString() ?? '0') ?? 0;
                    }
                  }

                  if (progressList.isNotEmpty) {
                    for (final p in progressList) {
                      if (p is Map) {
                        if (p['status'] == 'completed') completedExCount++;
                        totalCorrect += int.tryParse(p['completedCorrectReps']?.toString() ?? '0') ?? 0;
                        final exAttempted = int.tryParse(p['completedTotalReps']?.toString() ?? '0') ?? 0;
                        if (exAttempted > 0 && totalAttempted == 0) {
                          totalAttempted += exAttempted;
                        }
                      }
                    }
                  } else {
                    totalCorrect = int.tryParse(data['completedCorrectReps']?.toString() ?? '0') ?? 0;
                    final curIdx = int.tryParse(data['currentExerciseIndex']?.toString() ?? '0') ?? 0;
                    completedExCount = status == 'completed' ? totalExercises : curIdx;
                  }

                  final currentExercise = data['currentExercise']?.toString() ?? '';

                  final lastUpdated = data['lastUpdatedAt'] ?? data['updatedAt'] ?? data['createdAt'];
                  DateTime? activityTime;
                  if (lastUpdated is Timestamp) {
                    activityTime = lastUpdated.toDate().toLocal();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                    child: _DoctorAssignmentStatusCard(
                      sessionName: sessionName,
                      status: status,
                      completedExercises: completedExCount,
                      totalExercises: totalExercises,
                      correctReps: totalCorrect,
                      targetReps: totalTarget,
                      totalAttemptedReps: totalAttempted,
                      currentExercise: currentExercise,
                      exercises: exercises,
                      exerciseProgress: progressList,
                      lastActivity: activityTime,
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      'Average score',
                      sessions.isEmpty ? '—' : '${avg.toStringAsFixed(0)}/100',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat('Sessions', '${sessions.length}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      'Accuracy',
                      totalRepsAll == 0
                          ? '—'
                          : '${accuracyPct.toStringAsFixed(0)}% ($totalCorrectAll/$totalRepsAll)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const Text(
                'Progress analytics',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),

              SessionAnalyticsChart(
                sessions: sessions,
                isDoctorView: true,
              ),

              const SizedBox(height: 26),

              const Text(
                'Session history',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (sessions.isEmpty)
                const _Empty()
              else
                ...sessions.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: const Icon(Icons.assignment_outlined),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.sessionName,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (isWorkInProgressExercise(session.exercise)) ...[
                              const SizedBox(width: 6),
                              buildWipBadge(compact: true),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${session.reps} reps • ${session.correctReps}/${session.reps} correct',
                        ),
                        trailing: Text(
                          '${session.averageScore.toStringAsFixed(0)}/100',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DoctorSessionDetail(
                                patientId: patientId,
                                patient: patient,
                                session: session,
                              ),
                            ),
                          );
                        },
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
}

class _ProfileCard extends StatelessWidget {
  final UserModel patient;

  const _ProfileCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final details = <String>[];
    if (patient.age != null) details.add('Age: ${patient.age}');
    if (patient.gender != null && patient.gender!.isNotEmpty) {
      details.add('Gender: ${patient.gender}');
    }
    if (patient.phoneNumber != null && patient.phoneNumber!.isNotEmpty) {
      details.add('Phone: ${patient.phoneNumber}');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: primary.withValues(alpha: .1),
              child: Text(
                patient.name.isEmpty
                    ? 'P'
                    : patient.name[0].toUpperCase(),
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name.isNotEmpty ? patient.name : 'Patient',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    patient.email,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      details.join(' • '),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Center(
          child: Text(
            'No assessment sessions yet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}
class PatientProgressChart extends StatelessWidget {
  final List<double> scores;

  const PatientProgressChart({
    super.key,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient Progress',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Assessment score across completed sessions',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 25),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      size: 42,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No progress data yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Patient Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Assessment score across completed sessions',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),

            SizedBox(
              height: 240,
              width: double.infinity,
              child: CustomPaint(
                painter: _ProgressChartPainter(
                  scores: scores,
                  lineColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Session 1',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  'Session ${scores.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressChartPainter extends CustomPainter {
  final List<double> scores;
  final Color lineColor;

  _ProgressChartPainter({
    required this.scores,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    const leftPadding = 38.0;
    const rightPadding = 12.0;
    const topPadding = 12.0;
    const bottomPadding = 28.0;

    final chartWidth =
        size.width - leftPadding - rightPadding;

    final chartHeight =
        size.height - topPadding - bottomPadding;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.18)
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final textStyle = TextStyle(
      color: Colors.grey.shade600,
      fontSize: 10,
    );

    for (int value = 0; value <= 100; value += 25) {
      final y = topPadding +
          chartHeight -
          (value / 100) * chartHeight;

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: '$value',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(
          leftPadding - textPainter.width - 8,
          y - textPainter.height / 2,
        ),
      );
    }

    canvas.drawLine(
      Offset(leftPadding, topPadding),
      Offset(leftPadding, topPadding + chartHeight),
      axisPaint,
    );

    canvas.drawLine(
      Offset(leftPadding, topPadding + chartHeight),
      Offset(
        size.width - rightPadding,
        topPadding + chartHeight,
      ),
      axisPaint,
    );

    final path = Path();

    for (int i = 0; i < scores.length; i++) {
      final score = scores[i].clamp(0.0, 100.0);

      final x = scores.length == 1
          ? leftPadding + chartWidth / 2
          : leftPadding +
              (i / (scores.length - 1)) * chartWidth;

      final y = topPadding +
          chartHeight -
          (score / 100.0) * chartHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);

    for (int i = 0; i < scores.length; i++) {
      final score = scores[i].clamp(0.0, 100.0);

      final x = scores.length == 1
          ? leftPadding + chartWidth / 2
          : leftPadding +
              (i / (scores.length - 1)) * chartWidth;

      final y = topPadding +
          chartHeight -
          (score / 100.0) * chartHeight;

      canvas.drawCircle(
        Offset(x, y),
        5,
        pointPaint,
      );

      final scorePainter = TextPainter(
        text: TextSpan(
          text: score.toStringAsFixed(0),
          style: TextStyle(
            color: lineColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      scorePainter.layout();

      scorePainter.paint(
        canvas,
        Offset(
          x - scorePainter.width / 2,
          y - scorePainter.height - 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _ProgressChartPainter oldDelegate,
  ) {
    return oldDelegate.scores != scores ||
        oldDelegate.lineColor != lineColor;
  }
}

// ================================================================
// DOCTOR ASSIGNMENT / ACTIVE SESSION STATUS CARD
// ================================================================

class _DoctorAssignmentStatusCard extends StatelessWidget {
  final String sessionName;
  final String status;
  final int completedExercises;
  final int totalExercises;
  final int correctReps;
  final int targetReps;
  final int totalAttemptedReps;
  final String currentExercise;
  final List<dynamic> exercises;
  final List<dynamic> exerciseProgress;
  final DateTime? lastActivity;

  const _DoctorAssignmentStatusCard({
    required this.sessionName,
    required this.status,
    required this.completedExercises,
    required this.totalExercises,
    required this.correctReps,
    required this.targetReps,
    this.totalAttemptedReps = 0,
    this.currentExercise = '',
    this.exercises = const [],
    this.exerciseProgress = const [],
    this.lastActivity,
  });

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = months[dt.month - 1];
    final hr = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} $m ${dt.year} • $hr:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    Color statusBg;
    Color statusFg;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'in_progress':
        statusBg = Colors.blue.shade100;
        statusFg = Colors.blue.shade900;
        statusLabel = 'IN PROGRESS';
        statusIcon = Icons.play_arrow_rounded;
        break;
      case 'paused':
        statusBg = Colors.amber.shade100;
        statusFg = Colors.amber.shade900;
        statusLabel = 'PAUSED';
        statusIcon = Icons.pause_circle_rounded;
        break;
      case 'completed':
        statusBg = Colors.green.shade100;
        statusFg = Colors.green.shade900;
        statusLabel = 'COMPLETED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'discarded':
      case 'cancelled':
        statusBg = Colors.red.shade100;
        statusFg = Colors.red.shade900;
        statusLabel = 'DISCARDED';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'assigned':
      default:
        statusBg = Colors.teal.shade100;
        statusFg = Colors.teal.shade900;
        statusLabel = 'ASSIGNED';
        statusIcon = Icons.assignment_outlined;
        break;
    }

    final double completionFraction = targetReps > 0
        ? (correctReps / targetReps).clamp(0.0, 1.0)
        : (totalExercises > 0 ? (completedExercises / totalExercises).clamp(0.0, 1.0) : 0.0);
    final int completionPct = (completionFraction * 100).toInt();

    final int accuracyPct = totalAttemptedReps > 0
        ? ((correctReps / totalAttemptedReps) * 100).clamp(0, 100).toInt()
        : (correctReps > 0 ? 100 : 0);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: statusFg.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CURRENT ASSIGNMENT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sessionName,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusFg, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusFg,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (currentExercise.isNotEmpty && status != 'completed') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      status == 'paused' ? Icons.pause_circle_outline : Icons.play_circle_outline,
                      size: 16,
                      color: Colors.blue.shade800,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Current: ${getExerciseDisplayName(currentExercise)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue.shade900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: completionFraction,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                color: status == 'completed' ? Colors.green : Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$completionPct% Completed',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  '$completedExercises of $totalExercises exercises finished',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Correct Reps',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              targetReps > 0 ? '$correctReps / $targetReps' : '$correctReps',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Reps Attempted',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$totalAttemptedReps',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Accuracy',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              totalAttemptedReps > 0 ? '$accuracyPct%' : '—',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (exercises.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'ASSIGNED EXERCISES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              ...exercises.asMap().entries.map((entry) {
                final idx = entry.key;
                final ex = entry.value;
                if (ex is! Map) return const SizedBox.shrink();

                final exName = ex['exercise']?.toString() ?? '';
                final exTarget = int.tryParse(ex['targetCorrectReps']?.toString() ?? '0') ?? 0;

                int exCorrect = 0;
                String exStatus = 'pending';
                if (idx < exerciseProgress.length && exerciseProgress[idx] is Map) {
                  final prog = exerciseProgress[idx] as Map;
                  exCorrect = int.tryParse(prog['completedCorrectReps']?.toString() ?? '0') ?? 0;
                  exStatus = prog['status']?.toString().toLowerCase() ?? 'pending';
                } else if (status == 'completed') {
                  exCorrect = exTarget;
                  exStatus = 'completed';
                }

                final isExCompleted = exStatus == 'completed';
                final isExCurrent = (exName == currentExercise || exStatus == 'in_progress');

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.5),
                  child: Row(
                    children: [
                      Icon(
                        isExCompleted
                            ? Icons.check_circle_rounded
                            : (isExCurrent ? Icons.play_circle_filled_rounded : Icons.radio_button_unchecked),
                        size: 15,
                        color: isExCompleted
                            ? Colors.green
                            : (isExCurrent ? Colors.blueAccent : Colors.grey.shade400),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          getExerciseDisplayName(exName),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isExCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isExCompleted ? Colors.grey.shade700 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        '$exCorrect / $exTarget correct reps',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isExCompleted ? Colors.green.shade800 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (lastActivity != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade600),
                  const SizedBox(width: 5),
                  Text(
                    'Last activity: ${_formatDateTime(lastActivity!)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
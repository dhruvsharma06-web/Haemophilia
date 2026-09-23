import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/assessment_history_service.dart';
import '../../utils/exercise_utils.dart';
import '../../widgets/session_analytics_chart.dart';

class PatientHistory extends StatelessWidget {
  const PatientHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Session history',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: AssessmentHistoryService().watchAssessments(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load your session history.\n\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final groups = groupAssessmentSessions(
              snapshot.data?.docs ?? const [],
            );

            if (groups.isEmpty) {
              return const _HistoryEmptyState();
            }

            final int sessionsCount = groups.length;
            final int totalCorrectReps = groups.fold<int>(
              0,
              (total, session) => total + session.correctReps,
            );
            final int totalReps = groups.fold<int>(
              0,
              (total, session) => total + session.reps,
            );
            final double correctRate = totalReps == 0
                ? 0.0
                : (totalCorrectReps / totalReps) * 100.0;
            final double avgScore = groups.isEmpty
                ? 0.0
                : groups.fold<double>(
                      0.0,
                      (total, session) => total + session.averageScore,
                    ) /
                    groups.length;
            final double avgRom = groups.isEmpty
                ? 0.0
                : groups.fold<double>(
                      0.0,
                      (total, session) => total + session.averageRom,
                    ) /
                    groups.length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _HistoryStatCard(
                        icon: Icons.event_available_rounded,
                        label: 'Sessions',
                        value: '$sessionsCount',
                      ),
                      _HistoryStatCard(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Correct Reps',
                        value: '$totalCorrectReps',
                      ),
                      _HistoryStatCard(
                        icon: Icons.percent_rounded,
                        label: 'Accuracy',
                        value: totalReps == 0
                            ? '—'
                            : '${correctRate.toStringAsFixed(0)}%',
                      ),
                      _HistoryStatCard(
                        icon: Icons.speed_rounded,
                        label: 'Average Score',
                        value: groups.isEmpty
                            ? '—'
                            : avgScore.toStringAsFixed(0),
                      ),
                      _HistoryStatCard(
                        icon: Icons.track_changes_rounded,
                        label: 'Average ROM',
                        value: groups.isEmpty
                            ? '—'
                            : '${avgRom.toStringAsFixed(0)}°',
                      ),
                    ];

                    final columns = constraints.maxWidth >= 850
                        ? 5
                        : (constraints.maxWidth >= 550 ? 3 : 2);

                    final rows = <Widget>[];

                    for (int i = 0; i < cards.length; i += columns) {
                      final rowCards = cards.skip(i).take(columns).toList();

                      rows.add(
                        Row(
                          children: [
                            for (int j = 0; j < rowCards.length; j++) ...[
                              if (j > 0) const SizedBox(width: 10),
                              Expanded(child: rowCards[j]),
                            ],
                            if (rowCards.length < columns)
                              ...List.generate(
                                columns - rowCards.length,
                                (_) => const Expanded(child: SizedBox()),
                              ),
                          ],
                        ),
                      );

                      if (i + columns < cards.length) {
                        rows.add(const SizedBox(height: 10));
                      }
                    }

                    return Column(children: rows);
                  },
                ),
                const SizedBox(height: 20),
                SessionAnalyticsChart(
                  sessions: groups,
                  isDoctorView: false,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Completed Sessions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ...groups.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SessionCard(
                      session: session,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SessionDetails(
                              session: session,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SessionDetails extends StatelessWidget {
  final AssessmentSession session;

  const SessionDetails({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final correctRate = session.reps == 0
        ? 0.0
        : (session.correctReps / session.reps) * 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Session details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    session.sessionName,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (isWorkInProgressExercise(session.exercise)) ...[
                  const SizedBox(width: 8),
                  buildWipBadge(compact: true),
                ],
              ],
            ),
            if (isWorkInProgressExercise(session.exercise)) ...[
              const SizedBox(height: 3),
              Text(
                '${getExerciseDisplayName(session.exercise)} • Work in progress exercise',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 5),
            Text(
              _formatDateTime(session.date),
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            _SessionStatsGrid(
              session: session,
              correctRate: correctRate,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Assessments in this session',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${session.reps} reps',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...session.repsData.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RepCard(
                  data: entry.value,
                  fallbackRepNumber: entry.key + 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AssessmentSession {
  final String id;
  final String exercise;
  final String sessionName;
  final DateTime date;
  final List<Map<String, dynamic>> repsData;

  AssessmentSession({
    required this.id,
    required this.exercise,
    required this.sessionName,
    required this.date,
    required List<Map<String, dynamic>> repsData,
  }) : repsData = List.unmodifiable(repsData);

  int get reps => repsData.length;

  int get correctReps => repsData.where((data) {
        final form = data['form']?.toString().toLowerCase() ?? '';
        return form.contains('correct') && !form.contains('incorrect');
      }).length;

  double get correctRate => reps == 0 ? 0.0 : (correctReps / reps) * 100.0;

  double get averageScore => _average(repsData, ['score']);

  double get averageRom =>
      _average(repsData, ['rangeOfMotion', 'rom', 'range_of_motion']);

  double get averageDuration => _average(repsData, ['duration']);

  double get averageSmoothness {
    final raw = _average(repsData, ['smoothness', 'smoothness_raw']);
    return raw <= 1.0 && raw > 0 ? raw * 100.0 : raw;
  }

  double get averageConfidence {
    final raw = _average(repsData, ['confidence', 'lstm_confidence']);
    return raw <= 1.0 && raw > 0 ? raw * 100.0 : raw;
  }

  static double? _nullableNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final d = value.toDouble();
      if (d.isNaN || d.isInfinite) return null;
      return d;
    }
    final parsed = double.tryParse(value.toString());
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  static double _average(
    List<Map<String, dynamic>> data,
    List<String> keys,
  ) {
    final values = <double>[];
    for (final item in data) {
      double? val;
      for (final key in keys) {
        val = _nullableNumber(item[key]);
        if (val != null) break;
      }
      if (val != null && val >= 0) {
        values.add(val);
      }
    }

    if (values.isEmpty) {
      return 0.0;
    }

    return values.reduce((a, b) => a + b) / values.length;
  }
}

List<AssessmentSession> groupAssessmentSessions(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final dates = <String, DateTime>{};
  final exercises = <String, String>{};
  final sessionNames = <String, String>{};

  for (final doc in docs) {
    final data = <String, dynamic>{
      ...doc.data(),
      '__docId': doc.id,
    };

    final exercise =
        data['exercise']?.toString() ?? 'Assessment';

    final sessionName =
        data['sessionName']?.toString().trim() ?? '';

    final rawSessionId =
        data['sessionId']?.toString().trim() ?? '';

    final createdAt = data['createdAt'];

    final date = createdAt is Timestamp
        ? createdAt.toDate().toLocal()
        : DateTime.fromMillisecondsSinceEpoch(
            (double.tryParse(data['createdAtMillis']?.toString() ?? '') ??
                    DateTime.now().millisecondsSinceEpoch)
                .toInt(),
          ).toLocal();

    final sessionId = rawSessionId.isNotEmpty
        ? rawSessionId
        : 'legacy_${exercise}_${date.year}_${date.month}_${date.day}_${date.hour}_${date.minute}';

    groups
        .putIfAbsent(
          sessionId,
          () => <Map<String, dynamic>>[],
        )
        .add(data);

    dates[sessionId] =
        dates[sessionId] == null ||
                date.isBefore(dates[sessionId]!)
            ? date
            : dates[sessionId]!;

    exercises[sessionId] = exercise;

    if (sessionName.isNotEmpty) {
      sessionNames[sessionId] = sessionName;
    }
  }

  final sessions = <AssessmentSession>[];

  for (final entry in groups.entries) {
    final rawReps = entry.value;

    // Deduplicate reps within the session:
    // Ensure uniqueness by __docId and positive repNumber.
    final seenRepNumbers = <int>{};
    final seenDocIds = <String>{};
    final deduplicatedReps = <Map<String, dynamic>>[];

    for (final rep in rawReps) {
      final docId = rep['__docId']?.toString() ?? '';
      if (docId.isNotEmpty) {
        if (seenDocIds.contains(docId)) continue;
        seenDocIds.add(docId);
      }

      final rawNum = rep['repNumber'] ?? rep['rep_number'];
      final repNum = rawNum is num
          ? rawNum.toInt()
          : int.tryParse(rawNum?.toString() ?? '');
      if (repNum != null && repNum > 0) {
        if (seenRepNumbers.contains(repNum)) {
          continue; // Skip duplicate repNumber within the same session
        }
        seenRepNumbers.add(repNum);
      }

      deduplicatedReps.add(rep);
    }

    sessions.add(
      AssessmentSession(
        id: entry.key,
        exercise: exercises[entry.key] ?? 'Assessment',
        sessionName: sessionNames[entry.key]?.isNotEmpty == true
            ? sessionNames[entry.key]!
            : exercises[entry.key] ?? 'Assessment',
        date: dates[entry.key] ?? DateTime.now(),
        repsData: deduplicatedReps,
      ),
    );
  }

  sessions.sort(
    (a, b) => b.date.compareTo(a.date),
  );

  return sessions;
}

// ================================================================
// HISTORY STAT CARD
// ================================================================

class _HistoryStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _HistoryStatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
}

// ================================================================
// SESSION CARD
// ================================================================

class _SessionCard extends StatelessWidget {
  final AssessmentSession session;
  final VoidCallback onTap;

  const _SessionCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final correctRate = session.reps == 0
        ? 0.0
        : (session.correctReps / session.reps) * 100;

    final isGood = correctRate >= 70;

    // Distinct exercises in this session
    final distinctExercises = session.repsData
        .map((r) => r['exercise']?.toString())
        .where((e) => e != null && e.isNotEmpty)
        .toSet()
        .toList();

    String exerciseSummary;
    if (distinctExercises.isEmpty) {
      exerciseSummary = getExerciseDisplayName(session.exercise);
    } else if (distinctExercises.length == 1) {
      exerciseSummary = getExerciseDisplayName(distinctExercises.first!);
    } else {
      exerciseSummary =
          '${distinctExercises.length} exercises (${distinctExercises.map((e) => getExerciseDisplayName(e!)).join(', ')})';
    }

    final String statusLabel =
        isGood ? 'Completed' : 'Completed (Needs Practice)';
    final Color statusColor =
        isGood ? Colors.green.shade700 : Colors.orange.shade800;
    final Color statusBg =
        (isGood ? Colors.green : Colors.orange).withValues(alpha: .09);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      isGood
                          ? Icons.check_circle_outline_rounded
                          : Icons.insights_outlined,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.sessionName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatDateTime(session.date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXERCISES',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            exerciseSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CORRECT REPS',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${session.correctReps}/${session.reps} (${correctRate.toStringAsFixed(0)}%)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isGood
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'AVG SCORE',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${session.averageScore.toStringAsFixed(0)}/100',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// SESSION STATS GRID
// ================================================================

class _SessionStatsGrid extends StatelessWidget {
  final AssessmentSession session;
  final double correctRate;

  const _SessionStatsGrid({
    required this.session,
    required this.correctRate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final items = [
              _StatTile(
                label: 'Average Movement Score',
                value: '${session.averageScore.toStringAsFixed(0)}/100',
              ),
              _StatTile(
                label: 'Total Correct Reps',
                value: '${session.correctReps}/${session.reps}',
              ),
              _StatTile(
                label: 'Correct Rep Rate',
                value: '${correctRate.toStringAsFixed(0)}%',
              ),
              _StatTile(
                label: 'Range of Motion',
                value: '${session.averageRom.toStringAsFixed(0)}°',
              ),
              _StatTile(
                label: 'Average Duration',
                value: '${session.averageDuration.toStringAsFixed(1)}s',
              ),
              _StatTile(
                label: 'Movement Smoothness',
                value: '${session.averageSmoothness.toStringAsFixed(0)}%',
              ),
            ];

            final columns = constraints.maxWidth >= 700 ? 3 : 2;

            final rows = <Widget>[];

            for (var i = 0; i < items.length; i += columns) {
              final row = items.skip(i).take(columns).toList();

              rows.add(
                Row(
                  children: [
                    for (var j = 0; j < row.length; j++) ...[
                      if (j > 0) const SizedBox(width: 10),
                      Expanded(child: row[j]),
                    ],
                    if (row.length < columns)
                      ...List.generate(
                        columns - row.length,
                        (_) => const Expanded(child: SizedBox()),
                      ),
                  ],
                ),
              );

              if (i + columns < items.length) {
                rows.add(const SizedBox(height: 10));
              }
            }

            return Column(children: rows);
          },
        ),

        // Optional Technical & AI Details expansion tile
        if (session.averageConfidence > 0) ...[
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text(
                'Technical Details',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Pose Confidence: ${session.averageConfidence.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Pose landmarks detected by real-time MediaPipe model.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: primary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// REP CARD (PATIENT-FRIENDLY)
// ================================================================

class _RepCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int fallbackRepNumber;

  const _RepCard({
    required this.data,
    required this.fallbackRepNumber,
  });

  String _formatPatientError(String error) {
    final upper = error.toUpperCase().trim();
    switch (upper) {
      case 'RIGHT_ARM_LOW':
        return 'Keep both arms level during the movement.';
      case 'LEFT_ARM_LOW':
        return 'Keep both arms level during the movement.';
      case 'ARM_ASYMMETRY':
        return 'Raise both arms with even height and symmetry.';
      case 'BODY_TILT':
        return 'Keep your torso upright and avoid leaning.';
      case 'GENERAL_FORM_ERROR':
        return 'Maintain steady posture through the full movement.';
      default:
        return error.replaceAll('_', ' ').toLowerCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final form = data['form']?.toString() ?? 'Unknown';
    final incorrect = form.toLowerCase().contains('incorrect');

    final score = _number(data['score']);
    final rom = _number(data['rangeOfMotion']);
    final duration = _number(data['duration']);
    final speed = data['speed']?.toString() ?? 'Normal';
    final confidence = _number(data['confidence']);
    final error = data['errorType']?.toString() ?? '';
    final feedback = data['feedback']?.toString() ?? '';

    final storedRepNumber = _number(data['repNumber']).toInt();
    final repNumber = storedRepNumber > 0
        ? storedRepNumber
        : fallbackRepNumber;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  incorrect
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: incorrect ? Colors.red.shade600 : primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'Rep $repNumber',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (incorrect ? Colors.red : Colors.green)
                              .withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          incorrect ? 'Needs Adjustment' : 'Good Form',
                          style: TextStyle(
                            color: incorrect
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${score.toStringAsFixed(0)}/100',
                  style: TextStyle(
                    color: incorrect ? Colors.red.shade700 : primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                _RepMetric(
                  label: 'RANGE OF MOTION',
                  value: '${rom.toStringAsFixed(0)}°',
                ),
                _RepMetric(
                  label: 'SPEED',
                  value: speed,
                ),
                _RepMetric(
                  label: 'DURATION',
                  value: '${duration.toStringAsFixed(1)}s',
                ),
              ],
            ),
            if (error.isNotEmpty || feedback.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (incorrect ? Colors.red : Colors.blue)
                      .withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (incorrect ? Colors.red : Colors.blue)
                        .withValues(alpha: .15),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (error.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 14,
                            color: incorrect
                                ? Colors.red.shade700
                                : Colors.blueAccent,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Focus',
                            style: TextStyle(
                              color: incorrect
                                  ? Colors.red.shade700
                                  : Colors.blueAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatPatientError(error),
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (feedback.isNotEmpty &&
                        feedback != 'Rep completed.') ...[
                      if (error.isNotEmpty) const SizedBox(height: 6),
                      Text(
                        feedback,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (confidence > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Assessment consistency: ${confidence.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                    if ((data['doctorFeedback']?.toString() ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Doctor feedback',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        data['doctorFeedback'].toString(),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _RepMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RepMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final primary =
        Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color:
                    primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 36,
                color: primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No sessions yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Complete an assessment session and '
              'your session results will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _number(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();

  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return 'Today • $time';
  }

  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} • $time';
}
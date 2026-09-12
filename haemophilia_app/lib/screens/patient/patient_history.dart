import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/assessment_history_service.dart';

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
              return const Center(child: CircularProgressIndicator());
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

            final groups = groupAssessmentSessions(snapshot.data?.docs ?? const []);
            if (groups.isEmpty) {
              return const _HistoryEmptyState();
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final session = groups[index];
                return _SessionCard(
                  session: session,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SessionDetails(session: session),
                      ),
                    );
                  },
                );
              },
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
    final avgScore = session.averageScore;
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
            Text(
              session.exercise,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _formatDateTime(session.date),
              style: TextStyle(color: Colors.grey.shade600),
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
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
  final DateTime date;
  final List<Map<String, dynamic>> repsData;

  AssessmentSession({
    required this.id,
    required this.exercise,
    required this.date,
    required List<Map<String, dynamic>> repsData,
  }) : repsData = List.unmodifiable(repsData);

  int get reps => repsData.length;

  int get correctReps => repsData.where((data) {
        final form = data['form']?.toString().toLowerCase() ?? '';
        return form.contains('correct') && !form.contains('incorrect');
      }).length;

  double get averageScore => _average(repsData, 'score');
  double get averageRom => _average(repsData, 'rangeOfMotion');
  double get averageDuration => _average(repsData, 'duration');
  double get averageConfidence => _average(repsData, 'confidence');

  static double _average(List<Map<String, dynamic>> data, String key) {
    final values = data
        .map((item) => _number(item[key]))
        .where((value) => value != null)
        .cast<double>()
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

List<AssessmentSession> groupAssessmentSessions(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final dates = <String, DateTime>{};
  final exercises = <String, String>{};

  for (final doc in docs) {
    final data = <String, dynamic>{...doc.data(), '__docId': doc.id};
    final exercise = data['exercise']?.toString() ?? 'Assessment';
    final rawSessionId = data['sessionId']?.toString() ?? '';
    final createdAt = data['createdAt'];
    final date = createdAt is Timestamp
        ? createdAt.toDate().toLocal()
        : DateTime.fromMillisecondsSinceEpoch(
            (_number(data['createdAtMillis']) ?? DateTime.now().millisecondsSinceEpoch).toInt(),
          ).toLocal();

    // Older records created before session support are grouped by exercise and
    // minute so the user's existing history remains useful.
    final sessionId = rawSessionId.isNotEmpty
        ? rawSessionId
        : 'legacy_${exercise}_${date.year}_${date.month}_${date.day}_${date.hour}_${date.minute}';

    groups.putIfAbsent(sessionId, () => <Map<String, dynamic>>[]).add(data);
    dates[sessionId] = dates[sessionId] == null || date.isBefore(dates[sessionId]!)
        ? date
        : dates[sessionId]!;
    exercises[sessionId] = exercise;
  }

  final sessions = groups.entries
      .map(
        (entry) => AssessmentSession(
          id: entry.key,
          exercise: exercises[entry.key] ?? 'Assessment',
          date: dates[entry.key] ?? DateTime.now(),
          repsData: entry.value,
        ),
      )
      .toList();

  sessions.sort((a, b) => b.date.compareTo(a.date));
  return sessions;
}

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
    final sessionGood = correctRate >= 70;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (sessionGood ? primary : Colors.orange).withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      sessionGood
                          ? Icons.check_circle_outline
                          : Icons.insights_outlined,
                      color: sessionGood ? primary : Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.exercise,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  _SessionMetric(
                    label: 'SCORE',
                    value: session.averageScore.toStringAsFixed(0),
                  ),
                  _SessionMetric(
                    label: 'REPS',
                    value: '${session.reps}',
                  ),
                  _SessionMetric(
                    label: 'CORRECT',
                    value: '${session.correctReps}/${session.reps}',
                  ),
                  _SessionMetric(
                    label: 'AVG ROM',
                    value: '${session.averageRom.toStringAsFixed(0)}°',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionStatsGrid extends StatelessWidget {
  final AssessmentSession session;
  final double correctRate;

  const _SessionStatsGrid({
    required this.session,
    required this.correctRate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final items = [
          _StatTile(label: 'Average score', value: '${session.averageScore.toStringAsFixed(0)}/100'),
          _StatTile(label: 'Correct reps', value: '${session.correctReps}/${session.reps}'),
          _StatTile(label: 'Success rate', value: '${correctRate.toStringAsFixed(0)}%'),
          _StatTile(label: 'Average ROM', value: '${session.averageRom.toStringAsFixed(0)}°'),
          _StatTile(label: 'Avg duration', value: '${session.averageDuration.toStringAsFixed(1)}s'),
          _StatTile(label: 'AI confidence', value: '${session.averageConfidence.toStringAsFixed(1)}%'),
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
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

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
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
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

class _RepCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final int fallbackRepNumber;

  const _RepCard({
    required this.data,
    required this.fallbackRepNumber,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final form = data['form']?.toString() ?? 'Unknown';
    final incorrect = form.toLowerCase().contains('incorrect');
    final score = _number(data['score']);
    final rom = _number(data['rangeOfMotion']);
    final duration = _number(data['duration']);
    final speed = data['speed']?.toString() ?? 'Unknown';
    final confidence = _number(data['confidence']);
    final error = data['errorType']?.toString() ?? '';
    final feedback = data['feedback']?.toString() ?? '';
    final storedRepNumber = _number(data['repNumber'])?.toInt();
    final repNumber = (storedRepNumber != null && storedRepNumber > 0)
        ? storedRepNumber
        : fallbackRepNumber;

    return Card(
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
                  child: Text(
                    'Rep $repNumber',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
                _RepMetric(label: 'FORM', value: form),
                _RepMetric(label: 'ROM', value: '${rom.toStringAsFixed(0)}°'),
                _RepMetric(label: 'SPEED', value: speed),
                _RepMetric(label: 'DURATION', value: '${duration.toStringAsFixed(1)}s'),
              ],
            ),
            if (error.isNotEmpty || feedback.isNotEmpty || confidence > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (error.isNotEmpty)
                      Text(
                        error.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    if (feedback.isNotEmpty) ...[
                      if (error.isNotEmpty) const SizedBox(height: 3),
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
                      const SizedBox(height: 5),
                      Text(
                        'AI confidence: ${confidence.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                    if ((data['doctorFeedback']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Doctor feedback', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 11)),
                      const SizedBox(height: 3),
                      Text(data['doctorFeedback'].toString(), style: TextStyle(color: Colors.grey.shade700, fontSize: 12, height: 1.35)),
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

class _SessionMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SessionMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RepMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RepMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 9, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
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
                color: primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_rounded, size: 36, color: primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'No sessions yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'Complete an assessment session and your session results will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return 'Today • $time';
  }
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} • $time';
}

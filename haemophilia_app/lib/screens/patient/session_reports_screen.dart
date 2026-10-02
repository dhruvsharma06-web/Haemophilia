import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../utils/app_localizations.dart';
import '../../utils/exercise_utils.dart';
import '../support/help_screen.dart';

class SessionReportsScreen extends StatelessWidget {
  final String patientId;
  const SessionReportsScreen({super.key, required this.patientId});
  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Session reports')),
        actions: const [LanguageToggleButton()],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('assessmentSessions')
            .where('patientId', isEqualTo: patientId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(tr('Could not load reports.')));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs =
              snap.data!.docs
                  .where(
                    (d) =>
                        d.data()['status'] == 'completed' ||
                        d.data()['status'] == 'paused',
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      ((b.data()['startedAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0)
                          .compareTo(
                            (a.data()['startedAt'] as Timestamp?)
                                    ?.millisecondsSinceEpoch ??
                                0,
                          ),
                );
          if (docs.isEmpty) {
            return Center(child: Text(tr('No session reports yet.')));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: docs
                .map((doc) => SessionReportCard(data: doc.data()))
                .toList(),
          );
        },
      ),
    );
  }
}

class SessionReportCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const SessionReportCard({super.key, required this.data});
  num _number(dynamic value) {
    final parsed = value is num ? value : num.tryParse(value?.toString() ?? "");
    return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : 0;
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final report = data['report'] is Map
        ? Map<String, dynamic>.from(data['report'])
        : <String, dynamic>{};
    final total = _number(
      report['totalReps'] ??
          data['totalReps'] ??
          data['totalCompletedReps'] ??
          data['currentRepCount'] ??
          0,
    );
    final correct = _number(
      report['correctReps'] ??
          data['totalCorrectReps'] ??
          data['completedCorrectReps'] ??
          0,
    );
    final target = _number(
      data['targetCorrectReps'] ??
          (data['exercises'] is List
              ? (data['exercises'] as List).whereType<Map>().fold<num>(
                  0,
                  (runningTotal, exercise) =>
                      runningTotal + _number(exercise['targetCorrectReps']),
                )
              : 0),
    );
    final timestamp = data['startedAt'];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['sessionName']?.toString() ?? tr('Physiotherapy Session'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            AppText(
              '${timestamp is Timestamp ? readableDate(timestamp.toDate()) : ''} · ${trStatus(data['status']?.toString())}',
            ),
            const Divider(height: 24),
            AppText('${tr('Completed Reps')}: $total'),
            AppText(
              '${tr('Correct Reps')}: $correct${target > 0 ? ' / $target' : ''}',
            ),
            AppText(
              '${tr('Correct Rep Rate')}: ${total > 0 ? (correct / total * 100).toStringAsFixed(0) : '0'}%',
            ),
            AppText(
              '${tr('Average Movement Score')}: ${report['averageScore'] is num ? (report['averageScore'] as num).toStringAsFixed(0) : tr('Not available')}',
            ),
            AppText(
              '${tr('Range of Motion')}: ${report['averageRangeOfMotion'] is num ? '${(report['averageRangeOfMotion'] as num).toStringAsFixed(0)}°' : tr('Not available')}',
            ),
            if (data['exercises'] is List) ...[
              const SizedBox(height: 12),
              for (final raw in data['exercises'] as List)
                if (raw is Map)
                  AppText(
                    '${tr(getExerciseDisplayName(raw['exercise']?.toString() ?? ''))}: ${raw['completedCorrectReps'] ?? 0} / ${raw['targetCorrectReps'] ?? 0} ${tr('Correct Reps')}',
                  ),
            ],
            const SizedBox(height: 12),
            Text(
              tr(
                'Review these results with your doctor. Movement scores and camera-based angles are prototype estimates, not clinical measurements.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

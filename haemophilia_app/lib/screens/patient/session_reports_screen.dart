import '../../services/local_test_config.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../utils/app_localizations.dart';
import '../../utils/exercise_utils.dart';
import '../../services/session_feedback_service.dart';
import '../../utils/firebase_errors.dart';
import '../support/help_screen.dart';
import '../../widgets/rep_movement_stats.dart';

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
        stream: LocalTestConfig.database
            .collection('assessmentSessions')
            .where('patientId', isEqualTo: patientId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(tr('Could not load reports.')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions =
              snapshot.data!.docs.where((doc) {
                final status = doc.data()['status'];
                return doc.data()['practice'] != true &&
                    (status == 'completed' ||
                        status == 'paused' ||
                        status == 'abandoned');
              }).toList()..sort((a, b) {
                final at = a.data()['startedAt'];
                final bt = b.data()['startedAt'];
                return (bt is Timestamp ? bt.millisecondsSinceEpoch : 0)
                    .compareTo(at is Timestamp ? at.millisecondsSinceEpoch : 0);
              });
          if (sessions.isEmpty) {
            return Center(child: Text(tr('No session reports yet.')));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final doc = sessions[index];
              return SessionReportCard(
                data: doc.data(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionReportDetail(
                      patientId: patientId,
                      sessionId: doc.id,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SessionReportCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;
  const SessionReportCard({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final time = data['completedAt'] ?? data['startedAt'];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          data['sessionName']?.toString() ?? tr('Physiotherapy Session'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${time is Timestamp ? readableDate(time.toDate()) : ''} · ${trStatus(data['status']?.toString())}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class SessionReportDetail extends StatefulWidget {
  final String patientId;
  final String sessionId;
  final Map<String, dynamic>? fallbackSession;
  final List<Map<String, dynamic>>? fallbackReps;

  const SessionReportDetail({
    super.key,
    required this.patientId,
    required this.sessionId,
    this.fallbackSession,
    this.fallbackReps,
  });

  @override
  State<SessionReportDetail> createState() => _SessionReportDetailState();
}

class _SessionReportDetailState extends State<SessionReportDetail> {
  bool detailed = false;

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Session report')),
        actions: const [LanguageToggleButton()],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: LocalTestConfig.database
            .collection('assessmentSessions')
            .doc(widget.sessionId)
            .get(),
        builder: (context, sessionSnapshot) {
          if (sessionSnapshot.hasError && widget.fallbackSession == null) {
            return Center(
              child: Text(firebaseErrorMessage(sessionSnapshot.error)),
            );
          }
          if (sessionSnapshot.connectionState != ConnectionState.done &&
              widget.fallbackSession == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final session =
              sessionSnapshot.data?.data() ??
              widget.fallbackSession ??
              <String, dynamic>{};
          return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: LocalTestConfig.database
                .collection('users')
                .doc(widget.patientId)
                .collection('assessments')
                .where('sessionId', isEqualTo: widget.sessionId)
                .get(),
            builder: (context, repSnapshot) {
              if (repSnapshot.hasError && widget.fallbackReps == null) {
                return Center(
                  child: Text(firebaseErrorMessage(repSnapshot.error)),
                );
              }
              if (repSnapshot.connectionState != ConnectionState.done &&
                  widget.fallbackReps == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final reps =
                  repSnapshot.data?.docs.map((doc) => doc.data()).toList() ??
                  widget.fallbackReps ??
                  <Map<String, dynamic>>[];
              final report = _Report(session, reps);
              final feedback = generateSessionFeedback(
                total: report.total,
                correct: report.correct,
                target: report.target,
                status: session['status']?.toString() ?? '',
                issues: report.issueCounts,
                exercises: {
                  for (final e in report.byExercise.entries)
                    tr(getExerciseDisplayName(e.key)): e.value,
                },
                hindi: AppLocaleService.currentLocale.value == 'hi',
              );
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    session['sessionName']?.toString() ??
                        tr('Physiotherapy Session'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(tr('Brief report')),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(tr('Detailed report')),
                      ),
                    ],
                    selected: {detailed},
                    onSelectionChanged: (selection) =>
                        setState(() => detailed = selection.first),
                  ),
                  const SizedBox(height: 20),
                  _ReportSection(
                    title: tr('Automated session feedback'),
                    children: [Text(feedback.brief)],
                  ),
                  if (detailed) ...[
                    const SizedBox(height: 12),
                    _ReportSection(
                      title: tr('Rep-by-rep review'),
                      children: [
                        for (final rep in reps)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              '${tr('Rep')} ${rep['repNumber'] ?? '—'} · ${tr(getExerciseDisplayName(rep['exercise']?.toString() ?? ''))}',
                            ),
                            subtitle: Text(
                              tr(rep['form']?.toString() ?? 'Unknown'),
                            ),
                            children: [
                              RepMovementStats(rep: rep),
                              if ((rep['feedback']?.toString() ?? '')
                                  .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Text(tr(rep['feedback'].toString())),
                                ),
                              if ((rep['errorFrameUrl']?.toString() ?? '')
                                  .isNotEmpty)
                                Image.network(
                                  rep['errorFrameUrl'].toString(),
                                  height: 180,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, error, stack) =>
                                      Text(tr('Error image unavailable.')),
                                ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ReportSection(
                      title: tr('For the patient'),
                      children: [
                        for (final text in feedback.patientDetails)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(text),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ReportSection(
                      title: tr('For your doctor'),
                      children: [
                        for (final text in feedback.doctorDetails)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(text),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _ReportSection(
                    title: tr('Recorded activity'),
                    children: [
                      _ReportLine(tr('Completed Reps'), '${report.total}'),
                      _ReportLine(
                        tr('Recorded correctly'),
                        '${report.correct}',
                      ),
                      if (report.target > 0)
                        _ReportLine(
                          tr('Session target'),
                          '${report.target} ${tr('Correct Reps')}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ReportSection(
                    title: tr('Form feedback'),
                    children: [
                      Text(
                        report.total == 0
                            ? tr(
                                'No completed repetitions were recorded for this session.',
                              )
                            : report.incorrect == 0
                            ? tr(
                                'The camera marked all recorded repetitions as correct.',
                              )
                            : tr(
                                'The camera marked some repetitions as needing adjustment. Review the details with your doctor.',
                              ),
                      ),
                      if (report.total > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${tr('Correct Rep Rate')}: ${(report.correct / report.total * 100).toStringAsFixed(0)}%',
                          ),
                        ),
                    ],
                  ),
                  if (detailed) ...[
                    const SizedBox(height: 12),
                    _ReportSection(
                      title: tr('Detailed report'),
                      children: [
                        _ReportLine(
                          tr('Recorded with adjustment needed'),
                          '${report.incorrect}',
                        ),
                        for (final entry in report.byExercise.entries)
                          _ReportLine(
                            tr(getExerciseDisplayName(entry.key)),
                            '${entry.value.$1}/${entry.value.$2} ${tr('Correct Reps')}',
                          ),
                        if (report.issueCounts.isEmpty)
                          Text(tr('No form issues were recorded.')),
                        for (final entry in report.issueCounts.entries)
                          _ReportLine(entry.key, '${entry.value}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ReportSection(
                      title: tr('Camera estimates'),
                      children: [
                        _ReportLine(
                          tr('Average Movement Score'),
                          report.averageScore == null
                              ? tr('Not available')
                              : report.averageScore!.toStringAsFixed(0),
                        ),
                        _ReportLine(
                          tr('Range of Motion'),
                          report.averageRom == null
                              ? tr('Not available')
                              : '${report.averageRom!.toStringAsFixed(0)}°',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ReportSection(
                      title: tr('For your doctor'),
                      children: [
                        Text(
                          tr(
                            'Discuss any pain, swelling, or bleeding with your care team before continuing exercise.',
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    tr(
                      'This report summarizes recorded activity; it does not diagnose a condition or replace your doctor’s assessment.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Report {
  final int total;
  final int correct;
  final int target;
  final Map<String, (int, int)> byExercise;
  final Map<String, int> issueCounts;
  final double? averageScore;
  final double? averageRom;
  int get incorrect => total - correct;

  factory _Report(
    Map<String, dynamic> session,
    List<Map<String, dynamic>> rawReps,
  ) {
    final seen = <String>{};
    final reps = rawReps.where((rep) {
      final number = rep['repNumber']?.toString() ?? '';
      final key = '${rep['exercise']}:$number';
      return number.isEmpty || seen.add(key);
    }).toList();
    final byExercise = <String, (int, int)>{};
    final issues = <String, int>{};
    final scores = <double>[];
    final roms = <double>[];
    var correct = 0;
    for (final rep in reps) {
      final exercise = rep['exercise']?.toString() ?? 'Exercise';
      final form = rep['form']?.toString().toLowerCase() ?? '';
      final good = form.contains('correct') && !form.contains('incorrect');
      if (good) correct++;
      final previous = byExercise[exercise] ?? (0, 0);
      byExercise[exercise] = (previous.$1 + (good ? 1 : 0), previous.$2 + 1);
      final issue = rep['errorType']?.toString().trim() ?? '';
      if (!good && issue.isNotEmpty && issue.toLowerCase() != 'none') {
        issues[issue] = (issues[issue] ?? 0) + 1;
      }
      final score = _number(rep['score']);
      final rom = _number(rep['rangeOfMotion']);
      if (score != null) scores.add(score);
      if (rom != null) roms.add(rom);
    }
    final exercises = session['exercises'];
    var target = 0;
    if (exercises is List) {
      for (final item in exercises) {
        if (item is Map) {
          target += (_number(item['targetCorrectReps']) ?? 0).toInt();
        }
      }
    }
    target = target > 0
        ? target
        : (_number(session['targetCorrectReps']) ?? 0).toInt();
    final stored = session['report'] is Map ? session['report'] as Map : {};
    final savedTotal =
        (_number(
                  session['totalReps'] ??
                      session['totalCompletedReps'] ??
                      stored['totalReps'],
                ) ??
                0)
            .toInt();
    final savedCorrect =
        (_number(
                  session['totalCorrectReps'] ??
                      session['completedCorrectReps'] ??
                      stored['correctReps'],
                ) ??
                0)
            .toInt();
    final total = reps.isEmpty ? savedTotal : reps.length;
    final correctTotal = reps.isEmpty ? savedCorrect.clamp(0, total) : correct;
    return _Report._(
      total,
      correctTotal,
      target,
      byExercise,
      issues,
      scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length,
      roms.isEmpty ? null : roms.reduce((a, b) => a + b) / roms.length,
    );
  }

  const _Report._(
    this.total,
    this.correct,
    this.target,
    this.byExercise,
    this.issueCounts,
    this.averageScore,
    this.averageRom,
  );
  static double? _number(dynamic value) {
    final result = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return result != null && result.isFinite && result >= 0 ? result : null;
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _ReportSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class _ReportLine extends StatelessWidget {
  final String label;
  final String value;
  const _ReportLine(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(child: Text(value, textAlign: TextAlign.end, softWrap: true)),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../patient/patient_history.dart';
import '../../utils/exercise_utils.dart';

class DoctorSessionDetail extends StatelessWidget {
  final String patientId;
  final UserModel patient;
  final AssessmentSession session;

  const DoctorSessionDetail({
    super.key,
    required this.patientId,
    required this.patient,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final rate = session.reps == 0
        ? 0.0
        : (session.correctReps / session.reps) * 100;

    // Keep the doctor's review chronological.
    // Prefer the actual backend rep number when available.
    final orderedReps =
        List<Map<String, dynamic>>.from(
      session.repsData,
    );

    orderedReps.sort((a, b) {
      final aNumber = _toInt(
        a['rep_number'] ??
            a['repNumber'] ??
            a['rep'],
      );

      final bNumber = _toInt(
        b['rep_number'] ??
            b['repNumber'] ??
            b['rep'],
      );

      return aNumber.compareTo(bNumber);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Session review',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          12,
          20,
          32,
        ),
        children: [
          // Doctor-assigned session name.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  session.sessionName,
                  style: const TextStyle(
                    fontSize: 22,
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
            const SizedBox(height: 4),
            Text(
              '${getExerciseDisplayName(session.exercise)} • Work in progress exercise',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 4),

          Text(
            '${patient.name} • ${_date(session.date)}',
            style: TextStyle(
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 18),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Stat(
                'Average score',
                '${session.averageScore.toStringAsFixed(0)}/100',
              ),
              _Stat(
                'Correct reps',
                '${session.correctReps}/${session.reps}',
              ),
              _Stat(
                'Success rate',
                '${rate.toStringAsFixed(0)}%',
              ),
              _Stat(
                'Average ROM',
                '${session.averageRom.toStringAsFixed(0)}°',
              ),
              _Stat(
                'Avg duration',
                '${session.averageDuration.toStringAsFixed(1)}s',
              ),
              _Stat(
                'AI confidence',
                '${session.averageConfidence.toStringAsFixed(1)}%',
              ),
            ],
          ),

          const SizedBox(height: 26),

          const Text(
            'Rep-by-rep review',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 12),

          ...orderedReps.asMap().entries.map(
            (entry) {
              final rep = entry.value;

              final actualRepNumber = _toInt(
                rep['rep_number'] ??
                    rep['repNumber'] ??
                    rep['rep'],
              );

              final displayNumber =
                  actualRepNumber > 0
                      ? actualRepNumber
                      : entry.key + 1;

              return _RepReview(
                rep: rep,
                number: displayNumber,
              );
            },
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) {
    final x = d.toLocal();

    return '${x.day.toString().padLeft(2, '0')}/'
        '${x.month.toString().padLeft(2, '0')}/'
        '${x.year} • '
        '${x.hour.toString().padLeft(2, '0')}:'
        '${x.minute.toString().padLeft(2, '0')}';
  }
}

class _RepReview extends StatelessWidget {
  final Map<String, dynamic> rep;
  final int number;

  const _RepReview({
    required this.rep,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    final d = rep;

    final form =
        d['form']?.toString() ?? 'Unknown';

    final incorrect =
        form.toLowerCase().contains('incorrect');

    final primary =
        Theme.of(context).colorScheme.primary;

    final url =
        d['errorFrameUrl']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  incorrect
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: incorrect
                      ? Colors.red.shade600
                      : primary,
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: Text(
                    'Rep $number • $form',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),

                Text(
                  '${_num(d['score']).toStringAsFixed(0)}/100',
                  style: TextStyle(
                    color: incorrect
                        ? Colors.red.shade700
                        : primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                _M(
                  'ROM',
                  '${_num(d['rangeOfMotion']).toStringAsFixed(0)}°',
                ),
                _M(
                  'SPEED',
                  d['speed']?.toString() ?? '—',
                ),
                _M(
                  'DURATION',
                  '${_num(d['duration']).toStringAsFixed(1)}s',
                ),
                _M(
                  'AI',
                  '${_num(d['confidence']).toStringAsFixed(1)}%',
                ),
              ],
            ),

            if (incorrect && url.isNotEmpty) ...[
              const SizedBox(height: 13),

              ClipRRect(
                borderRadius:
                    BorderRadius.circular(14),
                child: GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(
                            url,
                            errorBuilder:
                                (_, __, ___) {
                              return const Padding(
                                padding:
                                    EdgeInsets.all(30),
                                child: Text(
                                  'Error image unavailable.',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  child: Image.network(
                    url,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) {
                      return Container(
                        height: 120,
                        color:
                            Colors.grey.shade100,
                        alignment:
                            Alignment.center,
                        child: const Text(
                          'Error image unavailable.',
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],

            if (incorrect) ...[
              const SizedBox(height: 13),

              Text(
                d['errorType']
                        ?.toString()
                        .replaceAll('_', ' ')
                        .toUpperCase() ??
                    '',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                d['feedback']?.toString() ?? '',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double _num(dynamic value) {
    return value is num
        ? value.toDouble()
        : double.tryParse(
              value?.toString() ?? '',
            ) ??
            0;
  }
}

class _M extends StatelessWidget {
  final String l;
  final String v;

  const _M(
    this.l,
    this.v,
  );

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            l,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            v,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String l;
  final String v;

  const _Stat(
    this.l,
    this.v,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                v,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                l,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _toInt(dynamic value) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      0;
}
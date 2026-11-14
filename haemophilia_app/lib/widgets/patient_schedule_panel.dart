import '../services/local_test_config.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/app_localizations.dart';
import '../utils/firebase_errors.dart';
import '../utils/schedule_utils.dart';
import '../screens/support/help_screen.dart';

class PatientSchedulePanel extends StatelessWidget {
  final String patientId;
  final Future<void> Function() onScheduleChanged;
  const PatientSchedulePanel({
    super.key,
    required this.patientId,
    required this.onScheduleChanged,
  });

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: LocalTestConfig.database
        .collection('exerciseScheduleSeries')
        .where('patientId', isEqualTo: patientId)
        .snapshots(),
    builder: (context, series) {
      if (series.hasError) return Text(firebaseErrorMessage(series.error));
      if (!series.hasData) return const LinearProgressIndicator();
      final ready = series.data!.docs
          .where((d) => d.data()['status'] == 'ready')
          .map((d) => d.id)
          .toSet();
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: LocalTestConfig.database
            .collection('exerciseSchedules')
            .where('patientId', isEqualTo: patientId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(firebaseErrorMessage(snapshot.error));
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) onScheduleChanged();
          });
          final now = DateTime.now();
          final docs =
              snapshot.data!.docs.where((doc) {
                final d = doc.data();
                return d['scheduledAt'] is Timestamp &&
                    (d['managedSeries'] != true ||
                        ready.contains(d['seriesId']));
              }).toList()..sort(
                (a, b) => (a.data()['scheduledAt'] as Timestamp).compareTo(
                  b.data()['scheduledAt'] as Timestamp,
                ),
              );
          final upcoming = docs
              .where(
                (doc) =>
                    doc.data()['status'] == 'scheduled' &&
                    doc.data()['expiresAt'] is Timestamp &&
                    sessionExpiry(doc.data())!.isAfter(now),
              )
              .toList();
          final previous = docs
              .where(
                (doc) =>
                    !upcoming.contains(doc) &&
                    doc.data()['status'] == 'activated' &&
                    sessionExpiry(doc.data())?.isAfter(now) == true,
              )
              .toList()
              .reversed
              .take(20)
              .toList();
          Widget tile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
            final d = doc.data();
            final date = (d['scheduledAt'] as Timestamp).toDate();
            final expired =
                d['status'] == 'missed' ||
                (d['status'] == 'scheduled' &&
                    d['expiresAt'] is Timestamp &&
                    !sessionExpiry(d)!.isAfter(now));
            final label = expired
                ? 'Expired'
                : d['status'] == 'cancelled'
                ? 'Cancelled'
                : d['status'] == 'activated'
                ? 'Previous session'
                : date.isAfter(now)
                ? 'Upcoming'
                : 'Available';
            return ListTile(
              isThreeLine: true,
              leading: Icon(expired ? Icons.event_busy : Icons.event_note),
              title: Text(
                d['sessionName']?.toString() ?? tr('Physiotherapy Session'),
              ),
              subtitle: Text(
                '${readableDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}\n${tr(label)}',
              ),
              trailing:
                  d['status'] == 'scheduled' && !expired && !date.isAfter(now)
                  ? IconButton(
                      tooltip: tr('Refresh'),
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        try {
                          await onScheduleChanged();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(firebaseErrorMessage(e))),
                            );
                          }
                        }
                      },
                    )
                  : null,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (upcoming.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: Text(tr('Scheduled sessions')),
                    subtitle: Text(
                      tr('Sessions become available at their scheduled time.'),
                    ),
                    children: upcoming.take(20).map(tile).toList(),
                  ),
                ),
              if (previous.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    title: Text(tr('Previous sessions')),
                    children: previous.map(tile).toList(),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

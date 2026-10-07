import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/local_test_config.dart';
import '../utils/app_localizations.dart';
import '../utils/firebase_errors.dart';
import '../utils/schedule_utils.dart';

/// Terminal assignments remain discoverable after the next occurrence replaces
/// the patient's single current-assignment document.
class ExpiredSessionsPanel extends StatelessWidget {
  final String patientId;
  const ExpiredSessionsPanel({super.key, required this.patientId});
  @override
  Widget build(BuildContext context) {
    final db = LocalTestConfig.database;
    final ref = db.collection('exerciseAssignments').doc(patientId);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.collection('archive').snapshots(),
      builder: (context, archived) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, current) =>
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db
                      .collection('exerciseSchedules')
                      .where('patientId', isEqualTo: patientId)
                      .snapshots(),
                  builder: (context, scheduled) {
                    final error =
                        archived.error ?? current.error ?? scheduled.error;
                    if (error != null) return Text(firebaseErrorMessage(error));
                    final records = <String, Map<String, dynamic>>{};
                    for (final doc
                        in scheduled.data?.docs ??
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                      final d = doc.data();
                      if (d['status'] == 'missed' ||
                          d['status'] == 'expired' ||
                          d['status'] == 'cancelled' ||
                          (d['status'] == 'scheduled' &&
                              sessionExpiry(d) != null &&
                              !DateTime.now().isBefore(sessionExpiry(d)!))) {
                        records[doc.id] = {
                          ...d,
                          'status': d['status'] == 'cancelled'
                              ? 'cancelled'
                              : 'expired',
                        };
                      }
                    }
                    for (final doc
                        in archived.data?.docs ??
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                      records[doc.id] = doc.data();
                    }
                    final active = current.data?.data();
                    if (active != null &&
                        (sessionExpired(active, DateTime.now()) ||
                            active['status'] == 'cancelled')) {
                      records[assignmentKey(active)] = {
                        ...active,
                        'status': active['status'] == 'cancelled'
                            ? 'cancelled'
                            : 'expired',
                      };
                    }
                    Widget group(String status, String title) {
                      final rows =
                          records.values
                              .where((d) => d['status'] == status)
                              .toList()
                            ..sort(
                              (a, b) => (sessionExpiry(b) ?? DateTime(1970))
                                  .compareTo(
                                    sessionExpiry(a) ?? DateTime(1970),
                                  ),
                            );
                      if (rows.isEmpty) return const SizedBox.shrink();
                      return Card(
                        child: ExpansionTile(
                          title: Text(tr(title)),
                          children: rows.take(50).map((d) {
                            final date = sessionDate(
                              d['scheduledAt'] ?? d['createdAt'],
                            );
                            return ListTile(
                              leading: Icon(
                                status == 'expired'
                                    ? Icons.event_busy
                                    : Icons.cancel_outlined,
                              ),
                              title: Text(
                                d['sessionName']?.toString() ??
                                    tr('Physiotherapy Session'),
                              ),
                              subtitle: Text(
                                '${date == null ? '' : '${date.day}/${date.month}/${date.year} · ${TimeOfDay.fromDateTime(date).format(context)}\n'}${tr(status == 'expired' ? 'Expired' : 'Cancelled')}',
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        group('expired', 'Expired sessions'),
                        group('cancelled', 'Cancelled sessions'),
                      ],
                    );
                  },
                ),
          ),
    );
  }
}

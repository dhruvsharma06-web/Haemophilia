import 'package:cloud_firestore/cloud_firestore.dart';

import 'local_test_config.dart';
import '../utils/schedule_utils.dart';

/// Atomic terminal transitions prevent cancellation/expiry from being undone
/// by queued recording writes or by a newly assigned occurrence.
class SessionLifecycleService {
  final _db = LocalTestConfig.database;

  Future<void> expire(String patientId) => _finish(patientId, 'expired');

  Future<void> cancel(String patientId, {required String expectedKey}) =>
      _finish(patientId, 'cancelled', expectedKey: expectedKey);

  Future<void> _finish(
    String patientId,
    String status, {
    String? expectedKey,
  }) async {
    final ref = _db.collection('exerciseAssignments').doc(patientId);
    await _db.runTransaction((tx) async {
      final current = await tx.get(ref);
      final data = current.data();
      if (data == null || !unfinishedSessionStatuses.contains(data['status'])) {
        return;
      }
      if (expectedKey != null && assignmentKey(data) != expectedKey) {
        throw StateError('The session changed. Refresh and try again.');
      }
      if (status == 'expired' && !sessionExpired(data, DateTime.now())) return;
      final key = assignmentKey(data);
      final archive = ref.collection('archive').doc(key);
      final archived = await tx.get(archive);
      final sessionId = data['sessionId']?.toString();
      final session = sessionId == null || sessionId.isEmpty
          ? null
          : await tx.get(_db.collection('assessmentSessions').doc(sessionId));
      final scheduleId = (data['scheduleId'] ?? data['sourceScheduleId'])
          ?.toString();
      final schedule = scheduleId == null || scheduleId.isEmpty
          ? null
          : await tx.get(_db.collection('exerciseSchedules').doc(scheduleId));
      final terminal = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'expired') 'expiredAt': FieldValue.serverTimestamp(),
        if (status == 'cancelled') ...{
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': LocalTestConfig.auth.currentUser!.uid,
        },
      };
      if (!archived.exists) {
        tx.set(archive, {
          ...data,
          ...terminal,
          'patientId': patientId,
          'archiveId': key,
          'archivedAt': FieldValue.serverTimestamp(),
        });
      }
      tx.update(ref, terminal);
      if (session != null &&
          session.exists &&
          unfinishedSessionStatuses.contains(session.data()?['status'])) {
        tx.update(session.reference, {
          ...terminal,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (schedule != null &&
          schedule.exists &&
          ['scheduled', 'activated'].contains(schedule.data()?['status'])) {
        tx.update(schedule.reference, {
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}

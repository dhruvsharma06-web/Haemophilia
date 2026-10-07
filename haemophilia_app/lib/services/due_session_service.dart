import 'local_test_config.dart';
import '../utils/schedule_utils.dart';
import 'session_lifecycle_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Activates only a doctor's published, due occurrence. Security rules verify
/// the immutable schedule payload and the atomic activation, even offline.
class DueSessionService {
  final _db = LocalTestConfig.database;

  Future<void> activate(String patientId) async {
    await SessionLifecycleService().expire(patientId);
    final snapshot = await _db
        .collection('exerciseSchedules')
        .where('patientId', isEqualTo: patientId)
        .get();
    final now = DateTime.now();
    final due =
        snapshot.docs.where((doc) {
          final d = doc.data();
          return d['status'] == 'scheduled' &&
              d['scheduledAt'] is Timestamp &&
              d['expiresAt'] is Timestamp &&
              !now.isBefore((d['scheduledAt'] as Timestamp).toDate()) &&
              now.isBefore(sessionExpiry(d)!);
        }).toList()..sort(
          (a, b) => (a.data()['scheduledAt'] as Timestamp).compareTo(
            b.data()['scheduledAt'] as Timestamp,
          ),
        );
    for (final candidate in due) {
      final activated = await _db.runTransaction((tx) async {
        final schedule = await tx.get(candidate.reference);
        final d = schedule.data();
        final currentTime = DateTime.now();
        if (d == null ||
            d['status'] != 'scheduled' ||
            sessionExpiry(d) == null ||
            !currentTime.isBefore(sessionExpiry(d)!) ||
            (d['scheduledAt'] as Timestamp).toDate().isAfter(currentTime)) {
          return false;
        }
        final patient = await tx.get(_db.collection('users').doc(patientId));
        final doctorId = d['doctorId']?.toString() ?? '';
        if (doctorId.isEmpty ||
            patient.data()?['doctorId'] != doctorId ||
            patient.data()?['accountActive'] == false) {
          return false;
        }
        final doctor = await tx.get(_db.collection('users').doc(doctorId));
        if (doctor.data()?['role'] != 'doctor' ||
            doctor.data()?['isApproved'] == false ||
            doctor.data()?['accountActive'] == false) {
          return false;
        }
        if (d['managedSeries'] == true) {
          final series = await tx.get(
            _db
                .collection('exerciseScheduleSeries')
                .doc(d['seriesId'].toString()),
          );
          if (series.data()?['status'] != 'ready') return false;
        }
        final ref = _db.collection('exerciseAssignments').doc(patientId);
        final current = await tx.get(ref);
        final old = current.data();
        if (old != null && unfinishedSessionStatuses.contains(old['status'])) {
          return false;
        }
        tx.set(ref, {
          'patientId': patientId,
          'doctorId': doctorId,
          'sourceScheduleId': candidate.id,
          'scheduleId': candidate.id,
          'sessionName': d['sessionName'],
          'exercises': d['exercises'],
          'exerciseProgress': d['exerciseProgress'],
          'scheduledAt': d['scheduledAt'],
          'expiresAt': d['expiresAt'],
          'status': 'assigned',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(candidate.reference, {
          'status': 'activated',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          _db
              .collection('users')
              .doc(patientId)
              .collection('notifications')
              .doc('schedule_${candidate.id}'),
          {
            'senderId': patientId,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
            'title': 'Exercise session available',
            'body': 'Open the app to view your scheduled session.',
            'data': {
              'type': 'session_assigned',
              'patientId': patientId,
              'doctorId': doctorId,
              'scheduleId': candidate.id,
            },
          },
        );
        return true;
      });
      if (activated) break;
    }
  }
}

import 'local_test_config.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/schedule_utils.dart';
import 'session_lifecycle_service.dart';

/// A series becomes visible to the scheduler only after all of its occurrences
/// have been saved. Chunking supports long plans with several sessions per day.
class ExerciseScheduleService {
  final FirebaseFirestore _db = LocalTestConfig.database;

  Future<void> cancelSession(String patientId, String expectedKey) =>
      SessionLifecycleService().cancel(patientId, expectedKey: expectedKey);

  Future<void> assignNow({
    required String patientId,
    required String doctorId,
    required String sessionName,
    required List<Map<String, dynamic>> exercises,
    required List<Map<String, dynamic>> exerciseProgress,
  }) async {
    await SessionLifecycleService().expire(patientId);
    final assignmentId = _db.collection('exerciseAssignments').doc().id;
    final ref = _db.collection('exerciseAssignments').doc(patientId);
    await _db.runTransaction((tx) async {
      final patient = await tx.get(_db.collection('users').doc(patientId));
      final doctor = await tx.get(_db.collection('users').doc(doctorId));
      final current = await tx.get(ref);
      if (patient.data()?['doctorId'] != doctorId ||
          patient.data()?['accountActive'] == false ||
          doctor.data()?['role'] != 'doctor' ||
          doctor.data()?['isApproved'] == false ||
          doctor.data()?['accountActive'] == false) {
        throw StateError('Select an active patient assigned to you.');
      }
      final status = current.data()?['status'];
      if (unfinishedSessionStatuses.contains(status)) {
        throw StateError(
          'Complete or cancel the current session before assigning another.',
        );
      }
      tx.set(ref, {
        'assignmentId': assignmentId,
        'patientId': patientId,
        'doctorId': doctorId,
        'sessionName': sessionName,
        'exercises': exercises,
        'exerciseProgress': exerciseProgress,
        'status': 'assigned',
        'scheduledAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      });
      tx.set(
        _db
            .collection('users')
            .doc(patientId)
            .collection('notifications')
            .doc('assignment_$assignmentId'),
        {
          'senderId': doctorId,
          'read': false,
          'title': 'Exercise session available',
          'body': 'Open the app to view your scheduled session.',
          'createdAt': FieldValue.serverTimestamp(),
          'data': {
            'type': 'session_assigned',
            'patientId': patientId,
            'doctorId': doctorId,
            'assignmentId': assignmentId,
          },
        },
      );
    });
  }

  Future<void> save({
    required String patientId,
    required String doctorId,
    required String sessionName,
    required List<DateTime> dates,
    required List<Map<String, dynamic>> exercises,
    required List<Map<String, dynamic>> exerciseProgress,
    String? replacedScheduleId,
  }) async {
    if (dates.isEmpty || dates.length > 4392) {
      throw StateError('Select at least one scheduled day.');
    }
    final series = _db.collection('exerciseScheduleSeries').doc();
    await series.set({
      'patientId': patientId,
      'doctorId': doctorId,
      'status': 'preparing',
      'occurrenceCount': dates.length,
      'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      for (var offset = 0; offset < dates.length; offset += 400) {
        final batch = _db.batch();
        for (
          var index = offset;
          index < dates.length && index < offset + 400;
          index++
        ) {
          final date = dates[index];
          final expiry = date.add(const Duration(hours: 1));
          batch.set(_db.collection('exerciseSchedules').doc(), {
            'patientId': patientId,
            'doctorId': doctorId,
            'seriesId': series.id,
            'managedSeries': true,
            'sessionName': sessionName,
            'exercises': exercises,
            'exerciseProgress': exerciseProgress,
            'scheduledAt': Timestamp.fromDate(date),
            'expiresAt': Timestamp.fromDate(expiry),
            'timezoneOffsetMinutes': date.timeZoneOffset.inMinutes,
            'status': 'scheduled',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      await _db.runTransaction((transaction) async {
        DocumentReference<Map<String, dynamic>>? replaced;
        if (replacedScheduleId != null) {
          replaced = _db
              .collection('exerciseSchedules')
              .doc(replacedScheduleId);
          final existing = await transaction.get(replaced);
          if (existing.data()?['status'] != 'scheduled') {
            throw StateError('This occurrence is already active or cancelled.');
          }
        }
        transaction.update(series, {
          'status': 'ready',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (replaced != null) {
          transaction.update(replaced, {
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      // If cancellation cannot be sent while offline, the unpublished series
      // remains inert. A partial save must never notify or assign a patient.
      try {
        await series.update({
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> cancelSeries(String seriesId) =>
      _db.collection('exerciseScheduleSeries').doc(seriesId).update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

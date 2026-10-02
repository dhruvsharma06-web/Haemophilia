import 'package:cloud_firestore/cloud_firestore.dart';

/// A series becomes visible to the scheduler only after all of its occurrences
/// have been saved. Chunking supports long plans with several sessions per day.
class ExerciseScheduleService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
      'patientId': patientId, 'doctorId': doctorId, 'status': 'preparing',
      'occurrenceCount': dates.length, 'createdAt': FieldValue.serverTimestamp(),
    });
    try {
      for (var offset = 0; offset < dates.length; offset += 400) {
        final batch = _db.batch();
        for (final date in dates.skip(offset).take(400)) {
          batch.set(_db.collection('exerciseSchedules').doc(), {
            'patientId': patientId, 'doctorId': doctorId, 'seriesId': series.id,
            'managedSeries': true, 'sessionName': sessionName, 'exercises': exercises,
            'exerciseProgress': exerciseProgress, 'scheduledAt': Timestamp.fromDate(date),
            'expiresAt': Timestamp.fromDate(DateTime(date.year, date.month, date.day + 1)),
            'timezoneOffsetMinutes': date.timeZoneOffset.inMinutes,
            'status': 'scheduled', 'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      await _db.runTransaction((transaction) async {
        DocumentReference<Map<String, dynamic>>? replaced;
        if (replacedScheduleId != null) {
          replaced = _db.collection('exerciseSchedules').doc(replacedScheduleId);
          final existing = await transaction.get(replaced);
          if (existing.data()?['status'] != 'scheduled') {
            throw StateError('This occurrence is already active or cancelled.');
          }
        }
        transaction.update(series, {'status': 'ready', 'updatedAt': FieldValue.serverTimestamp()});
        if (replaced != null) {
          transaction.update(replaced, {'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()});
        }
      });
    } catch (_) {
      // If cancellation cannot be sent while offline, the unpublished series
      // remains inert. A partial save must never notify or assign a patient.
      try { await series.update({'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()}); } catch (_) {}
      rethrow;
    }
  }

  Future<void> cancelSeries(String seriesId) => _db.collection('exerciseScheduleSeries').doc(seriesId).update({
    'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp(),
  });
}

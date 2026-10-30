/// Local calendar dates preserve the selected wall-clock time across DST changes.
List<DateTime> scheduledOccurrences({
  required DateTime start,
  required int days,
  required Set<int> weekdays,
  List<int>? timesOfDayMinutes,
}) {
  final times = (timesOfDayMinutes ?? [start.hour * 60 + start.minute]).toList()
    ..sort();
  if (days < 1 ||
      days > 366 ||
      weekdays.isEmpty ||
      weekdays.any((day) => day < 1 || day > 7) ||
      times.isEmpty ||
      times.length > 12 ||
      times.toSet().length != times.length ||
      times.any((minute) => minute < 0 || minute >= 1440)) {
    throw ArgumentError(
      'Select 1–366 days, at least one weekday and unique daily session times.',
    );
  }
  return [
        for (var i = 0; i < days; i++)
          for (final minute in times)
            DateTime(
              start.year,
              start.month,
              start.day + i,
              minute ~/ 60,
              minute % 60,
            ),
      ]
      .where((date) => weekdays.contains(date.weekday) && !date.isBefore(start))
      .toList();
}

const sessionAvailability = Duration(hours: 1);
const unfinishedSessionStatuses = {
  'assigned',
  'active',
  'paused',
  'in_progress',
};

DateTime? sessionDate(dynamic value) {
  if (value is DateTime) return value;
  try {
    final date = value?.toDate();
    return date is DateTime ? date : null;
  } catch (_) {
    return null;
  }
}

/// Every unfinished assignment uses its original scheduled start, never a
/// resume/update time. Legacy records fall back to their original creation time.
DateTime? sessionExpiry(Map<String, dynamic> data) {
  final start = sessionDate(
    data['scheduledAt'] ?? data['createdAt'] ?? data['startedAt'],
  );
  final stored = sessionDate(data['expiresAt']);
  if (start == null) return stored;
  final limit = start.add(sessionAvailability);
  return stored != null && stored.isBefore(limit) ? stored : limit;
}

bool assignmentAvailable(Map<String, dynamic> data, DateTime now) {
  if (!unfinishedSessionStatuses.contains(data['status'])) return false;
  final start = sessionDate(data['scheduledAt']);
  final end = sessionExpiry(data);
  return end != null &&
      (start == null || !now.isBefore(start)) &&
      now.isBefore(end);
}

String assignmentKey(Map<String, dynamic> data) {
  final id =
      data['assignmentId'] ?? data['scheduleId'] ?? data['sourceScheduleId'];
  if (id != null) return id.toString();
  final start = sessionDate(data['scheduledAt'] ?? data['createdAt']);
  if (start != null) return 'legacy_${start.microsecondsSinceEpoch}';
  return (data['sessionId'] ?? 'legacy').toString();
}

bool sessionExpired(Map<String, dynamic> data, DateTime now) =>
    data['status'] == 'expired' ||
    data['status'] == 'missed' ||
    (unfinishedSessionStatuses.contains(data['status']) &&
        (sessionExpiry(data) == null || !now.isBefore(sessionExpiry(data)!)));

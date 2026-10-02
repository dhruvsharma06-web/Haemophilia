/// Local calendar dates preserve the selected wall-clock time across DST changes.
List<DateTime> scheduledOccurrences({
  required DateTime start,
  required int days,
  required Set<int> weekdays,
  List<int>? timesOfDayMinutes,
}) {
  final times = (timesOfDayMinutes ?? [start.hour * 60 + start.minute]).toList()..sort();
  if (days < 1 || days > 366 || weekdays.isEmpty || weekdays.any((day) => day < 1 || day > 7)
      || times.isEmpty || times.length > 12 || times.toSet().length != times.length
      || times.any((minute) => minute < 0 || minute >= 1440)) {
    throw ArgumentError('Select 1–366 days, at least one weekday and unique daily session times.');
  }
  return [
    for (var i = 0; i < days; i++)
      for (final minute in times)
        DateTime(start.year, start.month, start.day + i, minute ~/ 60, minute % 60),
  ].where((date) => weekdays.contains(date.weekday) && !date.isBefore(start)).toList();
}

bool assignmentAvailable(Map<String, dynamic> data, DateTime now) {
  final status = data['status'];
  if (status == 'paused' || status == 'in_progress') return true;
  if (status != 'assigned') return false;
  final start = data['scheduledAt'];
  final end = data['expiresAt'];
  return (start == null || !now.isBefore(start.toDate())) &&
      (end == null || now.isBefore(end.toDate()));
}

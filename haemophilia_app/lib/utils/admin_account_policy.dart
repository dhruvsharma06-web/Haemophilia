const userFilters = {
  'all': 'All users',
  'patient': 'Assigned patients',
  'pending_patient': 'Unassigned patients',
  'doctor': 'Doctors',
  'pending_doctor': 'Pending doctors',
  'admin': 'Admins',
};

String managedRoleLabel(String role) => switch (role) {
  'patient' => 'Patient',
  'doctor' => 'Doctor',
  'pending_doctor' => 'Pending doctor',
  'admin' => 'Admin',
  _ => role,
};

List<String> allowedManagedRoles(String role) => switch (role) {
  'doctor' || 'pending_doctor' => ['pending_doctor', 'doctor'],
  'patient' => ['patient'],
  'admin' => ['admin'],
  _ => [],
};

bool countsAsActiveUser(Map<String, dynamic> data) =>
    data['accountActive'] != false &&
    !const {'inactive', 'rejected', 'removed'}.contains(data['status']);

({int doctors, int patients, int total}) adminUserCounts(
  Iterable<Map<String, dynamic>> users,
) {
  var doctors = 0;
  var patients = 0;
  var total = 0;
  for (final user in users.where(countsAsActiveUser)) {
    total++;
    if (matchesUserFilter(user, 'doctor')) doctors++;
    if (user['role'] == 'patient') patients++;
  }
  return (doctors: doctors, patients: patients, total: total);
}

bool matchesUserFilter(Map<String, dynamic> data, String filter) {
  if (filter == 'all') return true;
  final pendingDoctor =
      data['role'] == 'pending_doctor' ||
      (data['role'] == 'doctor' && data['isApproved'] == false);
  if (filter == 'pending_doctor') return pendingDoctor;
  if (filter == 'doctor') return data['role'] == 'doctor' && !pendingDoctor;
  if (filter == 'pending_patient') {
    return data['role'] == 'patient' &&
        (data['doctorId']?.toString().trim().isEmpty ?? true);
  }
  if (filter == 'patient') {
    return data['role'] == 'patient' &&
        (data['doctorId']?.toString().trim().isNotEmpty ?? false);
  }
  return data['role'] == filter;
}

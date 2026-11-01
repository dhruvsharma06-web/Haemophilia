const userFilters = {
  'all': 'All users',
  'patient': 'Assigned patients',
  'pending_patient': 'Unassigned patients',
  'doctor': 'Doctors',
  'pending_doctor': 'Pending doctors',
  'admin': 'Admins',
};

List<String> allowedManagedRoles(String role) => switch (role) {
  'doctor' || 'pending_doctor' => ['pending_doctor', 'doctor'],
  'patient' => ['patient'],
  'admin' => ['admin'],
  _ => [],
};

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

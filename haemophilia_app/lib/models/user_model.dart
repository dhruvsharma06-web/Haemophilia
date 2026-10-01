/// Formats a raw full name to 'First Middle Last' normal capitalization.
/// Examples:
///   'dhruv sharma' -> 'Dhruv Sharma'
///   'ARVIND KUMAR' -> 'Arvind Kumar'
///   'rahul amit patil' -> 'Rahul Amit Patil'
String formatFullName(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  return trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String? doctorId;
  final int? age;
  final String? gender;
  final String? phoneNumber;
  final String? photoUrl;
  final bool isApproved;
  final String? registrationNumber;
  final String? specialization;
  final String? hospital;

  UserModel({
    required this.uid,
    required String name,
    required this.email,
    required this.role,
    this.doctorId,
    this.age,
    this.gender,
    this.phoneNumber,
    this.photoUrl,
    this.isApproved = true,
    this.registrationNumber,
    this.specialization,
    this.hospital,
  }) : name = formatFullName(name);

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    final role = data['role'] as String? ?? 'patient';
    final approved = data['isApproved'] as bool? ?? (role != 'pending_doctor');

    return UserModel(
      uid: uid,
      name: formatFullName(data['name'] as String? ?? ''),
      email: data['email'] as String? ?? '',
      role: role,
      doctorId: data['doctorId']?.toString(),
      age: (data['age'] as num?)?.toInt(),
      gender: data['gender']?.toString(),
      phoneNumber: data['phoneNumber']?.toString(),
      photoUrl: data['photoUrl']?.toString(),
      isApproved: approved,
      registrationNumber: data['registrationNumber']?.toString(),
      specialization: data['specialization']?.toString(),
      hospital: data['hospital']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
      'isApproved': isApproved,
      if (doctorId != null) 'doctorId': doctorId,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (registrationNumber != null) 'registrationNumber': registrationNumber,
      if (specialization != null) 'specialization': specialization,
      if (hospital != null) 'hospital': hospital,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    String? doctorId,
    int? age,
    String? gender,
    String? phoneNumber,
    String? photoUrl,
    bool? isApproved,
    String? registrationNumber,
    String? specialization,
    String? hospital,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      doctorId: doctorId ?? this.doctorId,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      isApproved: isApproved ?? this.isApproved,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      specialization: specialization ?? this.specialization,
      hospital: hospital ?? this.hospital,
    );
  }
}

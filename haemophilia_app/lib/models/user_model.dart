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
  }) : name = formatFullName(name);

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: formatFullName(data['name'] as String? ?? ''),
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'patient',
      doctorId: data['doctorId']?.toString(),
      age: (data['age'] as num?)?.toInt(),
      gender: data['gender']?.toString(),
      phoneNumber: data['phoneNumber']?.toString(),
      photoUrl: data['photoUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
      if (doctorId != null) 'doctorId': doctorId,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (photoUrl != null) 'photoUrl': photoUrl,
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
    );
  }
}

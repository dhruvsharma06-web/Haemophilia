class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role;
  final String? doctorId;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.doctorId,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'patient',
      doctorId: data['doctorId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
      if (doctorId != null) 'doctorId': doctorId,
    };
  }
}

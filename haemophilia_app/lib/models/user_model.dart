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

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.doctorId,
    this.age,
    this.gender,
    this.phoneNumber,
    this.photoUrl,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      name: data['name'] as String? ?? '',
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

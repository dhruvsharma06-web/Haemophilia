import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ==========================================================
  // REGISTER PATIENT
  // ==========================================================

  Future<UserModel> registerPatient({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential =
        await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Registration failed.');
    }

    final userModel = UserModel(
      uid: user.uid,
      name: name.trim(),
      email: email.trim(),
      role: 'patient',
    );

    await _firestore
        .collection('users')
        .doc(user.uid)
        .set({
      ...userModel.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return userModel;
  }

  // ==========================================================
  // LOGIN
  // ==========================================================

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final credential =
        await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Login failed.');
    }

    final document = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();

    if (!document.exists || document.data() == null) {
      throw Exception(
        'User profile was not found.',
      );
    }

    return UserModel.fromMap(
      user.uid,
      document.data()!,
    );
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  Future<void> logout() async {
    await _auth.signOut();
  }

  // ==========================================================
  // CURRENT USER
  // ==========================================================

  User? get currentUser {
    return _auth.currentUser;
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  /// Institutional email domain requirement (e.g. '@somaiya.edu').
  /// Kept null to prevent breaking existing Firebase authentication.
  /// Configure this constant once the exact Somaiya institutional domain is confirmed.
  static const String? requiredEmailDomain = null;

  // ==========================================================
  // REGISTER PATIENT
  // ==========================================================

  Future<UserModel> registerPatient({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (requiredEmailDomain != null &&
        !cleanEmail.toLowerCase().endsWith(requiredEmailDomain!)) {
      throw Exception(
        'Please register with your $requiredEmailDomain institutional email.',
      );
    }

    final formattedName = formatFullName(name);
    final credential =
        await _auth.createUserWithEmailAndPassword(
      email: cleanEmail,
      password: password,
    );

    final user = credential.user;

    if (user == null) {
      throw Exception('Registration failed.');
    }

    final userModel = UserModel(
      uid: user.uid,
      name: formattedName,
      email: cleanEmail,
      role: 'patient',
    );

    await _firestore
        .collection('users')
        .doc(user.uid)
        .set({
      ...userModel.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await NotificationService().syncUserToken();

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

    await NotificationService().syncUserToken();

    return UserModel.fromMap(
      user.uid,
      document.data()!,
    );
  }

  // ==========================================================
  // LOGOUT
  // ==========================================================

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await NotificationService()
            .clearTokenOnLogout(uid)
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        // Non-fatal; clearing FCM token should never block Firebase sign-out
      }
    }
    await _auth.signOut();
  }

  // ==========================================================
  // UPDATE PROFILE
  // ==========================================================

  Future<UserModel> updateProfile({
    required String uid,
    required String name,
    required int? age,
    required String? gender,
    String? phoneNumber,
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Unauthorized to update this profile.');
    }

    final trimmedName = formatFullName(name);
    final updateData = <String, dynamic>{
      'name': trimmedName,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (age != null) {
      updateData['age'] = age;
    } else {
      updateData['age'] = FieldValue.delete();
    }

    if (gender != null && gender.trim().isNotEmpty) {
      updateData['gender'] = gender.trim();
    } else {
      updateData['gender'] = FieldValue.delete();
    }

    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      updateData['phoneNumber'] = phoneNumber.trim();
    } else {
      updateData['phoneNumber'] = FieldValue.delete();
    }

    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      updateData['photoUrl'] = photoUrl.trim();
    } else {
      updateData['photoUrl'] = FieldValue.delete();
    }

    await _firestore.collection('users').doc(uid).update(updateData);

    if (user.displayName != trimmedName) {
      try {
        await user.updateDisplayName(trimmedName);
      } catch (_) {
        // Best effort
      }
    }

    final doc = await _firestore.collection('users').doc(uid).get();
    return UserModel.fromMap(uid, doc.data() ?? {});
  }

  // ==========================================================
  // CURRENT USER & AUTH STATE
  // ==========================================================

  User? get currentUser {
    return _auth.currentUser;
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> getCurrentUserModel() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromMap(user.uid, doc.data()!);
    } catch (e) {
      return null;
    }
  }
}
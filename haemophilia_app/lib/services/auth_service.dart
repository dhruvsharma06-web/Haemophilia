import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import 'notification_service.dart';
import 'onboarding_service.dart';
import '../widgets/consent_form.dart';

enum LoginPortal { patient, clinician }

class AuthService {
  static final googleValidation = ValueNotifier<bool>(false);
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Institutional email domain requirement (e.g. '@somaiya.edu').
  /// Kept null to prevent breaking existing Firebase authentication.
  /// Configure this constant once the exact Somaiya institutional domain is confirmed.
  static const String? requiredEmailDomain = null;

  // ==========================================================
  // REGISTER PATIENT (LEGACY / CONVENIENCE)
  // ==========================================================

  Future<UserModel> registerPatient({
    required String name,
    required String email,
    required String password,
    bool consentAccepted = false,
    bool researchConsent = false,
  }) async {
    return registerPatientExtended(
      firstName: name,
      lastName: '',
      email: email,
      password: password,
      consentAccepted: consentAccepted,
      researchConsent: researchConsent,
    );
  }

  // ==========================================================
  // REGISTER PATIENT (EXTENDED MOBILE FORM)
  // ==========================================================

  Future<UserModel> registerPatientExtended({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    bool consentAccepted = false,
    bool researchConsent = false,
    int? age,
    String? gender,
    String? phoneNumber,
  }) async {
    if (!consentAccepted) throw StateError('Please accept the terms and consent first.');
    final cleanEmail = email.trim().toLowerCase();
    if (requiredEmailDomain != null &&
        !cleanEmail.toLowerCase().endsWith(requiredEmailDomain!)) {
      throw Exception(
        'Please register with your $requiredEmailDomain institutional email.',
      );
    }

    final rawName = [
      firstName.trim(),
      if (middleName != null && middleName.trim().isNotEmpty) middleName.trim(),
      lastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');

    final formattedName = formatFullName(rawName);
    final credential = await _auth.createUserWithEmailAndPassword(
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
      age: age,
      gender: gender,
      phoneNumber: phoneNumber?.trim(),
    );

    await _firestore.collection('users').doc(user.uid).set({
      ...userModel.toMap(),
      'patientId': patientDisplayId(user.uid),
      'onboardingCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'consentVersion': consentVersion,
      'consentAcceptedAt': FieldValue.serverTimestamp(),
      'researchConsent': researchConsent,
      'accountActive': true,
    });

    await NotificationService().syncUserToken();
    return userModel;
  }

  // ==========================================================
  // REGISTER DOCTOR / PHYSIOTHERAPIST
  // ==========================================================

  Future<UserModel> registerDoctor({
    required String fullName,
    required String email,
    required String password,
    required String mobileNumber,
    required String country,
    required String state,
    required String city,
    required String registrationNumber,
    required String regulatoryCouncil,
    required String qualification,
    required String specialization,
    required String hospital,
    required String yearsExperience,
    String? registrationCertName,
    String? professionalIdName,
    bool consentAccepted = false,
    bool researchConsent = false,
  }) async {
    if (!consentAccepted) throw StateError('Please accept the terms and consent first.');
    final cleanEmail = email.trim().toLowerCase();
    final formattedName = formatFullName(fullName);

    final credential = await _auth.createUserWithEmailAndPassword(
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
      role: 'pending_doctor',
      isApproved: false,
      phoneNumber: mobileNumber.trim(),
      registrationNumber: registrationNumber.trim(),
      specialization: specialization.trim(),
      hospital: hospital.trim(),
    );

    final doctorData = <String, dynamic>{
      ...userModel.toMap(),
      'country': country.trim(),
      'state': state.trim(),
      'city': city.trim(),
      'regulatoryCouncil': regulatoryCouncil.trim(),
      'qualification': qualification.trim(),
      'yearsExperience': yearsExperience.trim(),
      'registrationCertName': registrationCertName,
      'professionalIdName': professionalIdName,
      'status': 'pending_approval',
      'createdAt': FieldValue.serverTimestamp(),
      'consentVersion': consentVersion,
      'consentAcceptedAt': FieldValue.serverTimestamp(),
      'researchConsent': researchConsent,
      'accountActive': true,
    };

    await _firestore.collection('users').doc(user.uid).set(doctorData);

    try {
      await _firestore.collection('doctorApplications').doc(user.uid).set({
        ...doctorData,
        'applicantId': user.uid,
      });
    } catch (_) {
      // Best effort mirror document
    }

    return userModel;
  }

  // ==========================================================
  // GOOGLE SIGN IN
  // ==========================================================

  Future<UserModel?> signInWithGoogle() async {
    googleValidation.value = true;
    try { return await _signInWithGoogle(); }
    catch (_) { await _auth.signOut(); await _googleSignIn.signOut(); rethrow; }
    finally { googleValidation.value = false; }
  }

  Future<UserModel?> _signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // User canceled the sign-in prompt
      return null;
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential userCredential =
        await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw Exception('Google sign-in was not completed.');
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (!doc.exists || data == null || data['role'] != 'patient' ||
        data['email']?.toString().trim().toLowerCase() != googleUser.email.toLowerCase() ||
        data['accountActive'] == false) {
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        await user.delete();
      }
      await _auth.signOut();
      await _googleSignIn.signOut();
      throw StateError('Register a patient account with this email before using Google sign-in.');
    }

    await NotificationService().syncUserToken();
    return UserModel.fromMap(user.uid, doc.data()!);
  }

  // ==========================================================
  // FORGOT PASSWORD
  // ==========================================================

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }
  // LOGIN
  // ==========================================================

  Future<UserModel> login({
    required String email,
    required String password,
    LoginPortal portal = LoginPortal.patient,
  }) async {
    // The root gate waits for profile validation before choosing a dashboard.
    googleValidation.value = true;
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      final user = credential.user;
      if (user == null) throw FirebaseAuthException(code: 'invalid-credential');
      final document = await _firestore.collection('users').doc(user.uid).get();
      final data = document.data();
      if (data == null) throw FirebaseAuthException(code: 'profile-not-found', message: 'User profile was not found.');
      final role = data['role']?.toString().trim().toLowerCase();
      final permitted = portal == LoginPortal.patient
          ? {'patient', 'admin'} : {'doctor', 'pending_doctor', 'admin'};
      if (!permitted.contains(role)) {
        throw FirebaseAuthException(code: 'wrong-login-portal', message: portal == LoginPortal.patient
            ? 'This is a doctor account. Please use Doctor Login.'
            : 'This is a patient account. Please use Patient Login.');
      }
      if (data['accountActive'] == false) {
        throw FirebaseAuthException(code: 'account-inactive', message: 'Account inactive. Please contact the administrator.');
      }
      await NotificationService().syncUserToken();
      return UserModel.fromMap(user.uid, data);
    } catch (_) {
      await _auth.signOut();
      rethrow;
    } finally {
      googleValidation.value = false;
    }
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
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best effort sign-out from Google
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

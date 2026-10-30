import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/account_validation.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import 'notification_service.dart';
import 'onboarding_service.dart';
import 'local_test_config.dart';
import '../widgets/consent_form.dart';

enum LoginPortal { patient, clinician, admin }

/// Roles each sign-in page accepts. Administrators use only the web portal.
const Map<LoginPortal, Set<String>> portalRoles = {
  LoginPortal.patient: {'patient'},
  LoginPortal.clinician: {'doctor', 'pending_doctor'},
  LoginPortal.admin: {'admin'},
};

class AuthService {
  static final googleValidation = ValueNotifier<bool>(false);

  /// Set when this device is signed out because the account signed in on
  /// another device. The login screen shows it once, then clears it.
  static final signedOutReason = ValueNotifier<String?>(null);
  static const displacedMessage =
      'Your account was signed in on another device, so this device was signed out. Sign in again to continue here.';
  FirebaseAuth get _auth => LocalTestConfig.auth;
  FirebaseFirestore get _firestore => LocalTestConfig.database;
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
    if (!consentAccepted) {
      throw StateError('Please accept the terms and consent first.');
    }
    final cleanEmail = email.trim().toLowerCase();
    if (!validEmail(cleanEmail)) {
      throw StateError('Please enter a valid email address.');
    }
    final passwordProblem = passwordValidation(
      password,
      email: cleanEmail,
      name: '$firstName ${middleName ?? ''} $lastName',
    );
    if (passwordProblem != null) throw StateError(passwordProblem);
    if (phoneNumber != null && mobileValidation(phoneNumber) != null) {
      throw StateError(mobileValidation(phoneNumber)!);
    }
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

    await claimDeviceSession(user);
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
    if (!consentAccepted) {
      throw StateError('Please accept the terms and consent first.');
    }
    final cleanEmail = email.trim().toLowerCase();
    final formattedName = formatFullName(fullName);
    if (!validEmail(cleanEmail)) {
      throw StateError('Please enter a valid email address.');
    }
    final passwordProblem = passwordValidation(
      password,
      email: cleanEmail,
      name: fullName,
    );
    if (passwordProblem != null) throw StateError(passwordProblem);
    if (mobileValidation(mobileNumber) != null) {
      throw StateError(mobileValidation(mobileNumber)!);
    }

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

    await claimDeviceSession(user);
    return userModel;
  }

  // ==========================================================
  // GOOGLE SIGN IN
  // ==========================================================

  Future<UserModel?> signInWithGoogle() async {
    if (LocalTestConfig.enabled) {
      throw StateError(
        'Use the local email/password test accounts. Google sign-in is not connected in local test mode.',
      );
    }
    googleValidation.value = true;
    try {
      return await _signInWithGoogle();
    } catch (_) {
      await _auth.signOut();
      await _googleSignIn.signOut();
      rethrow;
    } finally {
      googleValidation.value = false;
    }
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

    final UserCredential userCredential = await _auth.signInWithCredential(
      credential,
    );
    final user = userCredential.user;
    if (user == null) {
      throw Exception('Google sign-in was not completed.');
    }

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (!doc.exists ||
        data == null ||
        data['role'] != 'patient' ||
        data['email']?.toString().trim().toLowerCase() !=
            googleUser.email.toLowerCase() ||
        data['accountActive'] == false) {
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        await user.delete();
      }
      await _auth.signOut();
      await _googleSignIn.signOut();
      throw StateError(
        'Register a patient account with this email before using Google sign-in.',
      );
    }

    await claimDeviceSession(user);
    await NotificationService().syncUserToken();
    return UserModel.fromMap(user.uid, doc.data()!);
  }

  // ==========================================================
  // FORGOT PASSWORD
  // ==========================================================

  /// Completes normally for unknown emails so the response never reveals
  /// whether an account exists.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found') rethrow;
    }
  }

  // ==========================================================
  // SINGLE ACTIVE DEVICE
  // ==========================================================

  /// Seconds-since-epoch of this sign-in, as recorded in the ID token.
  static Future<int?> authTimeOf(User user) async {
    try {
      final token = await user.getIdTokenResult();
      final claim = token.claims?['auth_time'];
      if (claim is num) return claim.toInt();
      final time = token.authTime;
      return time == null ? null : time.millisecondsSinceEpoch ~/ 1000;
    } catch (error) {
      debugPrint('Could not read sign-in time: $error');
      return null;
    }
  }

  /// Makes this sign-in the account's only valid session.
  ///
  /// Firestore and Storage rules refuse requests whose token `auth_time` is
  /// older than `sessionValidAfter`, and the root gate signs older devices out
  /// as soon as the profile changes. A failure here never blocks sign-in.
  Future<void> claimDeviceSession(User user) async {
    final authTime = await authTimeOf(user);
    if (authTime == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'sessionValidAfter': authTime,
        'activeDevice': {
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'signedInAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (error) {
      debugPrint('Could not register the active device: $error');
    }
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
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw FirebaseAuthException(code: 'invalid-credential');
      final document = await _firestore.collection('users').doc(user.uid).get();
      final data = document.data();
      if (data == null) {
        throw FirebaseAuthException(
          code: 'profile-not-found',
          message: 'User profile was not found.',
        );
      }
      final role = data['role']?.toString().trim().toLowerCase();
      if (!portalRoles[portal]!.contains(role)) {
        // Uniform messages: never say which kind of account this is.
        throw FirebaseAuthException(
          code: portal == LoginPortal.admin
              ? 'not-admin'
              : role == 'admin'
              ? 'admin-web-only'
              : 'wrong-login-portal',
        );
      }
      if (data['accountActive'] == false) {
        throw FirebaseAuthException(
          code: 'account-inactive',
          message: 'Account inactive. Please contact the administrator.',
        );
      }
      await claimDeviceSession(user);
      if (portal != LoginPortal.admin) {
        await NotificationService().syncUserToken();
      }
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

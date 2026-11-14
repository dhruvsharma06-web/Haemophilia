import 'local_test_config.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../widgets/consent_form.dart';

String patientDisplayId(String uid) => 'SHP-${uid.toUpperCase()}';

class OnboardingService {
  DocumentReference<Map<String, dynamic>> get _profile {
    final uid = LocalTestConfig.auth.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in.');
    return LocalTestConfig.database.collection('users').doc(uid);
  }

  Future<void> acceptConsent(bool researchConsent) => _profile.update({
    'consentVersion': consentVersion,
    'consentAcceptedAt': FieldValue.serverTimestamp(),
    'researchConsent': researchConsent,
    'researchConsentUpdatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> complete({
    required String diagnosisStatus,
    Map<String, dynamic>? answers,
    Map<String, dynamic>? result,
  }) => _profile.update({
    'diagnosisStatus': diagnosisStatus,
    'patientId': patientDisplayId(_profile.id),
    'screeningAnswers': answers ?? <String, dynamic>{},
    'screeningResult': result ?? <String, dynamic>{},
    'onboardingCompleted': true,
    'onboardingCompletedAt': FieldValue.serverTimestamp(),
  });
}

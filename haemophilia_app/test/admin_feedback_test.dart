import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/utils/admin_account_policy.dart';
import 'package:haemophilia_app/utils/firebase_errors.dart';
import 'package:haemophilia_app/utils/app_localizations.dart';

void main() {
  test('all rejected portal logins have the same credential error', () {
    for (final language in ['en', 'hi']) {
      AppLocaleService.currentLocale.value = language;
      final expected = authErrorMessage(
        FirebaseAuthException(code: 'invalid-credential'),
      );
      for (final code in [
        'wrong-login-portal',
        'admin-web-only',
        'not-admin',
        'profile-not-found',
        'wrong-password',
        'user-not-found',
      ]) {
        expect(authErrorMessage(FirebaseAuthException(code: code)), expected);
      }
    }
    AppLocaleService.currentLocale.value = 'en';
  });
  test('account families cannot be converted into each other', () {
    expect(allowedManagedRoles('patient'), ['patient']);
    expect(allowedManagedRoles('doctor'), ['pending_doctor', 'doctor']);
    expect(allowedManagedRoles('pending_doctor'), ['pending_doctor', 'doctor']);
    expect(allowedManagedRoles('admin'), ['admin']);
  });
  test('filters distinguish pending patients and unapproved clinicians', () {
    expect(matchesUserFilter({'role': 'patient'}, 'pending_patient'), isTrue);
    expect(
      matchesUserFilter({
        'role': 'patient',
        'doctorId': 'd',
      }, 'pending_patient'),
      isFalse,
    );
    expect(
      matchesUserFilter({'role': 'doctor', 'isApproved': false}, 'doctor'),
      isFalse,
    );
    expect(
      matchesUserFilter({
        'role': 'doctor',
        'isApproved': false,
      }, 'pending_doctor'),
      isTrue,
    );
    expect(
      matchesUserFilter({'role': 'pending_doctor'}, 'pending_doctor'),
      isTrue,
    );
    expect(matchesUserFilter({'role': 'admin'}, 'patient'), isFalse);
  });

  test(
    'dashboard totals update as accounts register, gain approval or close',
    () {
      final users = <Map<String, dynamic>>[
        {'role': 'admin'},
        {'role': 'doctor'}, // Legacy approved account.
        {'role': 'doctor', 'isApproved': false},
        {'role': 'patient', 'doctorId': 'doctor'},
        {'role': 'patient', 'accountActive': false},
        {'role': 'doctor', 'status': 'removed'},
        {'role': 'patient', 'status': 'rejected'},
        {'role': 'admin', 'status': 'inactive'},
      ];
      expect(adminUserCounts(users), (doctors: 1, patients: 1, total: 4));

      final patient = <String, dynamic>{
        'role': 'patient',
        'accountActive': true,
      };
      final applicant = <String, dynamic>{
        'role': 'pending_doctor',
        'isApproved': false,
      };
      users.addAll([patient, applicant]);
      expect(adminUserCounts(users), (doctors: 1, patients: 2, total: 6));

      patient['doctorId'] = 'doctor';
      expect(adminUserCounts(users), (doctors: 1, patients: 2, total: 6));

      applicant.addAll({'role': 'doctor', 'isApproved': true});
      expect(adminUserCounts(users), (doctors: 2, patients: 2, total: 6));

      applicant['accountActive'] = false;
      patient['status'] = 'rejected';
      expect(adminUserCounts(users), (doctors: 1, patients: 1, total: 4));
    },
  );
}

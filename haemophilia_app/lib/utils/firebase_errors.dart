import 'package:firebase_core/firebase_core.dart';

import 'app_localizations.dart';

/// Keep service error codes in logs; show an actionable message in the app.
String firebaseErrorMessage(Object? error, {String fallback = 'Could not save. Please try again.'}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return tr('Access is unavailable. Please contact the administrator.');
      case 'failed-precondition':
        return tr('This feature is being configured. Please contact the administrator.');
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return tr('Check your internet connection and try again.');
      case 'unauthenticated':
        return tr('Your sign-in has expired. Please sign in again.');
      case 'not-found':
        return tr('This record is no longer available. Refresh and try again.');
    }
  }
  return tr(fallback);
}

/// Sign-in errors are deliberately uniform: the message never reveals whether
/// an email is registered, or which kind of account it belongs to.
String authErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-login-credentials':
        return tr('Invalid email or password.');
      case 'wrong-login-portal':
        return tr(
          'Invalid email or password for this sign-in page. Patients and physiotherapists sign in on separate pages.',
        );
      case 'admin-web-only':
        return tr('Administrator accounts sign in on the web admin portal.');
      case 'not-admin':
        return tr('This account does not have administrator access.');
      case 'profile-not-found':
      case 'account-inactive':
        return tr('Account inactive. Please contact the administrator.');
      case 'invalid-email':
        return tr('Please enter a valid email address.');
      case 'user-disabled':
        return tr('This account has been disabled.');
      case 'too-many-requests':
        return tr('Too many attempts. Please try again later.');
      case 'network-request-failed':
        return tr('Check your internet connection and try again.');
    }
  }
  return tr('Login failed. Please try again.');
}

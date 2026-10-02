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

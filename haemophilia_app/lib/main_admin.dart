// Entry point for the separate web admin portal.
//
// Build:   flutter build web --release -t lib/main_admin.dart --output build/admin_web
// Deploy:  firebase deploy --only hosting:admin
//
// The mobile app (lib/main.dart) never routes to administration screens.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admin_portal/admin_portal_app.dart';
import 'firebase_options.dart';
import 'services/local_test_config.dart';
import 'utils/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLocaleService.init();

  if (LocalTestConfig.enabled && kReleaseMode) {
    throw StateError('Local test mode is not allowed in release builds.');
  }

  await Firebase.initializeApp(
    name: LocalTestConfig.enabled ? LocalTestConfig.appName : null,
    options: LocalTestConfig.enabled
        ? LocalTestConfig.options
        : DefaultFirebaseOptions.web,
  );

  // Admin sessions end when the browser tab closes.
  if (kIsWeb) {
    await LocalTestConfig.auth.setPersistence(Persistence.SESSION);
  }

  if (LocalTestConfig.enabled) {
    await LocalTestConfig.auth.useAuthEmulator(LocalTestConfig.host, 9099);
    LocalTestConfig.database.useFirestoreEmulator(LocalTestConfig.host, 8089);
    LocalTestConfig.database.settings = const Settings(
      persistenceEnabled: false,
    );
    await LocalTestConfig.storage.useStorageEmulator(
      LocalTestConfig.host,
      9199,
    );
  }

  runApp(const AdminPortalApp());
}

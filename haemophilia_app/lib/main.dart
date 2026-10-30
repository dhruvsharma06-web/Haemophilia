import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';
import 'services/notification_service.dart';
import 'services/local_test_config.dart';
import 'utils/app_localizations.dart';
import 'utils/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
        : DefaultFirebaseOptions.currentPlatform,
  );

  if (LocalTestConfig.enabled) {
    await LocalTestConfig.auth.useAuthEmulator(
      LocalTestConfig.host,
      9099,
      automaticHostMapping: false,
    );
    LocalTestConfig.database.useFirestoreEmulator(
      LocalTestConfig.host,
      8089,
      automaticHostMapping: false,
    );
    LocalTestConfig.database.settings = const Settings(
      persistenceEnabled: false,
    );
    await LocalTestConfig.storage.useStorageEmulator(
      LocalTestConfig.host,
      9199,
      automaticHostMapping: false,
    );
    NotificationService().setNavigatorKey(navigatorKey);
  } else {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await NotificationService().initialize(navKey: navigatorKey);
  }

  runApp(const HaemophiliaApp());
}

class HaemophiliaApp extends StatelessWidget {
  const HaemophiliaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocaleService.currentLocale,
      builder: (context, localeCode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Somaiya HemoPhysio',
          locale: Locale(localeCode),
          supportedLocales: const [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => AppLocaleScope(
            notifier: AppLocaleService.currentLocale,
            child: child!,
          ),
          theme: buildAppTheme(),
          home: const AuthGate(),
        );
      },
    );
  }
}

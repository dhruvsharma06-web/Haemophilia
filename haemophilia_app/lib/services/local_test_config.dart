import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Opt-in isolated development setup. Release builds cannot use this mode.
class LocalTestConfig {
  static const enabled = bool.fromEnvironment('LOCAL_TEST');
  static const appName = 'hemo-local-test';
  static FirebaseApp get app =>
      enabled ? Firebase.app(appName) : Firebase.app();
  static FirebaseAuth get auth =>
      enabled ? FirebaseAuth.instanceFor(app: app) : FirebaseAuth.instance;
  static FirebaseFirestore get database => enabled
      ? FirebaseFirestore.instanceFor(app: app)
      : FirebaseFirestore.instance;
  static FirebaseStorage get storage => enabled
      ? FirebaseStorage.instanceFor(app: app)
      : FirebaseStorage.instance;
  static const host = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const options = FirebaseOptions(
    apiKey: 'demo-local-only',
    appId: '1:1234567890:android:localtest',
    messagingSenderId: '1234567890',
    projectId: 'demo-hemo-local',
    authDomain: 'demo-hemo-local.firebaseapp.com',
    storageBucket: 'demo-hemo-local.appspot.com',
  );
}

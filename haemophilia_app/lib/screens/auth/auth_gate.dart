import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../admin/admin_dashboard.dart';
import '../doctor/doctor_dashboard.dart';
import '../patient/patient_dashboard.dart';
import 'login_screen.dart';

/// Gate widget that determines whether the user is authenticated and routes
/// to the appropriate dashboard based on their role stored in Firestore.
/// Acts as the single source of truth for the application's root route.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _syncedUid;

  void _syncTokenForUser(String uid) {
    if (_syncedUid == uid) return;
    _syncedUid = uid;
    NotificationService().syncUserToken();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        // While Firebase Auth is determining the current user state
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/haemophysio_logo.png',
                    height: 84,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'HaemoPhysio',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          _syncedUid = null;
          return const LoginScreen();
        }

        // User is authenticated; stream their Firestore user profile document
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting &&
                !userSnapshot.hasData) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icon/haemophysio_logo.png',
                        height: 84,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HaemoPhysio',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                    ],
                  ),
                ),
              );
            }

            if (userSnapshot.hasError ||
                !userSnapshot.hasData ||
                !userSnapshot.data!.exists ||
                userSnapshot.data!.data() == null) {
              // If profile does not exist or errored, offer sign out rather than stuck loop
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_off_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'User profile not found',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Could not load account details for ${user.email ?? user.uid}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.tonal(
                          onPressed: () => AuthService().logout(),
                          child: const Text('Sign out to try another account'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final data = userSnapshot.data!.data()!;
            final userModel = UserModel.fromMap(user.uid, data);

            // Sync FCM notification token in post-frame callback ONLY when user changes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _syncTokenForUser(user.uid);
              }
            });

            switch (userModel.role.toLowerCase()) {
              case 'doctor':
                return DoctorDashboard(user: userModel);
              case 'admin':
                return AdminDashboard(user: userModel);
              case 'patient':
              default:
                return PatientDashboard(user: userModel);
            }
          },
        );
      },
    );
  }
}

import '../../services/local_test_config.dart';
import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../doctor/doctor_dashboard.dart';
import '../patient/patient_dashboard.dart';
import 'doctor_pending_approval_screen.dart';
import 'login_screen.dart';
import 'patient_onboarding_screen.dart';
import '../../widgets/consent_form.dart';
import '../../services/onboarding_service.dart';
import '../../utils/app_localizations.dart';

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
  String? _authTimeUid;
  int? _authTime;
  bool _signingOutDisplaced = false;

  void _syncTokenForUser(String uid) {
    if (_syncedUid == uid) return;
    _syncedUid = uid;
    NotificationService().syncUserToken();
  }

  /// Reads this device's sign-in time once per signed-in account.
  void _loadAuthTime(User user) {
    if (_authTimeUid == user.uid) return;
    _authTimeUid = user.uid;
    _authTime = null;
    AuthService.authTimeOf(user).then((value) {
      if (mounted && _authTimeUid == user.uid) {
        setState(() => _authTime = value);
      }
    });
  }

  /// True when another device signed in to this account after this one.
  bool _displaced(Map<String, dynamic> data) {
    final validAfter = data['sessionValidAfter'];
    return _authTime != null && validAfter is num && validAfter > _authTime!;
  }

  void _signOutDisplaced() {
    if (_signingOutDisplaced) return;
    _signingOutDisplaced = true;
    AuthService.signedOutReason.value = AuthService.displacedMessage;
    AuthService().logout().whenComplete(() => _signingOutDisplaced = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.googleValidation,
      builder: (context, validating, _) {
        return StreamBuilder<User?>(
          stream: LocalTestConfig.auth.authStateChanges(),
          builder: (context, authSnapshot) {
            if (validating) return const LoginScreen();
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
                      const AppText(
                        'Somaiya HemoPhysio',
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
            if (user == null ||
                LocalTestConfig.auth.currentUser?.uid != user.uid) {
              _syncedUid = null;
              _authTimeUid = null;
              _authTime = null;
              return const LoginScreen();
            }
            _loadAuthTime(user);

            // User is authenticated; stream their Firestore user profile document
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: LocalTestConfig.database
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
                          const AppText(
                            'Somaiya HemoPhysio',
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
                            const AppText(
                              'User profile not found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AppText(
                              'Could not load account details for ${user.email ?? user.uid}.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.tonal(
                              onPressed: () => AuthService().logout(),
                              child: const AppText(
                                'Sign out to try another account',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final data = userSnapshot.data!.data()!;
                final userModel = UserModel.fromMap(user.uid, data);

                if (_displaced(data)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _signOutDisplaced();
                  });
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                // Sync FCM notification token in post-frame callback ONLY when user changes
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _syncTokenForUser(user.uid);
                  }
                });

                if (data['accountActive'] == false) {
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppText(
                            'Account inactive. Please contact the administrator.',
                          ),
                          if (data['rejectionReason'] != null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                data['rejectionReason'].toString(),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          TextButton(
                            onPressed: () => AuthService().logout(),
                            child: const AppText('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (userModel.role != 'admin' &&
                    data['consentVersion'] != consentVersion) {
                  return Scaffold(
                    appBar: AppBar(title: const AppText('Somaiya HemoPhysio')),
                    body: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              ConsentForm(
                                patient: userModel.role == 'patient',
                                onAccept: (research) =>
                                    OnboardingService().acceptConsent(research),
                              ),
                              TextButton(
                                onPressed: () => AuthService().logout(),
                                child: const AppText('Sign out'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                if (userModel.role == 'patient' &&
                    data['onboardingCompleted'] != true) {
                  return PatientOnboardingScreen(
                    registeredAge: userModel.age,
                    registeredGender: userModel.gender,
                  );
                }
                switch (userModel.role.toLowerCase()) {
                  case 'doctor':
                    if (!userModel.isApproved) {
                      return DoctorPendingApprovalScreen(user: userModel);
                    }
                    return DoctorDashboard(user: userModel);
                  case 'pending_doctor':
                    return DoctorPendingApprovalScreen(user: userModel);
                  case 'admin':
                    // Administration lives in the separate web portal
                    // (lib/main_admin.dart); the mobile app never shows it.
                    return const AdminWebOnlyScreen();
                  case 'patient':
                    return PatientDashboard(user: userModel);
                  default:
                    return Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => AuthService().logout(),
                          child: const AppText(
                            'Account access unavailable. Sign out and contact admin.',
                          ),
                        ),
                      ),
                    );
                }
              },
            );
          },
        );
      },
    );
  }
}

/// Shown if an administrator account reaches the mobile app.
class AdminWebOnlyScreen extends StatelessWidget {
  const AdminWebOnlyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    tr('Administrator accounts sign in on the web admin portal.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Open the admin portal in a web browser to manage accounts, doctor approvals and grievances.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () => AuthService().logout(),
                    child: Text(tr('Sign out')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

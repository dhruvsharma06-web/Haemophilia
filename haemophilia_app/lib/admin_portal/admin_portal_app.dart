import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../models/user_model.dart';
import '../screens/admin/admin_dashboard.dart';
import '../services/auth_service.dart';
import '../services/local_test_config.dart';
import '../utils/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/firebase_errors.dart';

/// Signs an idle administrator out after this long without input.
const adminIdleTimeout = Duration(minutes: 30);

class AdminPortalApp extends StatelessWidget {
  const AdminPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLocaleService.currentLocale,
      builder: (context, localeCode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Somaiya HemoPhysio · Admin',
        locale: Locale(localeCode),
        supportedLocales: const [Locale('en'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppLocaleScope(
          notifier: AppLocaleService.currentLocale,
          child: child!,
        ),
        theme: buildAppTheme(),
        home: const AdminPortalGate(),
      ),
    );
  }
}

/// Allows only active administrator accounts holding the account's current
/// session; anything else is signed out with a uniform message.
class AdminPortalGate extends StatefulWidget {
  const AdminPortalGate({super.key});

  @override
  State<AdminPortalGate> createState() => _AdminPortalGateState();
}

class _AdminPortalGateState extends State<AdminPortalGate> {
  String? _authTimeUid;
  int? _authTime;
  bool _signingOut = false;
  Timer? _idle;

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _resetIdle() {
    _idle?.cancel();
    if (LocalTestConfig.auth.currentUser == null) return;
    _idle = Timer(adminIdleTimeout, () {
      AuthService.signedOutReason.value =
          'You were signed out after 30 minutes without activity.';
      _signOut();
    });
  }

  void _signOut([String? reason]) {
    if (_signingOut) return;
    _signingOut = true;
    if (reason != null) AuthService.signedOutReason.value = reason;
    _idle?.cancel();
    AuthService().logout().whenComplete(() => _signingOut = false);
  }

  void _loadAuthTime(User user) {
    if (_authTimeUid == user.uid) return;
    _authTimeUid = user.uid;
    _authTime = null;
    _resetIdle();
    AuthService.authTimeOf(user).then((value) {
      if (mounted && _authTimeUid == user.uid) setState(() => _authTime = value);
    });
  }

  Widget _loading() =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.googleValidation,
      builder: (context, validating, _) => StreamBuilder<User?>(
        stream: LocalTestConfig.auth.authStateChanges(),
        builder: (context, authSnapshot) {
          if (validating) return const AdminLoginScreen();
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return _loading();
          }
          final user = authSnapshot.data;
          if (user == null) {
            _authTimeUid = null;
            _authTime = null;
            _idle?.cancel();
            return const AdminLoginScreen();
          }
          _loadAuthTime(user);
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: LocalTestConfig.database
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) return _loading();
              final data = snapshot.data?.data();
              final validAfter = data?['sessionValidAfter'];
              final displaced =
                  _authTime != null &&
                  validAfter is num &&
                  validAfter > _authTime!;
              final allowed =
                  data != null &&
                  data['role'] == 'admin' &&
                  data['accountActive'] != false;
              if (snapshot.hasError || !allowed || displaced) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _signOut(
                    displaced
                        ? AuthService.displacedMessage
                        : 'This account does not have administrator access.',
                  );
                });
                return _loading();
              }
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _resetIdle(),
                onPointerSignal: (_) => _resetIdle(),
                child: AdminDashboard(user: UserModel.fromMap(user.uid, data)),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = tr('Please fill in all fields.'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService().login(
        email: email,
        password: _password.text,
        portal: LoginPortal.admin,
      );
      AuthService.signedOutReason.value = null;
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: const [LanguageToggleButton(), SizedBox(width: 8)],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/icon/haemophysio_logo.png',
                    height: 72,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Admin portal'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ValueListenableBuilder<String?>(
                    valueListenable: AuthService.signedOutReason,
                    builder: (context, reason, _) => reason == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              color: const Color(0xFFFFF4E5),
                              child: ListTile(
                                leading: const Icon(Icons.info_outline),
                                title: Text(tr(reason)),
                                trailing: IconButton(
                                  tooltip: tr('OK'),
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      AuthService.signedOutReason.value = null,
                                ),
                              ),
                            ),
                          ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr('Administrator sign-in'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _email,
                            enabled: !_loading,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: tr('Email Address'),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            enabled: !_loading,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: tr('Password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: tr(
                                  _obscure ? 'Show password' : 'Hide password',
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(tr('Sign In')),
                          ),
                        ],
                      ),
                    ),
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

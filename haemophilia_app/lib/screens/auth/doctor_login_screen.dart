import '../../widgets/app_text.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/app_localizations.dart';
import 'doctor_register_screen.dart';

class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});

  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final identifier = _idController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty) {
      _showError(tr('Please enter your Physiotherapist ID or Email.'));
      return;
    }
    if (password.isEmpty) {
      _showError(tr('Please enter your password.'));
      return;
    }

    setState(() => _loading = true);

    try {
      await _authService.login(
        portal: LoginPortal.clinician,
        email: identifier,
        password: password,
      );

      if (!mounted) return;

      // Pop back to root AuthGate which reactively mounts DoctorDashboard or Pending screen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      _showError(_firebaseAuthError(e));
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(
      text: _idController.text.trim(),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool sending = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(tr('Reset Password')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: tr('Email Address'),
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(tr('Cancel')),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr('Please enter a valid email address.'),
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => sending = true);
                          try {
                            await _authService.sendPasswordResetEmail(email);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  content: Text(
                                    tr(
                                      'Password reset link sent to your email.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => sending = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: AppText(
                                    '${tr('Could not send reset email:')} $e',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(tr('Send Reset Link')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _firebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-login-portal':
      case 'profile-not-found':
      case 'account-inactive':
        return tr(e.message ?? 'Login failed. Please try again.');
      case 'invalid-credential':
        return tr('Invalid credentials or password.');
      case 'user-not-found':
        return tr('No clinician account found with this ID.');
      case 'wrong-password':
        return tr('Incorrect password.');
      case 'invalid-email':
        return tr('Please enter a valid email address.');
      case 'user-disabled':
        return tr('This account has been disabled.');
      case 'too-many-requests':
        return tr('Too many attempts. Please try again later.');
      default:
        return e.message ?? tr('Login failed. Please try again.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [LanguageToggleButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 20 : 32,
              vertical: 20,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Image.asset(
                    'assets/icon/haemophysio_logo.png',
                    height: 76,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  AppText(
                    'Somaiya HemoPhysio',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 25 : 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 20 : 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr('Physiotherapist Login'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _idController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: tr('Physiotherapist ID'),
                              hintText: 'doctor@somaiya.edu',
                              prefixIcon: const Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            onSubmitted: (_) {
                              if (!_loading) _login();
                            },
                            decoration: InputDecoration(
                              labelText: tr('Password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? tr('Show password')
                                    : tr('Hide password'),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading ? null : _forgotPassword,
                              child: Text(
                                tr('Forgot Password?'),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _loading ? null : _login,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    tr('Sign In'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const DoctorRegisterScreen(),
                                          ),
                                        );
                                      },
                                child: Text(tr('Register for an Account')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(
                      tr('Back to Patient Login'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

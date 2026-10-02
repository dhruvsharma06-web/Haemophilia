import 'package:flutter/material.dart';

import '../../services/onboarding_service.dart';
import '../../utils/app_localizations.dart';
import 'health_screening_screen.dart';
import '../../services/auth_service.dart';

class PatientOnboardingScreen extends StatefulWidget {
  const PatientOnboardingScreen({super.key});
  @override
  State<PatientOnboardingScreen> createState() =>
      _PatientOnboardingScreenState();
}

class _PatientOnboardingScreenState extends State<PatientOnboardingScreen> {
  String? _diagnosis;
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    if (_diagnosis == 'no' || _diagnosis == 'unsure') {
      return HealthScreeningScreen(
        onComplete: (answers, result) => OnboardingService().complete(
          diagnosisStatus: _diagnosis!,
          answers: answers,
          result: result,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Welcome')),
        actions: [
          const LanguageToggleButton(),
          IconButton(
            tooltip: tr('Sign out'),
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().logout(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                tr('Have you been diagnosed with haemophilia?'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Text(
                tr(
                  'Tell us about your health so an administrator can assign a doctor. This information does not establish a diagnosis.',
                ),
              ),
              const SizedBox(height: 20),
              if (_diagnosis == 'yes') ...[
                Text(
                  tr(
                    'Please contact a qualified doctor for guidance before exercising. You can enter the app while we arrange your doctor assignment.',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() {
                            _saving = true;
                            _error = null;
                          });
                          try {
                            await OnboardingService().complete(
                              diagnosisStatus: 'yes',
                            );
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => _error = tr(
                                  'Could not save. Please try again.',
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  child: Text(tr('Continue to app')),
                ),
              ] else ...[
                FilledButton(
                  onPressed: () => setState(() => _diagnosis = 'yes'),
                  child: Text(tr('Yes, diagnosed')),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _diagnosis = 'no'),
                  child: Text(tr('No diagnosis')),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _diagnosis = 'unsure'),
                  child: Text(tr('Not sure')),
                ),
              ],
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
    );
  }
}

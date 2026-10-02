import 'package:flutter/material.dart';

import '../utils/app_localizations.dart';

const consentVersion = '2026-10-02-v1';

/// Explicit choices are saved with a version and timestamp in the user profile.
class ConsentForm extends StatefulWidget {
  final Future<void> Function(bool researchConsent) onAccept;
  final bool patient;
  const ConsentForm({super.key, required this.onAccept, this.patient = true});

  @override
  State<ConsentForm> createState() => _ConsentFormState();
}

class _ConsentFormState extends State<ConsentForm> {
  bool _terms = false;
  bool _research = false;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Terms, privacy and consent'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Somaiya HemoPhysio supports exercise guidance and progress monitoring. AI screening and movement feedback may be inaccurate and do not provide a diagnosis or replace your treating clinician. Follow your prescribed care plan and seek professional guidance when unsure.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            widget.patient
                ? 'Your account information, screening answers, messages and exercise results are stored to provide the service. Relevant care records are available to your assigned doctor and authorized administrators as part of your care. Camera processing is confirmed separately before each session.'
                : 'Your professional profile and messages are stored to provide the service. Administrators review doctor applications. Only access records for patients assigned to your care.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Use accurate information, keep your login private and use messaging respectfully. You remain responsible for deciding when to stop and seeking medical help. Do not exercise while bleeding or continue through concerning symptoms.',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _terms,
          onChanged: _saving
              ? null
              : (v) => setState(() => _terms = v ?? false),
          title: Text(
            tr('I accept the terms and acknowledge the privacy information.'),
          ),
        ),
        if (widget.patient)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _research,
          onChanged: _saving
              ? null
              : (v) => setState(() => _research = v ?? false),
          title: Text(
            tr(
              'Optional: I allow my assessment and screening data to be used for research and development.',
            ),
          ),
          subtitle: Text(
            tr(
              'Declining does not prevent access. You can change this choice in Help.',
            ),
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: !_terms || _saving
              ? null
              : () async {
                  setState(() {
                    _saving = true;
                    _error = null;
                  });
                  try {
                    await widget.onAccept(widget.patient && _research);
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _error = tr('Could not save. Please try again.'),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(tr(_saving ? 'Saving...' : 'Accept and continue')),
        ),
      ],
    );
  }
}

Future<bool?> requestRegistrationConsent(BuildContext context, {bool patient = true}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConsentForm(
                patient: patient,
                onAccept: (research) async => Navigator.pop(context, research),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Cancel')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

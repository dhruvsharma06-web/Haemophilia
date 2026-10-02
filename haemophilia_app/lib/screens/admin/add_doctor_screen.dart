import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/firebase_errors.dart';

class AddDoctorScreen extends StatefulWidget {
  const AddDoctorScreen({super.key});
  @override
  State<AddDoctorScreen> createState() => _AddDoctorScreenState();
}

class _AddDoctorScreenState extends State<AddDoctorScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in [
      'name',
      'email',
      'phoneNumber',
      'registrationNumber',
      'qualification',
      'specialization',
      'hospital',
      'password',
    ])
      key: TextEditingController(),
  };
  late final String _requestId = FirebaseFirestore.instance
      .collection('adminAudit')
      .doc()
      .id;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AdminService().createDoctor({
        for (final field in _fields.entries)
          field.key: field.key == 'password'
              ? field.value.text
              : field.value.text.trim(),
        'requestId': _requestId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Doctor account created. Share the login credentials securely with the doctor.',
            ),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError ? tr(error.message.toString()) : firebaseErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final labels = {
      'name': 'Full Name',
      'email': 'Email',
      'phoneNumber': 'Mobile Number',
      'registrationNumber': 'Registration number',
      'qualification': 'Qualification',
      'specialization': 'Specialization',
      'hospital': 'Hospital / clinic',
      'password': 'Initial password',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Add doctor')),
        actions: const [LanguageToggleButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  tr('The doctor must accept the terms on their first login.'),
                ),
                for (final field in _fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextFormField(
                      controller: field.value,
                      enabled: !_saving,
                      obscureText: field.key == 'password',
                      maxLength: field.key == 'password' ? 128 : 200,
                      keyboardType: field.key == 'email'
                          ? TextInputType.emailAddress
                          : field.key == 'phoneNumber'
                          ? TextInputType.phone
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: tr(labels[field.key]!),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return tr('Required');
                        }
                        if (field.key == 'password' && value.length < 8) {
                          return tr('At least 8 characters');
                        }
                        if (field.key == 'email' &&
                            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value.trim())) {
                          return tr('Please enter a valid email address.');
                        }
                        return null;
                      },
                    ),
                  ),
                if (_error != null) Text(_error!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    tr(_saving ? 'Saving...' : 'Create doctor account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

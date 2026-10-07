import '../../widgets/app_text.dart';
import '../../utils/account_validation.dart';
import '../../widgets/consent_form.dart';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/app_localizations.dart';

class DoctorRegisterScreen extends StatefulWidget {
  const DoctorRegisterScreen({super.key});

  @override
  State<DoctorRegisterScreen> createState() => _DoctorRegisterScreenState();
}

class _DoctorRegisterScreenState extends State<DoctorRegisterScreen> {
  final _authService = AuthService();
  int _currentStep = 0;
  bool _loading = false;

  // Section 1: Personal Information
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _countryController = TextEditingController(text: 'India');
  final _stateController = TextEditingController(text: 'Maharashtra');
  final _cityController = TextEditingController(text: 'Mumbai');
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // Section 2: Professional Information
  final _regNumberController = TextEditingController();
  final _councilController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _specializationController = TextEditingController();
  final _hospitalController = TextEditingController();
  final _experienceController = TextEditingController();

  // Section 3: Professional Documents
  PlatformFile? _registrationCertFile;
  PlatformFile? _professionalIdFile;

  // Section 4: Declaration
  bool _declarationChecked = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _countryController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    _regNumberController.dispose();
    _councilController.dispose();
    _qualificationController.dispose();
    _specializationController.dispose();
    _hospitalController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument({required bool isCert}) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (files.isNotEmpty) {
        setState(() {
          if (isCert) {
            _registrationCertFile = files.first;
          } else {
            _professionalIdFile = files.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: AppText('${tr('Error selecting file:')} $e'),
          ),
        );
      }
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

  bool _validateStep(int step) {
    if (step == 0) {
      // Personal
      if (_fullNameController.text.trim().isEmpty) {
        _showError(tr('Please enter your full name.'));
        return false;
      }
      final email = _emailController.text.trim();
      if (!validEmail(email)) {
        _showError(tr('Please enter a valid email address.'));
        return false;
      }
      if (mobileValidation(_mobileController.text) != null) {
        _showError(tr(mobileValidation(_mobileController.text)!));
        return false;
      }
      if (_cityController.text.trim().isEmpty) {
        _showError(tr('Please enter your city.'));
        return false;
      }
      if (passwordValidation(_passwordController.text) != null) {
        _showError(tr(passwordValidation(_passwordController.text)!));
        return false;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        _showError(tr('Passwords do not match.'));
        return false;
      }
      return true;
    } else if (step == 1) {
      // Professional
      if (_regNumberController.text.trim().isEmpty) {
        _showError(tr('Please enter your medical registration number.'));
        return false;
      }
      if (_councilController.text.trim().isEmpty) {
        _showError(
          tr('Please specify your medical council or regulatory authority.'),
        );
        return false;
      }
      if (_qualificationController.text.trim().isEmpty) {
        _showError(
          tr('Please enter your medical qualification (e.g. BPT, MPT).'),
        );
        return false;
      }
      if (_hospitalController.text.trim().isEmpty) {
        _showError(
          tr('Please enter your hospital or affiliated organization.'),
        );
        return false;
      }
      return true;
    } else if (step == 2) {
      // Documents - require at least one or prompt notice
      if (_registrationCertFile == null && _professionalIdFile == null) {
        _showError(
          tr(
            'Please attach your medical registration certificate or ID document.',
          ),
        );
        return false;
      }
      return true;
    } else if (step == 3) {
      // Declaration
      if (!_declarationChecked) {
        _showError(
          tr(
            'Please accept the declaration before submitting your registration.',
          ),
        );
        return false;
      }
      return true;
    }
    return true;
  }

  void _nextStep() {
    if (_validateStep(_currentStep)) {
      if (_currentStep < 3) {
        setState(() => _currentStep++);
      } else {
        _submit();
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _submit() async {
    if (!_validateStep(3)) return;

    final researchConsent = await requestRegistrationConsent(
      context,
      patient: false,
    );
    if (researchConsent == null || !mounted) return;
    setState(() => _loading = true);

    try {
      await _authService.registerDoctor(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        consentAccepted: true,
        researchConsent: researchConsent,
        mobileNumber: _mobileController.text.trim(),
        country: _countryController.text.trim(),
        state: _stateController.text.trim(),
        city: _cityController.text.trim(),
        registrationNumber: _regNumberController.text.trim(),
        regulatoryCouncil: _councilController.text.trim(),
        qualification: _qualificationController.text.trim(),
        specialization: _specializationController.text.trim(),
        hospital: _hospitalController.text.trim(),
        yearsExperience: _experienceController.text.trim(),
        registrationCertName: _registrationCertFile?.name,
        professionalIdName: _professionalIdFile?.name,
      );

      if (!mounted) return;

      // Pop back to root AuthGate which will show DoctorPendingApprovalScreen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showError(tr('An account already exists with this email address.'));
      } else if (e.code == 'weak-password') {
        _showError(tr('Please choose a stronger password.'));
      } else {
        _showError(e.message ?? tr('Registration failed. Please try again.'));
      }
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Doctor Registration'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [LanguageToggleButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 28,
              vertical: 18,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header branding
                  Center(
                    child: Image.asset(
                      'assets/icon/haemophysio_logo.png',
                      height: 52,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: AppText(
                      'Somaiya HemoPhysio',
                      style: TextStyle(
                        fontSize: compact ? 20 : 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Center(
                    child: Text(
                      tr('Clinician Credential Registration'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Progress Step Header
                  _buildStepIndicator(primary),
                  const SizedBox(height: 20),

                  // Step Content
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 18 : 26),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _buildCurrentStepContent(compact),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Navigation buttons
                  Row(
                    children: [
                      if (_currentStep > 0) ...[
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: _loading ? null : _prevStep,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(tr('Previous')),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 3,
                        child: FilledButton(
                          onPressed: _loading ? null : _nextStep,
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
                                  _currentStep == 3
                                      ? tr('Submit Registration')
                                      : tr('Next'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        tr('Already have a clinician account?'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(tr('Sign In')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(Color primary) {
    final stepTitles = [
      tr('Personal'),
      tr('Professional'),
      tr('Documents'),
      tr('Declaration'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: List.generate(4, (index) {
          final isPast = index < _currentStep;
          final isCurrent = index == _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? primary
                              : (isPast
                                    ? Colors.green.shade600
                                    : Colors.grey.shade300),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isPast
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : AppText(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: (isCurrent || isPast)
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepTitles[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isCurrent ? primary : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < 3)
                  Container(
                    width: 12,
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: index < _currentStep
                        ? Colors.green.shade600
                        : Colors.grey.shade300,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStepContent(bool compact) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Personal(compact);
      case 1:
        return _buildStep2Professional(compact);
      case 2:
        return _buildStep3Documents(compact);
      case 3:
      default:
        return _buildStep4Declaration(compact);
    }
  }

  Widget _buildStep1Personal(bool compact) {
    return Column(
      key: const ValueKey('step_1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.person_outline_rounded, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Personal Information'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr('Provide your legal contact and identity details.'),
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _fullNameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Full Name'),
            hintText: 'Dr. Jane Doe',
            prefixIcon: const Icon(Icons.person_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: tr('Email Address'),
            hintText: 'doctor@somaiya.edu',
            prefixIcon: const Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: tr('Mobile Number'),
            hintText: '+91 98765 43210',
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        if (compact) ...[
          TextField(
            controller: _cityController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('City'),
              prefixIcon: const Icon(Icons.location_city_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stateController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('State / Province'),
              prefixIcon: const Icon(Icons.map_outlined),
            ),
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cityController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: tr('City'),
                    prefixIcon: const Icon(Icons.location_city_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _stateController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: tr('State / Province'),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _countryController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Country'),
            prefixIcon: const Icon(Icons.public_outlined),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 10),
        Text(
          tr('Account Password'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: tr('Password'),
            helperText: tr('At least 6 characters'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: tr('Confirm Password'),
            prefixIcon: const Icon(Icons.lock_clock_outlined),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              icon: Icon(
                _obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Professional(bool compact) {
    return Column(
      key: const ValueKey('step_2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.medical_services_outlined, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Professional Information'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr('Enter your medical council registration and practice details.'),
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _regNumberController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr('Medical Registration Number'),
            hintText: 'e.g. MMC/2018/12345',
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _councilController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Medical Council / Regulatory Authority'),
            hintText: 'e.g. Maharashtra Council / IAP',
            prefixIcon: const Icon(Icons.account_balance_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _qualificationController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr('Medical Qualification'),
            hintText: 'e.g. BPT, MPT, MBBS',
            prefixIcon: const Icon(Icons.school_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _specializationController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Medical Specialization'),
            hintText: 'e.g. Orthopedic Rehab, Hemophilia Therapy',
            prefixIcon: const Icon(Icons.healing_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hospitalController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Hospital / Organization'),
            hintText: 'e.g. K. J. Somaiya Hospital',
            prefixIcon: const Icon(Icons.local_hospital_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _experienceController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('Years of Experience'),
            hintText: 'e.g. 5',
            prefixIcon: const Icon(Icons.timer_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Documents(bool compact) {
    return Column(
      key: const ValueKey('step_3'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.description_outlined, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Professional Documents'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            'Upload clear scans or photos of your credentials (PDF, JPG, PNG). Max 10MB.',
          ),
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 18),

        // Document 1
        _documentUploadTile(
          title: tr('Medical Registration Certificate'),
          file: _registrationCertFile,
          onPick: () => _pickDocument(isCert: true),
          onRemove: () => setState(() => _registrationCertFile = null),
        ),
        const SizedBox(height: 16),

        // Document 2
        _documentUploadTile(
          title: tr('Professional ID Document'),
          file: _professionalIdFile,
          onPick: () => _pickDocument(isCert: false),
          onRemove: () => setState(() => _professionalIdFile = null),
        ),
      ],
    );
  }

  Widget _documentUploadTile({
    required String title,
    required PlatformFile? file,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: file != null
            ? Colors.green.shade50.withValues(alpha: 0.5)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: file != null ? Colors.green.shade300 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                file != null
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                color: file != null ? Colors.green.shade700 : Colors.blueGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (file != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onRemove,
                  ),
                ],
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(tr('Upload Document')),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep4Declaration(bool compact) {
    return Column(
      key: const ValueKey('step_4'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Verification & Approval'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Colors.blue.shade800,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(
                    'All doctor and physiotherapist accounts require credential verification by an administrator before clinical dashboard access is granted. You will be notified once your registration is approved.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade900,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Registration Summary'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              _summaryRow(
                tr('Name:'),
                'Dr. ${_fullNameController.text.trim()}',
              ),
              _summaryRow(tr('Email:'), _emailController.text.trim()),
              _summaryRow(
                tr('Registration No:'),
                _regNumberController.text.trim(),
              ),
              _summaryRow(tr('Council:'), _councilController.text.trim()),
              _summaryRow(tr('Hospital:'), _hospitalController.text.trim()),
              _summaryRow(
                tr('Documents:'),
                '${_registrationCertFile != null ? 1 : 0} cert, ${_professionalIdFile != null ? 1 : 0} ID',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _declarationChecked,
          onChanged: (val) =>
              setState(() => _declarationChecked = val ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            tr(
              'I hereby declare that all information and uploaded documents provided are authentic, accurate, and valid under medical regulatory authority guidelines.',
            ),
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value.isEmpty ? 'â€”' : value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

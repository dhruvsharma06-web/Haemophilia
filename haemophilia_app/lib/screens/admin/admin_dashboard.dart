import '../../widgets/app_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/admin_service.dart';
import '../../widgets/patient_screening_card.dart';
import '../../utils/firebase_errors.dart';
import '../support/help_screen.dart';
import '../../services/clinical_data_service.dart';
import '../../utils/app_localizations.dart';
import 'add_doctor_screen.dart';

class AdminDashboard extends StatefulWidget {
  final UserModel user;

  const AdminDashboard({super.key, required this.user});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _isLoggingOut = false;
  int _section = 0;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    try {
      await AuthService().logout();
    } catch (e) {
      debugPrint('Logout error: $e');
    }

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final user = widget.user;
    final service = ClinicalDataService();

    return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset(
                  'assets/icon/haemophysio_logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    tr('Admin'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        actions: [
          const LanguageToggleButton(),
          IconButton(tooltip: tr('Add doctor'), icon: const Icon(Icons.person_add_alt_1), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddDoctorScreen()))),
          IconButton(
            tooltip: tr('Log out'),
            onPressed: _isLoggingOut ? null : _logout,
            icon: _isLoggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchAllUsers(),
        builder: (context, snapshot) {
          final pending = snapshot.data?.docs.where(_isNewPatient).length ?? 0;
          return NavigationBar(
            selectedIndex: _section,
            onDestinationSelected: (value) => setState(() => _section = value),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text(pending > 99 ? '99+' : '$pending'),
                  child: const Icon(Icons.person_add_alt_1_outlined),
                ),
                label: tr('New patients'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.manage_accounts_outlined),
                label: tr('Manage Users'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.how_to_reg),
                label: tr('Doctor approvals'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.support_agent),
                label: tr('Grievances'),
              ),
            ],
          );
        },
      ),
      body: _section == 3 ? const HelpScreen(admin:true) : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(firebaseErrorMessage(snapshot.error, fallback: 'Could not load users.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final docs = _section == 0
              ? allDocs.where(_isNewPatient).toList()
              : _section == 2
              ? allDocs.where((doc) => doc.data()['role'] == 'pending_doctor' ||
                  (doc.data()['role'] == 'doctor' && doc.data()['isApproved'] == false)).toList()
              : allDocs.toList();
          if (_section == 0) {
            docs.sort((a, b) => _createdAt(b.data()).compareTo(_createdAt(a.data())));
          }
          final doctors =
              allDocs.where((doc) => doc.data()['role'] == 'doctor').length;
          final patients =
              allDocs.where((doc) => doc.data()['role'] == 'patient').length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              _Hero(
                title: '${tr('Welcome back,')} ${user.name}',
                subtitle:
                    tr('Manage accounts, doctor assignments and platform access.'),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = [
                    _Metric(
                      tr('Doctors'),
                      '$doctors',
                      Icons.medical_services_outlined,
                    ),
                    _Metric(
                      tr('Patients'),
                      '$patients',
                      Icons.people_outline,
                    ),
                    _Metric(
                      tr('Total Users'),
                      '${allDocs.length}',
                      Icons.groups_outlined,
                    ),
                  ];

                  if (constraints.maxWidth < 650) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: metrics[0]),
                            const SizedBox(width: 10),
                            Expanded(child: metrics[1]),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: metrics[2]),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      for (var i = 0; i < metrics.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: metrics[i]),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                tr(_section == 0 ? 'New patients' : _section == 2 ? 'Doctor approvals' : 'Manage Users'),
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                tr(_section == 0
                    ? 'Patients waiting for a doctor. Review screening and assign a clinician.'
                    : _section == 2
                    ? 'Review clinician applications before granting access.'
                    : 'Manage existing accounts and doctor transfers.'),
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              if (docs.isEmpty)
                _Empty(message: _section == 0 ? 'No patients are waiting for a doctor.' :
                    _section == 2 ? 'No doctor applications are waiting.' : 'No users found.')
              else
                ...docs.map(
                  (doc) => _section == 0
                      ? _NewPatientCard(doc: doc)
                      : _UserCard(doc: doc, currentAdminId: user.uid),
                ),
            ],
          );
        },
      ),
    );
  }
}

bool _isNewPatient(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final doctorId = data['doctorId']?.toString().trim();
  return data['role'] == 'patient' && data['accountActive'] != false &&
      (doctorId == null || doctorId.isEmpty);
}

DateTime _createdAt(Map<String, dynamic> data) =>
    (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

class _NewPatientCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _NewPatientCard({required this.doc});

  Future<void> _assign(BuildContext context) async {
    final doctors = await ClinicalDataService().getDoctors();
    if (!context.mounted) return;
    if (doctors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('No approved doctors are available.'))),
      );
      return;
    }
    String? selectedDoctor;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          AppLocaleScope.of(dialogContext);
          return AlertDialog(
            title: Text(tr('Assign doctor')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.data()['name']?.toString() ?? tr('Patient')),
                    const SizedBox(height: 12),
                    PatientScreeningCard(data: doc.data()),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDoctor,
                      decoration: InputDecoration(labelText: tr('Approved doctor')),
                      items: doctors.map((doctor) => DropdownMenuItem(
                        value: doctor.id,
                        child: Text(doctor.data()['name']?.toString() ?? tr('Doctor')),
                      )).toList(),
                      onChanged: saving ? null : (value) => setDialogState(() => selectedDoctor = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(tr('Cancel')),
              ),
              FilledButton(
                onPressed: saving || selectedDoctor == null ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    await AdminService().manageUser(
                      uid: doc.id, role: 'patient', active: true,
                      doctorId: selectedDoctor, requireUnassigned: true,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('Doctor assigned.'))),
                      );
                    }
                  } catch (error) {
                    if (dialogContext.mounted) setDialogState(() => saving = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error is StateError
                            ? tr(error.message.toString())
                            : error is FirebaseException && error.code == 'permission-denied'
                                ? tr('Firebase access settings are blocking patient assignment. Contact the project owner.')
                                : firebaseErrorMessage(error))),
                      );
                    }
                  }
                },
                child: Text(tr('Assign')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final data = doc.data();
    final createdAt = _createdAt(data);
    final hasDate = createdAt.millisecondsSinceEpoch > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['name']?.toString() ?? tr('Patient'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(data['patientId']?.toString() ?? doc.id),
            if (hasDate) Text('${tr('Registered')}: ${createdAt.day}/${createdAt.month}/${createdAt.year}'),
            const SizedBox(height: 12),
            PatientScreeningCard(data: data),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  try { await _assign(context); }
                  catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(firebaseErrorMessage(error, fallback: 'Could not load doctors.'))),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(tr('Assign doctor')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String currentAdminId;

  const _UserCard({
    required this.doc,
    required this.currentAdminId,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final data = doc.data();
    final role = data['role']?.toString() ?? 'patient';
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: primary.withValues(alpha: .10),
              child: Text(
                data['name']?.toString().isNotEmpty == true
                    ? data['name'].toString()[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['name']?.toString() ?? 'User',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data['email']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tr(role),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (doc.id != currentAdminId)
              IconButton(
                tooltip: tr('Manage'),
                onPressed: () => _manage(context, doc),
                icon: const Icon(Icons.tune_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _manage(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final service = ClinicalDataService();
    final data = doc.data();

    var role = data['role']?.toString() ?? 'patient';
    if (!['patient','pending_doctor','doctor','admin'].contains(role)) role='patient';
    String? doctorId = data['doctorId']?.toString();
    var active = data['accountActive'] != false;
    var saving = false;

    List<QueryDocumentSnapshot<Map<String, dynamic>>> doctors;
    try {
      doctors = await service.getDoctors();
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(firebaseErrorMessage(error, fallback: 'Could not load doctors.'))));
      return;
    }
    if (doctorId != null && !doctors.any((doc)=>doc.id==doctorId)) doctorId=null;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            AppLocaleScope.of(dialogContext);
            final doctorItems = <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: AppText('Unassigned'),
              ),
              ...doctors.map(
                (doctor) => DropdownMenuItem<String?>(
                  value: doctor.id,
                  child: Text(
                    doctor.data()['name']?.toString() ?? 'Doctor',
                  ),
                ),
              ),
            ];

            return AlertDialog(
              title: Text(data['name']?.toString() ?? 'User'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(labelText: tr('Role')),
                      items: const ['patient', 'pending_doctor', 'doctor', 'admin']
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(tr(value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => role = value);
                        }
                      },
                    ),
                    SwitchListTile(title: Text(tr('Account active')), value: active, onChanged: saving ? null : (v) => setDialogState(() => active = v)),
                    Text(tr('Set the role to Doctor to approve an application. Disable account access to remove a doctor while retaining records.')),
                    if (data['registrationNumber'] != null) AppText('${tr('Medical Registration Number')}: ${data['registrationNumber']}'),
                    if (data['qualification'] != null) AppText('${tr('Qualification')}: ${data['qualification']}'),
                    if (data['specialization'] != null) AppText('${tr('Specialization')}: ${data['specialization']}'),
                    if (data['hospital'] != null) AppText('${tr('Hospital / Clinic')}: ${data['hospital']}'),
                    if (role == 'patient') PatientScreeningCard(data: data),
                    const SizedBox(height: 14),
                    if (role == 'patient')
                      DropdownButtonFormField<String?>(
                        initialValue: doctors.any((d) => d.id == doctorId)
                            ? doctorId
                            : null,
                        decoration: InputDecoration(
                          labelText: tr('Assigned doctor'),
                        ),
                        items: doctorItems,
                        onChanged: (value) {
                          setDialogState(() => doctorId = value);
                        },
                      ),
                  ],
                )),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const AppText('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : () async {
                    try {
                      setDialogState(() => saving = true);
                      await AdminService().manageUser(uid: doc.id, role: role, active: active, doctorId: role == 'patient' ? doctorId : null);

                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: AppText('User updated.')),
                      );
                    } catch (e) {
                      if (dialogContext.mounted) setDialogState(() => saving = false);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e is StateError ? tr(e.message.toString()) : firebaseErrorMessage(e, fallback: 'Could not update user. Please try again.')),
                        ),
                      );
                    }
                  },
                  child: const AppText('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Hero({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .88),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _Metric(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Text(
            tr(message),
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

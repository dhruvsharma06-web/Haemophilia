import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/clinical_data_service.dart';
import '../auth/login_screen.dart';

class AdminDashboard extends StatelessWidget {
  final UserModel user;

  const AdminDashboard({super.key, required this.user});

  Future<void> _logout(BuildContext context) async {
    await AuthService().logout();
    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ClinicalDataService();
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.admin_panel_settings_outlined,
                color: primary,
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Admin Portal',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load users.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          final doctors =
              docs.where((doc) => doc.data()['role'] == 'doctor').length;
          final patients =
              docs.where((doc) => doc.data()['role'] == 'patient').length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              _Hero(
                title: 'Welcome, ${user.name}',
                subtitle:
                    'Manage accounts, doctor assignments and platform access.',
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = [
                    _Metric(
                      'Doctors',
                      '$doctors',
                      Icons.medical_services_outlined,
                    ),
                    _Metric(
                      'Patients',
                      '$patients',
                      Icons.people_outline,
                    ),
                    _Metric(
                      'Users',
                      '${docs.length}',
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
              const Text(
                'User management',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Promote existing accounts and assign patients to doctors.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              if (docs.isEmpty)
                const _Empty()
              else
                ...docs.map(
                  (doc) => _UserCard(
                    doc: doc,
                    currentAdminId: user.uid,
                  ),
                ),
            ],
          );
        },
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
                  fontWeight: FontWeight.w800,
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
                      role.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (doc.id != currentAdminId)
              IconButton(
                tooltip: 'Manage',
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
    String? doctorId = data['doctorId']?.toString();

    final doctors = await service.getDoctors();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final doctorItems = <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Unassigned'),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const ['patient', 'doctor', 'admin']
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => role = value);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    if (role == 'patient')
                      DropdownButtonFormField<String?>(
                        value: doctors.any((d) => d.id == doctorId)
                            ? doctorId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Assigned doctor',
                        ),
                        items: doctorItems,
                        onChanged: (value) {
                          setDialogState(() => doctorId = value);
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await service.updateUserRole(
                        uid: doc.id,
                        role: role,
                      );

                      if (role == 'patient') {
                        await service.assignDoctor(
                          patientId: doc.id,
                          doctorId: doctorId,
                        );
                      } else {
                        await service.assignDoctor(
                          patientId: doc.id,
                          doctorId: null,
                        );
                      }

                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User updated.')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not update user: $e'),
                        ),
                      );
                    }
                  },
                  child: const Text('Save'),
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
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, const Color(0xFF63B4E8), .45)!,
          ],
        ),
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
              fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w800,
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
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Text(
            'No users found.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

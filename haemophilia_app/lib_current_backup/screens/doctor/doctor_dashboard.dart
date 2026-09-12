import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/clinical_data_service.dart';
import '../auth/login_screen.dart';
import '../patient/patient_history.dart';
import 'doctor_patient_detail.dart';

class DoctorDashboard extends StatelessWidget {
  final UserModel user;

  const DoctorDashboard({super.key, required this.user});

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
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _BrandMark(color: primary, icon: Icons.medical_services_outlined),
            const SizedBox(width: 10),
            const Text(
              'Clinician Portal',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ClinicalDataService().watchAssignedPatients(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorState(message: snapshot.error.toString());
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final patients = snapshot.data?.docs ?? [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              children: [
                _Hero(
                  title: 'Welcome, Dr. ${user.name}',
                  subtitle:
                      'Review patient progress, movement quality and clinical feedback.',
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        'Patients',
                        '${patients.length}',
                        Icons.people_outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Metric(
                        'Assigned',
                        '${patients.length}',
                        Icons.assignment_ind_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Your patients',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Open a patient to review sessions and errors.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                if (patients.isEmpty)
                  const _EmptyCard()
                else
                  ...patients.map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PatientCard(doc: doc),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _PatientCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final primary = Theme.of(context).colorScheme.primary;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ClinicalDataService().watchPatientAssessments(doc.id),
      builder: (context, snapshot) {
        final assessments = snapshot.data?.docs ?? [];
        final sessions = groupAssessmentSessions(assessments);
        final latest = sessions.isEmpty ? null : sessions.first;

        final patient = UserModel.fromMap(doc.id, data);

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorPatientDetail(
                    patientId: doc.id,
                    patient: patient,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: primary.withValues(alpha: .10),
                    child: Text(
                      data['name']?.toString().isNotEmpty == true
                          ? data['name'].toString()[0].toUpperCase()
                          : 'P',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name']?.toString() ?? 'Patient',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          latest == null
                              ? 'No assessments yet'
                              : 'Latest session • ${latest.averageScore.toStringAsFixed(0)}/100',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _BrandMark({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 22),
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
  final String title;
  final String value;
  final IconData icon;

  const _Metric(this.title, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            const Text(
              'No patients assigned',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 5),
            Text(
              'Ask an administrator to assign patients to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load patients.\n\n$message',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

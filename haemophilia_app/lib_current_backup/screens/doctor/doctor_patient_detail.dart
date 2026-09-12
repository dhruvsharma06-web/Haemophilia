import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/clinical_data_service.dart';
import '../patient/patient_history.dart';
import 'doctor_messages.dart';
import 'doctor_session_detail.dart';

class DoctorPatientDetail extends StatelessWidget {
  final String patientId;
  final UserModel patient;

  const DoctorPatientDetail({
    super.key,
    required this.patientId,
    required this.patient,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          patient.name.isEmpty ? 'Patient' : patient.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ClinicalDataService().watchPatientAssessments(patientId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load patient data.\n\n${snapshot.error}',
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
          final sessions = groupAssessmentSessions(docs);

          final reps = docs.length;
          final correct = docs.where((doc) {
            final form = doc.data()['form']?.toString().toLowerCase() ?? '';
            return form.contains('correct') && !form.contains('incorrect');
          }).length;

          final avg = sessions.isEmpty
              ? 0.0
              : sessions
                      .map((session) => session.averageScore)
                      .reduce((a, b) => a + b) /
                  sessions.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _ProfileCard(patient: patient),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DoctorMessages(
                        patientId: patientId,
                        patient: patient,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Message patient'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      'Average score',
                      sessions.isEmpty ? '—' : '${avg.toStringAsFixed(0)}/100',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat('Sessions', '${sessions.length}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      'Correct reps',
                      reps == 0 ? '—' : '$correct/$reps',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const Text(
                'Session history',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (sessions.isEmpty)
                const _Empty()
              else
                ...sessions.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: const Icon(Icons.assignment_outlined),
                        title: Text(
                          session.exercise,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${session.reps} reps • ${session.correctReps}/${session.reps} correct',
                        ),
                        trailing: Text(
                          '${session.averageScore.toStringAsFixed(0)}/100',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DoctorSessionDetail(
                                patientId: patientId,
                                patient: patient,
                                session: session,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserModel patient;

  const _ProfileCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: primary.withValues(alpha: .1),
              child: Text(
                patient.name.isEmpty
                    ? 'P'
                    : patient.name[0].toUpperCase(),
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    patient.email,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
        padding: const EdgeInsets.all(25),
        child: Center(
          child: Text(
            'No assessment sessions yet.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

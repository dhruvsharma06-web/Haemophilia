import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/clinical_data_service.dart';
import '../patient/patient_history.dart';
import '../profile/edit_profile_screen.dart';
import 'doctor_patient_detail.dart';
import '../../utils/exercise_utils.dart';

class DoctorDashboard extends StatefulWidget {
  final UserModel user;

  const DoctorDashboard({super.key, required this.user});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  bool _isLoggingOut = false;

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
    final currentUser = widget.user;

    return Scaffold(
          appBar: AppBar(
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/icon/haemophysio_logo.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text(
                    'HaemoPhysio',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Edit Profile',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(user: currentUser),
                    ),
                  );
                },
                icon: const Icon(Icons.person_outline_rounded),
              ),
              IconButton(
                tooltip: 'Log out',
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
                      title: 'Welcome, Dr. ${currentUser.name}',
                      subtitle:
                          'Review patient progress, movement quality and clinical feedback.',
                    ),
                    const SizedBox(height: 24),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('exerciseAssignments')
                          .where('doctorId', isEqualTo: currentUser.uid)
                          .snapshots(),
                      builder: (context, assignSnap) {
                        final assignDocs = assignSnap.data?.docs ?? [];

                        final uniquePatientIds = <String>{};
                        for (final p in patients) {
                          if (p.id.isNotEmpty) uniquePatientIds.add(p.id);
                        }
                        for (final a in assignDocs) {
                          final pid = a.data()['patientId']?.toString() ?? a.id;
                          if (pid.isNotEmpty) uniquePatientIds.add(pid);
                        }

                        return _Metric(
                          'Assigned Patients',
                          '${uniquePatientIds.length}',
                          Icons.people_outline,
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _LiveAssessmentSection(
                      doctorId: currentUser.uid,
                      patients: patients,
                    ),
                    const Text(
                      'Your patients',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Open a patient to review sessions and errors.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 14),
                    () {
                      final uniquePatientDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
                      for (final doc in patients) {
                        uniquePatientDocs[doc.id] = doc;
                      }
                      final patientList = uniquePatientDocs.values.toList();

                      if (patientList.isEmpty) {
                        return const _EmptyCard();
                      }

                      return Column(
                        children: patientList
                            .map(
                              (doc) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _PatientCard(doc: doc),
                              ),
                            )
                            .toList(),
                      );
                    }(),
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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('exerciseAssignments')
          .doc(doc.id)
          .snapshots(),
      builder: (context, assignmentSnap) {
        final assignData = assignmentSnap.data?.data();
        final assignStatus = assignData?['status']?.toString().toLowerCase();
        final isPaused = assignStatus == 'paused';
        final isInProgress = assignStatus == 'in_progress';
        final sessionName = assignData?['sessionName']?.toString();
        final progressPct =
            (assignData?['progressPercentage'] as num?)?.toInt() ?? 0;

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
                          patient.name.isNotEmpty
                              ? patient.name[0].toUpperCase()
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
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    patient.name.isNotEmpty
                                        ? patient.name
                                        : 'Patient',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (isPaused)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.amber.shade400),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.pause_circle_outline,
                                            size: 11,
                                            color: Colors.amber.shade900),
                                        const SizedBox(width: 3),
                                        Text(
                                          'PAUSED ($progressPct%)',
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (isInProgress)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.blue.shade400),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_circle_outline,
                                            size: 11,
                                            color: Colors.blue.shade900),
                                        const SizedBox(width: 3),
                                        Text(
                                          'IN PROGRESS ($progressPct%)',
                                          style: TextStyle(
                                            color: Colors.blue.shade900,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isPaused
                                  ? '${sessionName ?? "Session"} paused • $progressPct% complete'
                                  : isInProgress
                                      ? '${sessionName ?? "Session"} in progress • $progressPct%'
                                      : latest == null
                                          ? 'No assessments yet'
                                          : 'Latest session • ${latest.averageScore.toStringAsFixed(0)}/100',
                              style: TextStyle(
                                color: isPaused
                                    ? Colors.amber.shade800
                                    : isInProgress
                                        ? Colors.blue.shade800
                                        : Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: (isPaused || isInProgress)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
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

class _LiveAssessmentSection extends StatelessWidget {
  final String doctorId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> patients;

  const _LiveAssessmentSection({
    required this.doctorId,
    required this.patients,
  });

  @override
  Widget build(BuildContext context) {
    final patientMap = {for (var p in patients) p.id: p};

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ClinicalDataService().watchActiveDoctorSessions(doctorId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final docs = snapshot.data!.docs;
        final now = DateTime.now();

        // 1. Active sessions (exclude stale sessions where no update happened in the last 20 minutes)
        final activeSessions = docs.where((d) {
          final data = d.data();
          final status = data['status']?.toString().toLowerCase();
          if (status != 'active' && status != 'in_progress') return false;

          final lastUpdated = data['lastUpdatedAt'] ?? data['startedAt'];
          if (lastUpdated is Timestamp) {
            final diff = now.difference(lastUpdated.toDate().toLocal());
            if (diff.inMinutes > 20) return false;
          }
          return true;
        }).toList();

        // 2. Paused sessions (within last 24 hours)
        final pausedSessions = docs.where((d) {
          final data = d.data();
          final status = data['status']?.toString().toLowerCase();
          if (status != 'paused') return false;

          final pausedAt = data['pausedAt'] ?? data['lastUpdatedAt'] ?? data['updatedAt'];
          if (pausedAt is Timestamp) {
            final diff = now.difference(pausedAt.toDate().toLocal());
            if (diff.inHours > 24) return false;
          }
          return true;
        }).toList();

        // 3. Completed sessions in the last 30 minutes
        final recentlyCompleted = docs.where((d) {
          final data = d.data();
          final status = data['status']?.toString().toLowerCase();
          if (status != 'completed') return false;
          final completedAt =
              data['completedAt'] ?? data['endedAt'] ?? data['lastUpdatedAt'];
          if (completedAt is Timestamp) {
            final diff = now.difference(completedAt.toDate().toLocal());
            return diff.inMinutes <= 30;
          }
          return false;
        }).toList();

        if (activeSessions.isEmpty && pausedSessions.isEmpty && recentlyCompleted.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeSessions.isNotEmpty) ...[
              const Row(
                children: [
                  _PulsingLiveDot(),
                  SizedBox(width: 8),
                  Text(
                    'Active Live Assessments',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...activeSessions.map((sessionDoc) {
                final data = sessionDoc.data();
                final patientId = data['patientId']?.toString() ?? '';
                final patientDoc = patientMap[patientId];
                final patientName = formatFullName(
                    data['patientName']?.toString().isNotEmpty == true
                        ? data['patientName'].toString()
                        : (patientDoc?.data()['name']?.toString() ?? 'Patient'));
                final patientUser = patientDoc != null
                    ? UserModel.fromMap(patientDoc.id, patientDoc.data())
                    : UserModel(
                        uid: patientId,
                        name: patientName,
                        email: '',
                        role: 'patient');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LiveSessionCard(
                    sessionData: data,
                    patientName: patientName,
                    patient: patientUser,
                  ),
                );
              }),
            ],
            if (pausedSessions.isNotEmpty) ...[
              if (activeSessions.isNotEmpty) const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.pause_circle_outline_rounded,
                      color: Color(0xFFF57F17), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Paused Assessments (${pausedSessions.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF57F17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...pausedSessions.map((sessionDoc) {
                final data = sessionDoc.data();
                final patientId = data['patientId']?.toString() ?? '';
                final patientDoc = patientMap[patientId];
                final patientName = formatFullName(
                    data['patientName']?.toString().isNotEmpty == true
                        ? data['patientName'].toString()
                        : (patientDoc?.data()['name']?.toString() ?? 'Patient'));
                final patientUser = patientDoc != null
                    ? UserModel.fromMap(patientDoc.id, patientDoc.data())
                    : UserModel(
                        uid: patientId,
                        name: patientName,
                        email: '',
                        role: 'patient');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PausedSessionCard(
                    sessionData: data,
                    patientName: patientName,
                    patient: patientUser,
                  ),
                );
              }),
            ],
            if (recentlyCompleted.isNotEmpty) ...[
              if (activeSessions.isNotEmpty || pausedSessions.isNotEmpty)
                const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2E7D32), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Recently Completed Assessments',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...recentlyCompleted.map((sessionDoc) {
                final data = sessionDoc.data();
                final patientId = data['patientId']?.toString() ?? '';
                final patientDoc = patientMap[patientId];
                final patientName = formatFullName(
                    data['patientName']?.toString().isNotEmpty == true
                        ? data['patientName'].toString()
                        : (patientDoc?.data()['name']?.toString() ?? 'Patient'));
                final patientUser = patientDoc != null
                    ? UserModel.fromMap(patientDoc.id, patientDoc.data())
                    : UserModel(
                        uid: patientId,
                        name: patientName,
                        email: '',
                        role: 'patient');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RecentlyCompletedSessionCard(
                    sessionData: data,
                    patientName: patientName,
                    patient: patientUser,
                  ),
                );
              }),
            ],
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  final Map<String, dynamic> sessionData;
  final String patientName;
  final UserModel patient;

  const _LiveSessionCard({
    required this.sessionData,
    required this.patientName,
    required this.patient,
  });

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate().toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final diff = DateTime.now().difference(dt);
      final ago = diff.inMinutes < 1 ? 'just now' : '${diff.inMinutes}m ago';
      return '$h:$m $ampm ($ago)';
    }
    return 'Active';
  }

  @override
  Widget build(BuildContext context) {
    final repCount = (sessionData['currentRepCount'] as num?)?.toInt() ?? 0;
    final score = (sessionData['currentScore'] as num?)?.toDouble() ?? 0.0;
    final form = sessionData['currentForm']?.toString() ?? 'Assessing...';
    final rawExercise = sessionData['currentExercise']?.toString() ??
        sessionData['exercise']?.toString() ??
        sessionData['sessionName']?.toString() ??
        '';
    final exercise = rawExercise.isNotEmpty
        ? getExerciseDisplayName(rawExercise)
        : 'Physiotherapy Assessment';
    final startedAt = sessionData['lastUpdatedAt'] ?? sessionData['startedAt'];

    final Color scoreColor = score >= 80
        ? const Color(0xFF2E7D32)
        : (score >= 50 ? const Color(0xFFE65100) : const Color(0xFFC62828));

    final Color formColor = form.toLowerCase().contains('incorrect') ||
            form.toLowerCase().contains('slow') ||
            form.toLowerCase().contains('fast') ||
            form.toLowerCase().contains('incomplete')
        ? const Color(0xFFE65100)
        : const Color(0xFF1565C0);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
      ),
      color: const Color(0xFFFFF9F9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulsingLiveDot(size: 8),
                      SizedBox(width: 5),
                      Text(
                        'LIVE ASSESSMENT',
                        style: TextStyle(
                          color: Color(0xFFD32F2F),
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(startedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        exercise,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorPatientDetail(
                          patientId: patient.uid,
                          patient: patient,
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child:
                      const Text('View Patient', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _LiveChip(
                  icon: Icons.repeat_rounded,
                  label: '$repCount reps',
                  color: const Color(0xFF1565C0),
                ),
                _LiveChip(
                  icon: Icons.speed_rounded,
                  label: '${score.toStringAsFixed(0)}/100',
                  color: scoreColor,
                ),
                _LiveChip(
                  icon: Icons.accessibility_new_rounded,
                  label: form,
                  color: formColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PausedSessionCard extends StatelessWidget {
  final Map<String, dynamic> sessionData;
  final String patientName;
  final UserModel patient;

  const _PausedSessionCard({
    required this.sessionData,
    required this.patientName,
    required this.patient,
  });

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate().toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final diff = DateTime.now().difference(dt);
      final ago = diff.inMinutes < 1
          ? 'just now'
          : (diff.inMinutes < 60
              ? '${diff.inMinutes}m ago'
              : '${diff.inHours}h ago');
      return '$h:$m $ampm ($ago)';
    }
    return 'Paused';
  }

  @override
  Widget build(BuildContext context) {
    final repCount = (sessionData['currentRepCount'] as num?)?.toInt() ??
        (sessionData['totalReps'] as num?)?.toInt() ??
        (sessionData['completedCorrectReps'] as num?)?.toInt() ??
        0;
    final score = (sessionData['currentScore'] as num?)?.toDouble() ?? 0.0;
    final form = sessionData['currentForm']?.toString() ?? 'Paused';
    final progressPct =
        (sessionData['progressPercentage'] as num?)?.toInt() ?? 0;
    final rawExercise = sessionData['currentExercise']?.toString() ??
        sessionData['exercise']?.toString() ??
        sessionData['sessionName']?.toString() ??
        '';
    final exercise = rawExercise.isNotEmpty
        ? getExerciseDisplayName(rawExercise)
        : 'Physiotherapy Assessment';
    final pausedAt = sessionData['pausedAt'] ??
        sessionData['lastUpdatedAt'] ??
        sessionData['updatedAt'];

    final Color scoreColor = score >= 80
        ? const Color(0xFF2E7D32)
        : (score >= 50 ? const Color(0xFFE65100) : const Color(0xFFC62828));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFE082), width: 1.5),
      ),
      color: const Color(0xFFFFFDF5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause_circle_outline_rounded,
                          size: 13, color: Color(0xFFF57F17)),
                      SizedBox(width: 4),
                      Text(
                        'PAUSED',
                        style: TextStyle(
                          color: Color(0xFFF57F17),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(pausedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patientName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        exercise,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorPatientDetail(
                          patientId: patient.uid,
                          patient: patient,
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child:
                      const Text('View Patient', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (progressPct > 0)
                  _LiveChip(
                    icon: Icons.pie_chart_outline_rounded,
                    label: '$progressPct% complete',
                    color: const Color(0xFFF57F17),
                  ),
                _LiveChip(
                  icon: Icons.repeat_rounded,
                  label: '$repCount reps',
                  color: const Color(0xFF1565C0),
                ),
                if (score > 0)
                  _LiveChip(
                    icon: Icons.speed_rounded,
                    label: '${score.toStringAsFixed(0)}/100',
                    color: scoreColor,
                  ),
                _LiveChip(
                  icon: Icons.accessibility_new_rounded,
                  label: form,
                  color: const Color(0xFF616161),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentlyCompletedSessionCard extends StatelessWidget {
  final Map<String, dynamic> sessionData;
  final String patientName;
  final UserModel patient;

  const _RecentlyCompletedSessionCard({
    required this.sessionData,
    required this.patientName,
    required this.patient,
  });

  @override
  Widget build(BuildContext context) {
    final finalReps = (sessionData['finalRepCount'] ??
            sessionData['currentRepCount'] as num?)
        ?.toInt() ??
        0;
    final finalScore = (sessionData['finalScore'] ??
            sessionData['averageScore'] ??
            sessionData['currentScore'] as num?)
        ?.toDouble() ??
        0.0;
    final rawExercise = sessionData['currentExercise']?.toString() ??
        sessionData['exercise']?.toString() ??
        sessionData['sessionName']?.toString() ??
        '';
    final exercise = rawExercise.isNotEmpty
        ? getExerciseDisplayName(rawExercise)
        : 'Physiotherapy Assessment';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFA5D6A7), width: 1.2),
      ),
      color: const Color(0xFFF1F8E9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF2E7D32),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$patientName completed $exercise',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Score: ${finalScore.toStringAsFixed(0)}/100 • $finalReps reps',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoctorPatientDetail(
                      patientId: patient.uid,
                      patient: patient,
                    ),
                  ),
                );
              },
              child: const Text('Review', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _LiveChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingLiveDot extends StatefulWidget {
  final double size;

  const _PulsingLiveDot({
    this.size = 10,
  });

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.4),
                  blurRadius: 4 * _animation.value,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

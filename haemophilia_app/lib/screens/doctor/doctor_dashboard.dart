import '../../services/local_test_config.dart';
import '../../utils/firebase_errors.dart';
import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/clinical_data_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/exercise_utils.dart';
import '../patient/patient_history.dart';
import '../profile/edit_profile_screen.dart';
import '../support/help_screen.dart';
import 'assign_exercises_screen.dart';
import 'doctor_patient_detail.dart';
import '../../widgets/notification_bell.dart';

class DoctorDashboard extends StatefulWidget {
  final UserModel user;

  const DoctorDashboard({super.key, required this.user});

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  bool _isLoggingOut = false;
  String _search = '';
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

  void _showAssignPatientPicker(BuildContext context, String doctorId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Select Patient to Assign'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: LocalTestConfig.database
                        .collection('users')
                        .where('role', isEqualTo: 'patient')
                        .where('doctorId', isEqualTo: doctorId)
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text(firebaseErrorMessage(snap.error)),
                        );
                      }
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            tr('No registered patients found.'),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final p = UserModel.fromMap(doc.id, doc.data());
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .10),
                              child: Text(
                                p.name.isNotEmpty
                                    ? p.name[0].toUpperCase()
                                    : 'P',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              p.name.isNotEmpty ? p.name : tr('Patient'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(p.email),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AssignExercisesScreen(
                                    patientId: p.uid,
                                    patient: p,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final currentUser = widget.user;
    final doctorId = LocalTestConfig.auth.currentUser?.uid ?? currentUser.uid;

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
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: AppText(
                'Somaiya HemoPhysio',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const NotificationBell(),
          const LanguageToggleButton(),
          IconButton(
            tooltip: tr('Edit Profile'),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (value) => setState(() => _section = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            label: tr('Patients'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.monitor_heart_outlined),
            label: tr('Live sessions'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.support_agent),
            label: tr('Help'),
          ),
        ],
      ),
      body: _section == 2
          ? const HelpScreen()
          : SafeArea(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: LocalTestConfig.database
                    .collection('users')
                    .where('role', isEqualTo: 'patient')
                    .where('doctorId', isEqualTo: doctorId)
                    .snapshots(),
                builder: (context, assignSnap) {
                  if (assignSnap.hasError) {
                    return _ErrorState(
                      message: firebaseErrorMessage(
                        assignSnap.error,
                        fallback: 'Could not load patient data.',
                      ),
                    );
                  }

                  if (assignSnap.connectionState == ConnectionState.waiting &&
                      !assignSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final assignDocs = assignSnap.data?.docs ?? [];

                  // Doctor-specific: strictly extract unique patient IDs from this doctor's exerciseAssignments
                  final uniquePatientIds = assignDocs.map((d) => d.id).toSet();

                  final patientIdList = uniquePatientIds.toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                    children: [
                      if (_section == 0) ...[
                        _Hero(
                          title: '${tr('Welcome, Dr.')} ${currentUser.name}',
                          subtitle: tr(
                            'Review patient progress, movement quality and clinical feedback.',
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Metric(
                          tr('Assigned Patients'),
                          '${uniquePatientIds.length}',
                          Icons.people_outline,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_section == 1)
                        _LiveAssessmentSection(doctorId: doctorId),
                      if (_section == 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr('Your patients'),
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tr(
                                      'Open a patient to review sessions and errors.',
                                    ),
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              tooltip: tr('Assign exercises to a patient'),
                              onPressed: () =>
                                  _showAssignPatientPicker(context, doctorId),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          decoration: InputDecoration(
                            labelText: tr('Search by patient ID'),
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (v) =>
                              setState(() => _search = v.trim().toUpperCase()),
                        ),
                        const SizedBox(height: 12),
                        if (patientIdList.isEmpty)
                          _EmptyCard(
                            onAssignPatient: () =>
                                _showAssignPatientPicker(context, doctorId),
                          )
                        else
                          Column(
                            children: patientIdList
                                .where(
                                  (id) =>
                                      _search.isEmpty ||
                                      ('SHP-${id.toUpperCase()}').contains(
                                        _search,
                                      ),
                                )
                                .map(
                                  (pid) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _PatientCard(patientId: pid),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final String patientId;

  const _PatientCard({required this.patientId});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: LocalTestConfig.database
          .collection('users')
          .doc(patientId)
          .snapshots(),
      builder: (context, userSnap) {
        final data = userSnap.data?.data() ?? {};
        final patient = UserModel.fromMap(patientId, data);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: LocalTestConfig.database
              .collection('exerciseAssignments')
              .doc(patientId)
              .snapshots(),
          builder: (context, assignmentSnap) {
            final assignData = assignmentSnap.data?.data();
            final assignStatus = assignData?['status']
                ?.toString()
                .toLowerCase();
            final isPaused = assignStatus == 'paused';
            final isInProgress = assignStatus == 'in_progress';
            final sessionName = assignData?['sessionName']?.toString();
            final progressPct =
                (assignData?['progressPercentage'] as num?)?.toInt() ?? 0;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ClinicalDataService().watchPatientAssessments(patientId),
              builder: (context, snapshot) {
                final assessments = snapshot.data?.docs ?? [];
                final sessions = groupAssessmentSessions(assessments);
                final latest = sessions.isEmpty ? null : sessions.first;

                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DoctorPatientDetail(
                            patientId: patientId,
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
                                fontWeight: FontWeight.w700,
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
                                  patient.patientId,
                                  style: TextStyle(
                                    color: primary,
                                    fontSize: 11,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        patient.name.isNotEmpty
                                            ? patient.name
                                            : tr('Patient'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    if (isPaused)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade400,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.pause_circle_outline,
                                              size: 11,
                                              color: Colors.amber.shade900,
                                            ),
                                            const SizedBox(width: 3),
                                            AppText(
                                              '${tr('PAUSED')} ($progressPct%)',
                                              style: TextStyle(
                                                color: Colors.amber.shade900,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (isInProgress)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.shade400,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.play_circle_outline,
                                              size: 11,
                                              color: Colors.blue.shade900,
                                            ),
                                            const SizedBox(width: 3),
                                            AppText(
                                              '${tr('IN PROGRESS')} ($progressPct%)',
                                              style: TextStyle(
                                                color: Colors.blue.shade900,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
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
                                      ? '${sessionName ?? tr("Session")} ${tr("paused")} • $progressPct% ${tr("complete")}'
                                      : isInProgress
                                      ? '${sessionName ?? tr("Session")} ${tr("in progress")} • $progressPct%'
                                      : latest == null
                                      ? tr('No assessments yet')
                                      : '${tr("Latest session")} • ${latest.averageScore.toStringAsFixed(0)}/100',
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
  final String title;
  final String value;
  final IconData icon;

  const _Metric(this.title, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
  final VoidCallback? onAssignPatient;

  const _EmptyCard({this.onAssignPatient});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            Text(
              tr('No patients assigned'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 5),
            Text(
              tr('Ask an administrator to assign patients to your account.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (onAssignPatient != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAssignPatient,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(tr('Assign exercises to a patient')),
              ),
            ],
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
    AppLocaleScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppText(
          '${tr("Could not load patients.")}\n\n$message',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _LiveAssessmentSection extends StatelessWidget {
  final String doctorId;

  const _LiveAssessmentSection({required this.doctorId});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ClinicalDataService().watchActiveDoctorSessions(doctorId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(firebaseErrorMessage(snapshot.error));
        }
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final docs =
            snapshot.data!
                .where((doc) => doc.data()['practice'] != true)
                .toList()
              ..sort(
                (a, b) =>
                    ((b.data()['completedAt'] ??
                                    b.data()['lastUpdatedAt'] ??
                                    b.data()['startedAt'])
                                is Timestamp
                            ? ((b.data()['completedAt'] ??
                                          b.data()['lastUpdatedAt'] ??
                                          b.data()['startedAt'])
                                      as Timestamp)
                                  .millisecondsSinceEpoch
                            : 0)
                        .compareTo(
                          (a.data()['completedAt'] ??
                                      a.data()['lastUpdatedAt'] ??
                                      a.data()['startedAt'])
                                  is Timestamp
                              ? ((a.data()['completedAt'] ??
                                            a.data()['lastUpdatedAt'] ??
                                            a.data()['startedAt'])
                                        as Timestamp)
                                    .millisecondsSinceEpoch
                              : 0,
                        ),
              );
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

        // Paused work remains visible until completed or discarded.
        final pausedSessions = docs.where((d) {
          final data = d.data();
          final status = data['status']?.toString().toLowerCase();
          if (status != 'paused') return false;

          return true;
        }).toList();

        // Completed sessions from the past week, newest first.
        final recentlyCompleted = docs
            .where((d) {
              final data = d.data();
              final status = data['status']?.toString().toLowerCase();
              if (status != 'completed') return false;
              final completedAt =
                  data['completedAt'] ??
                  data['endedAt'] ??
                  data['lastUpdatedAt'];
              if (completedAt is Timestamp) {
                final diff = now.difference(completedAt.toDate().toLocal());
                return diff.inDays <= 7;
              }
              return false;
            })
            .take(10)
            .toList();

        if (activeSessions.isEmpty &&
            pausedSessions.isEmpty &&
            recentlyCompleted.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(tr('No recent sessions yet.')),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeSessions.isNotEmpty) ...[
              Row(
                children: [
                  const _PulsingLiveDot(),
                  const SizedBox(width: 8),
                  Text(
                    tr('Active Live Assessments'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD32F2F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...activeSessions.map((sessionDoc) {
                final data = sessionDoc.data();
                final patientId = data['patientId']?.toString() ?? '';
                final rawName = data['patientName']?.toString();
                final patientName = formatFullName(
                  (rawName != null && rawName.isNotEmpty) ? rawName : 'Patient',
                );
                final patientUser = UserModel(
                  uid: patientId,
                  name: patientName,
                  email: '',
                  role: 'patient',
                );

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
                  const Icon(
                    Icons.pause_circle_outline_rounded,
                    color: Color(0xFFF57F17),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  AppText(
                    '${tr("Paused Assessments")} (${pausedSessions.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF57F17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...pausedSessions.map((sessionDoc) {
                final data = sessionDoc.data();
                final patientId = data['patientId']?.toString() ?? '';
                final rawName = data['patientName']?.toString();
                final patientName = formatFullName(
                  (rawName != null && rawName.isNotEmpty) ? rawName : 'Patient',
                );
                final patientUser = UserModel(
                  uid: patientId,
                  name: patientName,
                  email: '',
                  role: 'patient',
                );

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
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF2E7D32),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('Recently Completed Assessments'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...recentlyCompleted.map((sessionDoc) {
                final data = sessionDoc.data();
                final patientId = data['patientId']?.toString() ?? '';
                final rawName = data['patientName']?.toString();
                final patientName = formatFullName(
                  (rawName != null && rawName.isNotEmpty) ? rawName : 'Patient',
                );
                final patientUser = UserModel(
                  uid: patientId,
                  name: patientName,
                  email: '',
                  role: 'patient',
                );

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
    AppLocaleScope.of(context);
    final repCount = (sessionData['currentRepCount'] as num?)?.toInt() ?? 0;
    final score = (sessionData['currentScore'] as num?)?.toDouble() ?? 0.0;
    final form = sessionData['currentForm']?.toString() ?? 'Assessing...';
    final rawExercise =
        sessionData['currentExercise']?.toString() ??
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

    final Color formColor =
        form.toLowerCase().contains('incorrect') ||
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _PulsingLiveDot(size: 8),
                      const SizedBox(width: 5),
                      Text(
                        tr('LIVE ASSESSMENT'),
                        style: const TextStyle(
                          color: Color(0xFFD32F2F),
                          fontWeight: FontWeight.w700,
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                          fontWeight: FontWeight.w700,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    tr('View Patient'),
                    style: const TextStyle(fontSize: 12),
                  ),
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
                  label: '$repCount ${tr('reps')}',
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
    AppLocaleScope.of(context);
    final repCount =
        (sessionData['currentRepCount'] as num?)?.toInt() ??
        (sessionData['totalReps'] as num?)?.toInt() ??
        (sessionData['completedCorrectReps'] as num?)?.toInt() ??
        0;
    final score = (sessionData['currentScore'] as num?)?.toDouble() ?? 0.0;
    final form = sessionData['currentForm']?.toString() ?? 'Paused';
    final progressPct =
        (sessionData['progressPercentage'] as num?)?.toInt() ?? 0;
    final rawExercise =
        sessionData['currentExercise']?.toString() ??
        sessionData['exercise']?.toString() ??
        sessionData['sessionName']?.toString() ??
        '';
    final exercise = rawExercise.isNotEmpty
        ? getExerciseDisplayName(rawExercise)
        : 'Physiotherapy Assessment';
    final pausedAt =
        sessionData['pausedAt'] ??
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFD54F)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.pause_circle_outline_rounded,
                        size: 13,
                        color: Color(0xFFF57F17),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('PAUSED'),
                        style: const TextStyle(
                          color: Color(0xFFF57F17),
                          fontWeight: FontWeight.w700,
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                          fontWeight: FontWeight.w700,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    tr('View Patient'),
                    style: const TextStyle(fontSize: 12),
                  ),
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
                    label: '$progressPct% ${tr('complete')}',
                    color: const Color(0xFFF57F17),
                  ),
                _LiveChip(
                  icon: Icons.repeat_rounded,
                  label: '$repCount ${tr('reps')}',
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
    AppLocaleScope.of(context);
    final finalReps =
        (sessionData['finalRepCount'] ?? sessionData['currentRepCount'] as num?)
            ?.toInt() ??
        0;
    final finalScore =
        (sessionData['finalScore'] ??
                sessionData['averageScore'] ??
                sessionData['currentScore'] as num?)
            ?.toDouble() ??
        0.0;
    final rawExercise =
        sessionData['currentExercise']?.toString() ??
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
                  AppText(
                    '$patientName ${tr('completed')} $exercise',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    '${tr('Score')}: ${finalScore.toStringAsFixed(0)}/100 • $finalReps ${tr('reps')}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
              child: Text(tr('Review'), style: const TextStyle(fontSize: 12)),
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
    AppLocaleScope.of(context);
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

  const _PulsingLiveDot({this.size = 10});

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
    _animation = Tween<double>(
      begin: 0.6,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
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

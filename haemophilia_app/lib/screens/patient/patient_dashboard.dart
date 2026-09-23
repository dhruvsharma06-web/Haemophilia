import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/assessment_history_service.dart';
import '../auth/login_screen.dart';
import '../profile/edit_profile_screen.dart';
import 'patient_history.dart';
import 'patient_messages.dart';
import 'assigned_assessment_screen.dart';
import '../../utils/exercise_utils.dart';
import '../../widgets/session_analytics_chart.dart';

class PatientDashboard extends StatefulWidget {
  final UserModel user;

  const PatientDashboard({super.key, required this.user});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final AuthService _authService = AuthService();

  Future<void> _logout() async {
    await _authService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // Temporary first-exercise entry point.
  // This will later load the doctor's assigned exercise
  // and target correct reps from Firestore.
void _startAssignedAssessment() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AssignedAssessmentScreen(),
    ),
  );
}

  String _getFirstName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data();
        final currentUser = userData != null
            ? UserModel.fromMap(widget.user.uid, userData)
            : widget.user;
        final firstName = _getFirstName(currentUser.name);

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: compact ? 68 : 76,
            titleSpacing: compact ? 20 : 28,
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.health_and_safety_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 11),
                const Text(
                  'Haemophilia',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Account',
                offset: const Offset(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                icon: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .10),
                  child: Text(
                    currentUser.name.isNotEmpty
                        ? currentUser.name[0].toUpperCase()
                        : 'P',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                onSelected: (value) {
                  if (value == 'edit_profile') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(user: currentUser),
                      ),
                    );
                  } else if (value == 'logout') {
                    _logout();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit_profile',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit Profile'),
                      subtitle: Text(currentUser.name),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout),
                      title: Text('Log out'),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 28,
                10,
                compact ? 20 : 28,
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WelcomeHeader(firstName: firstName, compact: compact),

                  const SizedBox(height: 24),

                  // --------------------------------------------------
                  // NEXT ASSESSMENT (ASSIGNMENT-DRIVEN)
                  // --------------------------------------------------
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('exerciseAssignments')
                        .doc(widget.user.uid)
                        .snapshots(),
                    builder: (context, assignmentSnapshot) {
                      final assignmentData = assignmentSnapshot.data?.data();
                      final status = assignmentData?['status']
                          ?.toString()
                          .trim()
                          .toLowerCase();
                      final rawExercises = assignmentData?['exercises'];
                      final bool hasExercises =
                          rawExercises is List && rawExercises.isNotEmpty;
                      final bool isPaused =
                          status == 'paused' || status == 'in_progress';
                      final bool hasActiveAssignment =
                          assignmentSnapshot.hasData &&
                          assignmentSnapshot.data!.exists &&
                          (status == 'assigned' || isPaused) &&
                          hasExercises;

                      if (!hasActiveAssignment) {
                        final isCompleted = status == 'completed';
                        return _NoSessionAssignedCard(
                          compact: compact,
                          isCompleted: isCompleted,
                        );
                      }

                      final sessionName =
                          assignmentData?['sessionName']?.toString().trim() ??
                              'Physiotherapy Session';
                      final exerciseCount = rawExercises.length;

                      if (isPaused) {
                        final currentExerciseIndex =
                            (assignmentData?['currentExerciseIndex'] as num?)?.toInt() ?? 0;
                        final completedCorrectReps =
                            (assignmentData?['completedCorrectReps'] as num?)?.toInt() ?? 0;
                        final currentExerciseName =
                            assignmentData?['currentExercise']?.toString() ?? '';

                        return _PausedSessionCard(
                          compact: compact,
                          sessionName: sessionName,
                          exerciseCount: exerciseCount,
                          currentExerciseIndex: currentExerciseIndex,
                          completedCorrectReps: completedCorrectReps,
                          currentExerciseName: currentExerciseName,
                          onPressed: _startAssignedAssessment,
                        );
                      }

                      return _ActiveSessionCard(
                        compact: compact,
                        sessionName: sessionName,
                        exerciseCount: exerciseCount,
                        onPressed: _startAssignedAssessment,
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  // --------------------------------------------------
                  // PROGRESS
                  // --------------------------------------------------
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: AssessmentHistoryService().watchAssessments(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _AssessmentDataErrorCard(
                          message: snapshot.error.toString(),
                        );
                      }

                      final sessions = groupAssessmentSessions(
                        snapshot.data?.docs ?? const [],
                      );

                      final int sessionsCount = sessions.length;

                      final int totalCorrectReps = sessions.fold<int>(
                        0,
                        (total, session) => total + session.correctReps,
                      );

                      final int totalReps = sessions.fold<int>(
                        0,
                        (total, session) => total + session.reps,
                      );

                      final double correctRate = totalReps == 0
                          ? 0.0
                          : (totalCorrectReps / totalReps) * 100.0;

                      final double avgScore = sessions.isEmpty
                          ? 0.0
                          : sessions.fold<double>(
                                0.0,
                                (total, session) => total + session.averageScore,
                              ) /
                              sessions.length;

                      final double avgRom = sessions.isEmpty
                          ? 0.0
                          : sessions.fold<double>(
                                0.0,
                                (total, session) => total + session.averageRom,
                              ) /
                              sessions.length;

                      // Extract most recent form error / focus tip
                      String? recentFocusTip;
                      if (sessions.isNotEmpty) {
                        for (final rep in sessions.first.repsData) {
                          final form =
                              rep['form']?.toString().toLowerCase() ?? '';
                          final error = rep['errorType']?.toString() ??
                              rep['error_type']?.toString() ??
                              '';
                          final feedback = rep['feedback']?.toString() ?? '';
                          if (form.contains('incorrect') || error.isNotEmpty) {
                            if (error.contains('ARM_LOW') ||
                                error.contains('RIGHT_ARM_LOW') ||
                                error.contains('LEFT_ARM_LOW')) {
                              recentFocusTip =
                                  'Keep both arms level during the movement.';
                            } else if (error.contains('ASYMMETRY')) {
                              recentFocusTip =
                                  'Raise both arms at an even height and symmetric speed.';
                            } else if (error.contains('BODY_TILT')) {
                              recentFocusTip =
                                  'Keep your torso upright and avoid leaning sideways.';
                            } else if (feedback.isNotEmpty &&
                                feedback != 'Rep completed.') {
                              recentFocusTip = feedback;
                            } else {
                              recentFocusTip =
                                  'Focus on controlled, steady movement through the full range of motion.';
                            }
                            break;
                          }
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(
                            title: 'Your progress',
                            subtitle:
                                'Clear summary of your physiotherapy performance',
                          ),

                          const SizedBox(height: 14),

                          LayoutBuilder(
                            builder: (context, constraints) {
                              final cards = [
                                _StatCard(
                                  icon: Icons.event_available_rounded,
                                  label: 'Sessions',
                                  value: '$sessionsCount',
                                ),
                                _StatCard(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: 'Correct Reps',
                                  value: '$totalCorrectReps',
                                ),
                                _StatCard(
                                  icon: Icons.percent_rounded,
                                  label: 'Accuracy',
                                  value: totalReps == 0
                                      ? '—'
                                      : '${correctRate.toStringAsFixed(0)}%',
                                ),
                                _StatCard(
                                  icon: Icons.speed_rounded,
                                  label: 'Average Score',
                                  value: sessions.isEmpty
                                      ? '—'
                                      : avgScore.toStringAsFixed(0),
                                ),
                                _StatCard(
                                  icon: Icons.track_changes_rounded,
                                  label: 'Average ROM',
                                  value: sessions.isEmpty
                                      ? '—'
                                      : '${avgRom.toStringAsFixed(0)}°',
                                ),
                              ];

                              final columns = constraints.maxWidth >= 850
                                  ? 5
                                  : (constraints.maxWidth >= 550 ? 3 : 2);

                              final rows = <Widget>[];

                              for (int i = 0; i < cards.length; i += columns) {
                                final rowCards = cards
                                    .skip(i)
                                    .take(columns)
                                    .toList();

                                rows.add(
                                  Row(
                                    children: [
                                      for (
                                        int j = 0;
                                        j < rowCards.length;
                                        j++
                                      ) ...[
                                        if (j > 0) const SizedBox(width: 12),
                                        Expanded(child: rowCards[j]),
                                      ],
                                      if (rowCards.length < columns)
                                        ...List.generate(
                                          columns - rowCards.length,
                                          (_) =>
                                              const Expanded(child: SizedBox()),
                                        ),
                                    ],
                                  ),
                                );

                                if (i + columns < cards.length) {
                                  rows.add(const SizedBox(height: 12));
                                }
                              }

                              return Column(children: rows);
                            },
                          ),

                          if (recentFocusTip != null) ...[
                            const SizedBox(height: 16),
                            _RecentFocusCard(focusTip: recentFocusTip),
                          ],

                          if (sessions.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            SessionAnalyticsChart(
                              sessions: sessions,
                              isDoctorView: false,
                            ),
                          ],

                          const SizedBox(height: 30),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Expanded(
                                child: _SectionTitle(
                                  title: 'Recent sessions',
                                  subtitle:
                                      'Detailed session summary and completion status',
                                ),
                              ),
                              if (sessions.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const PatientHistory(),
                                      ),
                                    );
                                  },
                                  child: const Text('View history'),
                                ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              sessions.isEmpty)
                            const _LoadingAssessmentsCard()
                          else if (sessions.isEmpty)
                            const _EmptyAssessmentsCard()
                          else
                            ...sessions
                                .take(3)
                                .map(
                                  (session) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _SessionSummaryCard(
                                      session: session,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SessionDetails(
                                              session: session,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // --------------------------------------------------
                  // DOCTOR MESSAGES
                  // --------------------------------------------------
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.forum_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: const Text(
                        'Doctor messages',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'View guidance and message your doctor.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientMessages(user: widget.user),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  _AccountCard(user: currentUser),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }
}

// ================================================================
// PAUSED SESSION CARD (ASSESSMENT IN PROGRESS)
// ================================================================

class _PausedSessionCard extends StatelessWidget {
  final bool compact;
  final String sessionName;
  final int exerciseCount;
  final int currentExerciseIndex;
  final int completedCorrectReps;
  final String currentExerciseName;
  final VoidCallback onPressed;

  const _PausedSessionCard({
    required this.compact,
    required this.sessionName,
    required this.exerciseCount,
    required this.currentExerciseIndex,
    required this.completedCorrectReps,
    required this.currentExerciseName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final displayExName = currentExerciseName.isNotEmpty
        ? getExerciseDisplayName(currentExerciseName)
        : 'Exercise ${currentExerciseIndex + 1}';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: Colors.amber.shade400.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 18 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 56 : 64,
                  height: compact ? 56 : 64,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.pause_circle_outline_rounded,
                    color: Colors.amber.shade900,
                    size: compact ? 30 : 34,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade800,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ASSESSMENT IN PROGRESS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        sessionName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Paused at $displayExName (Exercise ${currentExerciseIndex + 1} of $exerciseCount) • $completedCorrectReps correct reps completed',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: Colors.amber.shade900, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ready to continue: $sessionName',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: onPressed,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Continue Session',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// ACTIVE SESSION CARD
// ================================================================

class _ActiveSessionCard extends StatelessWidget {
  final bool compact;
  final String sessionName;
  final int exerciseCount;
  final VoidCallback onPressed;

  const _ActiveSessionCard({
    required this.compact,
    required this.sessionName,
    required this.exerciseCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 18 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 56 : 64,
                  height: compact ? 56 : 64,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.accessibility_new_rounded,
                    color: primary,
                    size: compact ? 29 : 33,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sessionName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Assigned session by your doctor with $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}. Complete all correct reps to finish.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.assignment_outlined, color: primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ready to begin: $sessionName',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Start Session',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// NO SESSION ASSIGNED CARD
// ================================================================

class _NoSessionAssignedCard extends StatelessWidget {
  final bool compact;
  final bool isCompleted;

  const _NoSessionAssignedCard({
    required this.compact,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 24),
        child: Row(
          children: [
            Container(
              width: compact ? 56 : 64,
              height: compact ? 56 : 64,
              decoration: BoxDecoration(
                color: isCompleted
                    ? Colors.green.withValues(alpha: .1)
                    : Colors.grey.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                isCompleted
                    ? Icons.check_circle_outline_rounded
                    : Icons.assignment_late_outlined,
                color: isCompleted ? Colors.green.shade600 : Colors.grey.shade600,
                size: compact ? 29 : 33,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'All done for now',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isCompleted
                        ? 'Your doctor will assign your next session when you are ready.'
                        : 'No exercise session is currently assigned.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      height: 1.35,
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

// ================================================================
// SECTION TITLE
// ================================================================

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -.25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    );
  }
}

// ================================================================
// STAT CARD
// ================================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: primary, size: 22),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
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

// ================================================================
// ASSESSMENT DATA ERROR
// ================================================================

class _AssessmentDataErrorCard extends StatelessWidget {
  final String message;

  const _AssessmentDataErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.error,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Could not load assessments',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    message,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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

// ================================================================
// LOADING
// ================================================================

class _LoadingAssessmentsCard extends StatelessWidget {
  const _LoadingAssessmentsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),

              const SizedBox(height: 12),

              Text(
                'Loading your assessments...',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// RECENT FOCUS CARD
// ================================================================

class _RecentFocusCard extends StatelessWidget {
  final String focusTip;

  const _RecentFocusCard({required this.focusTip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.withValues(alpha: .22),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: Colors.blueAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Most recent focus',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  focusTip,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// SESSION SUMMARY
// ================================================================

class _SessionSummaryCard extends StatelessWidget {
  final AssessmentSession session;
  final VoidCallback onTap;

  const _SessionSummaryCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final successRate = session.reps == 0
        ? 0.0
        : (session.correctReps / session.reps) * 100;

    final bool isGood = successRate >= 70;

    // Extract distinct exercises in this session
    final distinctExercises = session.repsData
        .map((r) => r['exercise']?.toString())
        .where((e) => e != null && e.isNotEmpty)
        .toSet()
        .toList();

    String exerciseSummary;
    if (distinctExercises.isEmpty) {
      exerciseSummary = getExerciseDisplayName(session.exercise);
    } else if (distinctExercises.length == 1) {
      exerciseSummary = getExerciseDisplayName(distinctExercises.first!);
    } else {
      exerciseSummary =
          '${distinctExercises.length} exercises (${distinctExercises.map((e) => getExerciseDisplayName(e!)).join(', ')})';
    }

    // Determine completion status
    final String statusLabel =
        isGood ? 'Completed' : 'Completed (Needs Practice)';
    final Color statusColor =
        isGood ? Colors.green.shade700 : Colors.orange.shade800;
    final Color statusBg =
        (isGood ? Colors.green : Colors.orange).withValues(alpha: .09);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      isGood
                          ? Icons.check_circle_outline_rounded
                          : Icons.insights_outlined,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.sessionName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatDateTime(session.date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXERCISES',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            exerciseSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CORRECT REPS',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${session.correctReps}/${session.reps} (${successRate.toStringAsFixed(0)}%)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isGood
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'AVG SCORE',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${session.averageScore.toStringAsFixed(0)}/100',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// HELPERS
// ================================================================

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();

  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return 'Today • $time';
  }

  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} • $time';
}


// ================================================================
// WELCOME HEADER
// ================================================================

class _WelcomeHeader extends StatelessWidget {
  final String firstName;
  final bool compact;

  const _WelcomeHeader({required this.firstName, required this.compact});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 20 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, Color.lerp(primary, const Color(0xFF63B4E8), .45)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, $firstName',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 24 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  'Track your physiotherapy progress '
                  'and complete guided movement assessments.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    height: 1.45,
                    fontSize: compact ? 14 : 16,
                  ),
                ),
              ],
            ),
          ),

          if (!compact) ...[
            const SizedBox(width: 16),

            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.favorite_outline_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ================================================================
// EMPTY ASSESSMENTS
// ================================================================

class _EmptyAssessmentsCard extends StatelessWidget {
  const _EmptyAssessmentsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .09),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 29,
                  color: Colors.grey.shade500,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'No assessments yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 5),

              Text(
                'Complete your first assessment '
                'to see your results here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// ACCOUNT
// ================================================================

class _AccountCard extends StatelessWidget {
  final UserModel user;

  const _AccountCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'P';

    final details = <String>[];
    if (user.age != null) details.add('${user.age} yrs');
    if (user.gender != null && user.gender!.isNotEmpty) details.add(user.gender!);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditProfileScreen(user: user),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: primary.withValues(alpha: .10),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: primary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.isNotEmpty
                          ? '${user.email} • ${details.join(", ")}'
                          : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(user: user),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Edit', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

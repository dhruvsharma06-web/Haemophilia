import '../../services/local_test_config.dart';
import '../../utils/firebase_errors.dart';
import '../../widgets/app_text.dart';

import 'dart:async';

import '../support/help_screen.dart';
import 'session_reports_screen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/due_session_service.dart';
import '../../widgets/patient_schedule_panel.dart';
import '../../widgets/session_deadline.dart';
import '../../widgets/expired_sessions_panel.dart';
import '../../widgets/patient_screening_card.dart';
import '../../widgets/notification_bell.dart';
import '../../services/assessment_history_service.dart';
import '../profile/edit_profile_screen.dart';
import 'patient_history.dart';
import 'patient_messages.dart';
import 'assigned_assessment_screen.dart';
import '../../utils/exercise_utils.dart';
import '../../utils/schedule_utils.dart';
import '../../widgets/session_analytics_chart.dart';
import '../assessment/live_assessment_screen.dart';
import '../../widgets/exercise_demo/exercise_demo_dialog.dart';
import '../../utils/app_localizations.dart';

class PatientDashboard extends StatefulWidget {
  final UserModel user;

  const PatientDashboard({super.key, required this.user});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final AuthService _authService = AuthService();

  bool _isLoggingOut = false;
  int _section = 0;
  Timer? _availabilityTimer;
  bool _activating = false;
  Future<void> _activateDueSession() async {
    if (_activating) return;
    _activating = true;
    try {
      await DueSessionService().activate(widget.user.uid);
    } catch (error) {
      debugPrint('Due session activation: $error');
    } finally {
      _activating = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _activateDueSession();
    _availabilityTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _activateDueSession();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    try {
      await _authService.logout();
    } catch (e) {
      debugPrint('Logout error: $e');
    }

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // Loads the current doctor's assignment from Firestore.
  void _startAssignedAssessment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AssignedAssessmentScreen()),
    );
  }

  void _resumeAssessment(Map<String, dynamic> data) {
    final sessionId = data['sessionId']?.toString() ?? '';
    final rawExercises = data['exercises'];
    final rawProgress = data['exerciseProgress'] ?? rawExercises;
    final progress = rawProgress is List
        ? rawProgress
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    final List<Map<String, dynamic>>? assignedExercises =
        (data['practice'] != true &&
            rawExercises is List &&
            rawExercises.isNotEmpty)
        ? rawExercises
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : null;

    final rawExercise =
        data['currentExercise']?.toString() ??
        data['exercise']?.toString() ??
        (assignedExercises != null && assignedExercises.isNotEmpty
            ? assignedExercises.first['exercise']?.toString()
            : null) ??
        'assisted_shoulder_flexion';

    final exerciseName = normalizeExerciseId(rawExercise);
    final currentIndex = (data['currentExerciseIndex'] as num?)?.toInt() ?? 0;
    final sessionTotalCorrect =
        (data['totalCorrectReps'] as num?)?.toInt() ??
        (data['completedCorrectReps'] as num?)?.toInt() ??
        0;
    final sessionTotalReps =
        (data['totalReps'] as num?)?.toInt() ??
        (data['totalCompletedReps'] as num?)?.toInt() ??
        (data['currentRepCount'] as num?)?.toInt() ??
        0;

    int currentExCorrect = 0;
    int currentExTotal = 0;

    if (assignedExercises != null &&
        currentIndex >= 0 &&
        currentIndex < assignedExercises.length) {
      final currentEx = currentIndex < progress.length
          ? progress[currentIndex]
          : assignedExercises[currentIndex];
      currentExCorrect =
          (currentEx['completedCorrectReps'] as num?)?.toInt() ?? 0;
      currentExTotal = (currentEx['completedTotalReps'] as num?)?.toInt() ?? 0;
    } else {
      currentExCorrect = sessionTotalCorrect;
      currentExTotal = sessionTotalReps;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAssessmentScreen(
          exerciseName: exerciseName,
          assignedExercises: assignedExercises,
          assignedDoctorId: data['doctorId']?.toString(),
          sessionName: data['sessionName']?.toString(),
          sessionId: sessionId.isNotEmpty ? sessionId : null,
          initialExerciseIndex: currentIndex,
          initialCorrectReps: currentExCorrect,
          initialTotalReps: currentExTotal,
          initialRepSequence: sessionTotalReps,
          initialExerciseProgress: progress,
        ),
      ),
    );
  }

  Future<void> _discardAssessment(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
          size: 44,
        ),
        title: Text(tr('Discard Session?')),
        content: Text(
          tr(
            'Are you sure you want to discard your progress? This session cannot be resumed once discarded.',
          ),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Discard')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await AssessmentHistoryService().abandonSession(
          sessionId,
          widget.user.uid,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(firebaseErrorMessage(error))));
        }
      }
    }
  }

  String _getFirstName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final currentUser = widget.user;
    final firstName = _getFirstName(currentUser.name);

    return Scaffold(
      appBar: _section >= 3
          ? null
          : AppBar(
              toolbarHeight: compact ? 68 : 76,
              titleSpacing: compact ? 20 : 28,
              title: Row(
                children: [
                  Image.asset(
                    'assets/icon/haemophysio_logo.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: AppText(
                      'Somaiya HemoPhysio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                const NotificationBell(),
                const LanguageToggleButton(),
                PopupMenuButton<String>(
                  enabled: !_isLoggingOut,
                  tooltip: tr('Account'),
                  offset: const Offset(0, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  icon: _isLoggingOut
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .10),
                          child: Text(
                            currentUser.name.isNotEmpty
                                ? currentUser.name[0].toUpperCase()
                                : 'P',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                  onSelected: (value) {
                    if (_isLoggingOut) return;
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
                        title: Text(tr('Edit Profile')),
                        subtitle: Text(currentUser.name),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout),
                        title: Text(tr('Log out')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (value) => setState(() => _section = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.event_note),
            label: tr('Sessions'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.self_improvement),
            label: tr('Practice'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            label: tr('History'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            label: tr('Messages'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.support_agent),
            label: tr('Help'),
          ),
        ],
      ),
      body: _section == 3
          ? PatientMessages(user: widget.user)
          : _section == 4
          ? const HelpScreen()
          : SafeArea(
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
                        if (_section == 0) ...[
                          _WelcomeHeader(
                            firstName: firstName,
                            compact: compact,
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (_section == 0) ...[
                          // --------------------------------------------------
                          // NEXT ASSESSMENT / RESUME ASSESSMENT
                          // --------------------------------------------------
                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: LocalTestConfig.database
                                .collection('exerciseAssignments')
                                .doc(widget.user.uid)
                                .snapshots(),
                            builder: (context, unfinishedSnap) {
                              if (unfinishedSnap.hasError) {
                                return Text(
                                  firebaseErrorMessage(unfinishedSnap.error),
                                );
                              }
                              final sessionData = unfinishedSnap.data?.data();
                              // Only the current prescription can be resumed;
                              // orphaned recording documents cannot hide a new one.
                              if (sessionData != null &&
                                  assignmentAvailable(
                                    sessionData,
                                    DateTime.now(),
                                  ) &&
                                  [
                                    'active',
                                    'in_progress',
                                    'paused',
                                  ].contains(sessionData['status']) &&
                                  (sessionData['sessionId']?.toString() ?? '')
                                      .isNotEmpty) {
                                final sessionId = sessionData['sessionId']
                                    .toString();
                                final sessionName =
                                    sessionData['sessionName']
                                        ?.toString()
                                        .trim() ??
                                    'Physiotherapy Session';
                                final rawEx =
                                    sessionData['currentExercise']
                                        ?.toString() ??
                                    sessionData['exercise']?.toString() ??
                                    '';
                                final currentExName = rawEx.isNotEmpty
                                    ? getExerciseDisplayName(rawEx)
                                    : 'Assessment';
                                final repCount =
                                    (sessionData['currentRepCount'] as num?)
                                        ?.toInt() ??
                                    (sessionData['totalReps'] as num?)
                                        ?.toInt() ??
                                    (sessionData['totalCompletedReps'] as num?)
                                        ?.toInt() ??
                                    0;
                                final rawExercises = sessionData['exercises'];
                                final int exCount = rawExercises is List
                                    ? rawExercises.length
                                    : 1;
                                final int exIndex =
                                    (sessionData['currentExerciseIndex']
                                            as num?)
                                        ?.toInt() ??
                                    0;

                                debugPrint(
                                  'Dashboard selected active session: $sessionId ($sessionName, status: ${sessionData['status']})',
                                );

                                return Column(
                                  children: [
                                    SessionDeadline(
                                      deadline: sessionExpiry(sessionData)!,
                                      onExpired: () {
                                        _activateDueSession();
                                        setState(() {});
                                      },
                                    ),
                                    _ResumeAssessmentCard(
                                      compact: compact,
                                      sessionName: sessionName,
                                      exerciseName: currentExName,
                                      repsCompleted: repCount,
                                      exerciseCount: exCount,
                                      currentExerciseIndex: exIndex,
                                      onResume: () =>
                                          _resumeAssessment(sessionData),
                                      onDiscard: () =>
                                          _discardAssessment(sessionId),
                                    ),
                                  ],
                                );
                              }

                              return StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: LocalTestConfig.database
                                    .collection('exerciseAssignments')
                                    .doc(widget.user.uid)
                                    .snapshots(),
                                builder: (context, assignmentSnapshot) {
                                  if (assignmentSnapshot.hasError) {
                                    return Text(
                                      firebaseErrorMessage(
                                        assignmentSnapshot.error,
                                      ),
                                    );
                                  }
                                  final assignmentData = assignmentSnapshot.data
                                      ?.data();
                                  final status = assignmentData?['status']
                                      ?.toString()
                                      .trim()
                                      .toLowerCase();
                                  final rawExercises =
                                      assignmentData?['exercises'];
                                  final bool hasExercises =
                                      rawExercises is List &&
                                      rawExercises.isNotEmpty;
                                  final bool isPaused =
                                      status == 'paused' ||
                                      status == 'in_progress';
                                  final bool hasActiveAssignment =
                                      assignmentSnapshot.hasData &&
                                      assignmentSnapshot.data!.exists &&
                                      (status == 'assigned' || isPaused) &&
                                      assignmentAvailable(
                                        assignmentData!,
                                        DateTime.now(),
                                      ) &&
                                      hasExercises;

                                  if (!hasActiveAssignment) {
                                    final isCompleted = status == 'completed';
                                    debugPrint(
                                      'Dashboard: no pending assignment (status: $status, isCompleted: $isCompleted)',
                                    );
                                    return _NoSessionAssignedCard(
                                      compact: compact,
                                      isCompleted: isCompleted,
                                    );
                                  }

                                  final sessionName =
                                      assignmentData['sessionName']
                                          ?.toString()
                                          .trim() ??
                                      'Physiotherapy Session';
                                  final exerciseCount = rawExercises.length;

                                  debugPrint(
                                    'Dashboard selected pending assignment: $sessionName (status: $status, exercises: $exerciseCount)',
                                  );

                                  return Column(
                                    children: [
                                      SessionDeadline(
                                        deadline: sessionExpiry(
                                          assignmentData,
                                        )!,
                                        onExpired: () {
                                          _activateDueSession();
                                          setState(() {});
                                        },
                                      ),
                                      _ActiveSessionCard(
                                        compact: compact,
                                        sessionName: sessionName,
                                        exerciseCount: exerciseCount,
                                        onPressed: _startAssignedAssessment,
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),

                          const SizedBox(height: 30),
                          PatientSchedulePanel(
                            patientId: widget.user.uid,
                            onScheduleChanged: _activateDueSession,
                          ),
                          ExpiredSessionsPanel(patientId: widget.user.uid),
                          ExpansionTile(
                            title: Text(tr('Patient screening')),
                            children: [
                              StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: LocalTestConfig.database
                                    .collection('users')
                                    .doc(widget.user.uid)
                                    .snapshots(),
                                builder: (context, snapshot) =>
                                    snapshot.hasError
                                    ? Text(firebaseErrorMessage(snapshot.error))
                                    : PatientScreeningCard(
                                        data: snapshot.data?.data() ?? {},
                                      ),
                              ),
                            ],
                          ),
                        ],
                        if (_section == 2) ...[
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SessionReportsScreen(
                                  patientId: widget.user.uid,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.description_outlined),
                            label: Text(tr('Session reports')),
                          ),
                          // --------------------------------------------------
                          // PROGRESS
                          // --------------------------------------------------
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: AssessmentHistoryService().watchAssessments(
                              widget.user.uid,
                            ),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return _AssessmentDataErrorCard(
                                  message: firebaseErrorMessage(
                                    snapshot.error,
                                    fallback:
                                        'Could not load your session history.',
                                  ),
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
                                          (total, session) =>
                                              total + session.averageScore,
                                        ) /
                                        sessions.length;

                              final double avgRom = sessions.isEmpty
                                  ? 0.0
                                  : sessions.fold<double>(
                                          0.0,
                                          (total, session) =>
                                              total + session.averageRom,
                                        ) /
                                        sessions.length;

                              // Extract most recent form error / focus tip
                              String? recentFocusTip;
                              if (sessions.isNotEmpty) {
                                for (final rep in sessions.first.repsData) {
                                  final form =
                                      rep['form']?.toString().toLowerCase() ??
                                      '';
                                  final error =
                                      rep['errorType']?.toString() ??
                                      rep['error_type']?.toString() ??
                                      '';
                                  final feedback =
                                      rep['feedback']?.toString() ?? '';
                                  if (form.contains('incorrect') ||
                                      error.isNotEmpty) {
                                    if (error.contains('ARM_LOW') ||
                                        error.contains('RIGHT_ARM_LOW') ||
                                        error.contains('LEFT_ARM_LOW')) {
                                      recentFocusTip = 'Keep both arms level during the movement.';
                                    } else if (error.contains('ASYMMETRY')) {
                                      recentFocusTip = 'Raise both arms at an even height and symmetric speed.';
                                    } else if (error.contains('BODY_TILT')) {
                                      recentFocusTip = 'Keep your torso upright and avoid leaning sideways.';
                                    } else if (feedback.isNotEmpty &&
                                        feedback != 'Rep completed.') {
                                      recentFocusTip = feedback;
                                    } else {
                                      recentFocusTip = 'Focus on controlled, steady movement through the full range of motion.';
                                    }
                                    break;
                                  }
                                }
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SectionTitle(
                                    title: tr('Your progress'),
                                    subtitle: tr(
                                      'Clear summary of your physiotherapy performance',
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final cards = [
                                        _StatCard(
                                          icon: Icons.event_available_rounded,
                                          label: tr('Sessions'),
                                          value: '$sessionsCount',
                                        ),
                                        _StatCard(
                                          icon: Icons
                                              .check_circle_outline_rounded,
                                          label: tr('Correct Reps'),
                                          value: '$totalCorrectReps',
                                        ),
                                        _StatCard(
                                          icon: Icons.percent_rounded,
                                          label: tr('Accuracy'),
                                          value: totalReps == 0
                                              ? '—'
                                              : '${correctRate.toStringAsFixed(0)}%',
                                        ),
                                        _StatCard(
                                          icon: Icons.speed_rounded,
                                          label: tr('Average Score'),
                                          value: sessions.isEmpty
                                              ? '—'
                                              : avgScore.toStringAsFixed(0),
                                        ),
                                        _StatCard(
                                          icon: Icons.track_changes_rounded,
                                          label: tr('Average ROM'),
                                          value: sessions.isEmpty
                                              ? '—'
                                              : '${avgRom.toStringAsFixed(0)}°',
                                        ),
                                      ];

                                      final columns =
                                          constraints.maxWidth >= 850
                                          ? 5
                                          : (constraints.maxWidth >= 550
                                                ? 3
                                                : 2);

                                      final rows = <Widget>[];

                                      for (
                                        int i = 0;
                                        i < cards.length;
                                        i += columns
                                      ) {
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
                                                if (j > 0)
                                                  const SizedBox(width: 12),
                                                Expanded(child: rowCards[j]),
                                              ],
                                              if (rowCards.length < columns)
                                                ...List.generate(
                                                  columns - rowCards.length,
                                                  (_) => const Expanded(
                                                    child: SizedBox(),
                                                  ),
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
                                      Expanded(
                                        child: _SectionTitle(
                                          title: tr('Recent sessions'),
                                          subtitle: tr(
                                            'Detailed session summary and completion status',
                                          ),
                                        ),
                                      ),
                                      if (sessions.isNotEmpty)
                                        TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PatientHistory(
                                                  userId: widget.user.uid,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Text(tr('View history')),
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
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: _SessionSummaryCard(
                                              session: session,
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        SessionDetails(
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
                        ],
                        if (_section == 1 ||
                            (_section == 0 && widget.user.doctorId == null))
                          _ExerciseLibrarySection(compact: compact),

                        const SizedBox(height: 24),

                        if (_section == 0) ...[
                          AppText(
                            '${tr('Patient ID')}: ${currentUser.patientId}',
                          ),
                          const SizedBox(height: 12),
                          _AccountCard(user: currentUser),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ================================================================
// RESUME ASSESSMENT CARD (UNFINISHED SESSIONS)
// ================================================================

class _ResumeAssessmentCard extends StatelessWidget {
  final bool compact;
  final String sessionName;
  final String exerciseName;
  final int repsCompleted;
  final int exerciseCount;
  final int currentExerciseIndex;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  const _ResumeAssessmentCard({
    required this.compact,
    required this.sessionName,
    required this.exerciseName,
    required this.repsCompleted,
    required this.exerciseCount,
    required this.currentExerciseIndex,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
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
                            child: Text(
                              tr('ASSESSMENT IN PROGRESS'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        exerciseCount > 1
                            ? 'Paused at $exerciseName (${currentExerciseIndex + 1} of $exerciseCount) • $repsCompleted reps completed'
                            : '$exerciseName • $repsCompleted reps completed',
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
                  Icon(
                    Icons.history_rounded,
                    color: Colors.amber.shade900,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      'Ready to continue: $exerciseName ($repsCompleted reps completed)',
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
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        tr('Resume Assessment'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: onDiscard,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text(
                        tr('Discard'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
    AppLocaleScope.of(context);
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      AppText(
                        '${tr('Assigned session by your doctor with')} $exerciseCount ${tr(exerciseCount == 1 ? 'exercise. Complete all correct reps to finish.' : 'exercises. Complete all correct reps to finish.')}',
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
                    child: AppText(
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
                label: Text(
                  tr('Start Session'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
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
    AppLocaleScope.of(context);
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
                color: isCompleted
                    ? Colors.green.shade600
                    : Colors.grey.shade600,
                size: compact ? 29 : 33,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('All done for now'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isCompleted
                        ? tr(
                            'Your doctor will assign your next session when you are ready.',
                          )
                        : tr('No exercise session is currently assigned.'),
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
    AppLocaleScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
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
    AppLocaleScope.of(context);
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
                      fontWeight: FontWeight.w700,
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
    AppLocaleScope.of(context);
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
                  const AppText(
                    'Could not load assessments',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
    AppLocaleScope.of(context);
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

              AppText(
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
    AppLocaleScope.of(context);
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
                Text(
                  tr('Most Recent Focus'),
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(focusTip),
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
    AppLocaleScope.of(context);
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
      exerciseSummary = tr(getExerciseDisplayName(session.exercise));
    } else if (distinctExercises.length == 1) {
      exerciseSummary = tr(getExerciseDisplayName(distinctExercises.first!));
    } else {
      exerciseSummary =
          '${distinctExercises.length} ${tr('exercises')} (${distinctExercises.map((e) => tr(getExerciseDisplayName(e!))).join(', ')})';
    }

    // Determine completion status
    final String statusLabel = isGood
        ? 'Completed'
        : 'Completed (Needs Practice)';
    final Color statusColor = isGood
        ? Colors.green.shade700
        : Colors.orange.shade800;
    final Color statusBg = (isGood ? Colors.green : Colors.orange).withValues(
      alpha: .09,
    );

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
                                  fontWeight: FontWeight.w700,
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
                                tr(statusLabel),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
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
                            tr('EXERCISES'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            exerciseSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('CORRECT REPS'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AppText(
                            '${session.correctReps}/${session.reps} (${successRate.toStringAsFixed(0)}%)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isGood
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            tr('AVG SCORE'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AppText(
                            '${session.averageScore.toStringAsFixed(0)}/100',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
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
    return '${tr('Today')} • $time';
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
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 20 : 24),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  '${tr("Welcome back,")} $firstName',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 22 : 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  tr('Track exercises, monitor progress and recover safely.'),
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
    AppLocaleScope.of(context);
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

              Text(
                tr('No assessment sessions yet'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                tr('Complete your first assessment to see your results here.'),
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
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'P';

    final details = <String>[];
    if (user.age != null) details.add('${user.age} yrs');
    if (user.gender != null && user.gender!.isNotEmpty) {
      details.add(user.gender!);
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EditProfileScreen(user: user)),
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
                    fontWeight: FontWeight.w700,
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.isNotEmpty
                          ? '${user.email} • ${details.join(", ")}'
                          : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const AppText('Edit', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// EXERCISE LIBRARY & DEMONSTRATIONS SECTION
// ================================================================

class _ExerciseLibrarySection extends StatelessWidget {
  final bool compact;

  const _ExerciseLibrarySection({required this.compact});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: tr('Exercise library & guides'),
          subtitle: tr(
            'Step-by-step technique guides and interactive demonstrations',
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 640;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 2 : 1,
                mainAxisExtent: isWide ? 180 : 172,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: kAllExercises.length,
              itemBuilder: (context, index) {
                final ex = kAllExercises[index];
                return _ExerciseLibraryCard(exercise: ex, compact: compact);
              },
            );
          },
        ),
      ],
    );
  }
}

class _ExerciseLibraryCard extends StatelessWidget {
  final ExerciseMetadata exercise;
  final bool compact;

  const _ExerciseLibraryCard({required this.exercise, required this.compact});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(exercise.icon, color: primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(exercise.displayName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (exercise.isWorkInProgress)
                        buildWipBadge(compact: true)
                      else
                        Text(
                          tr(
                            exercise.id == kAssistedElbowFlexionV5
                                ? 'Experimental model'
                                : 'Movement guide',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                tr(exercise.description),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      showExerciseDemoDialog(
                        context,
                        exerciseName: exercise.id,
                      );
                    },
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 16,
                    ),
                    label: Text(
                      tr('Tutorial'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final uid = LocalTestConfig.auth.currentUser?.uid;
                      if (uid == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveAssessmentScreen(
                            exerciseName: exercise.displayName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.videocam_outlined, size: 16),
                    label: Text(
                      tr('Practice'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

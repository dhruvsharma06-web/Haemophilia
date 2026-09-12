import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/assessment_history_service.dart';
import '../auth/login_screen.dart';
import 'live_assessment_screen.dart';
import 'patient_history.dart';
import 'patient_messages.dart';

class PatientDashboard extends StatefulWidget {
  final UserModel user;

  const PatientDashboard({
    super.key,
    required this.user,
  });

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

  void _startAssistedFlexion() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LiveAssessmentScreen(
          exerciseName: 'Assisted Shoulder Flexion',
        ),
      ),
    );
  }

  String get _firstName {
    final name = widget.user.name.trim();
    if (name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;

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
                color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
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
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: .10),
              child: Text(
                widget.user.name.isNotEmpty
                    ? widget.user.name[0].toUpperCase()
                    : 'P',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'profile',
                enabled: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(widget.user.name),
                  subtitle: const Text('Patient account'),
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
                  _WelcomeHeader(firstName: _firstName, compact: compact),
                  const SizedBox(height: 24),

                  _PrimaryExerciseCard(
                    compact: compact,
                    onPressed: _startAssistedFlexion,
                  ),

                  const SizedBox(height: 30),

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
                      final latest = sessions.isNotEmpty ? sessions.first : null;
                      final correctReps = sessions.fold<int>(
                        0,
                        (total, session) => total + session.correctReps,
                      );
                      final totalReps = sessions.fold<int>(
                        0,
                        (total, session) => total + session.reps,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(
                            title: 'Your progress',
                            subtitle: 'A quick look at your physiotherapy sessions',
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final cards = [
                                _StatCard(
                                  icon: Icons.analytics_outlined,
                                  label: 'Latest score',
                                  value: latest == null
                                      ? '—'
                                      : latest.averageScore.toStringAsFixed(0),
                                ),
                                _StatCard(
                                  icon: Icons.event_note_outlined,
                                  label: 'Sessions',
                                  value: '${sessions.length}',
                                ),
                                _StatCard(
                                  icon: Icons.check_circle_outline,
                                  label: 'Correct reps',
                                  value: totalReps == 0
                                      ? '—'
                                      : '$correctReps/$totalReps',
                                ),
                                const _StatCard(
                                  icon: Icons.insights_outlined,
                                  label: 'Status',
                                  value: 'Ready',
                                ),
                              ];

                              final columns = constraints.maxWidth >= 760 ? 4 : 2;
                              final rows = <Widget>[];
                              for (int i = 0; i < cards.length; i += columns) {
                                final rowCards = cards.skip(i).take(columns).toList();
                                rows.add(
                                  Row(
                                    children: [
                                      for (int j = 0; j < rowCards.length; j++) ...[
                                        if (j > 0) const SizedBox(width: 12),
                                        Expanded(child: rowCards[j]),
                                      ],
                                      if (rowCards.length < columns)
                                        ...List.generate(
                                          columns - rowCards.length,
                                          (_) => const Expanded(child: SizedBox()),
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

                          const SizedBox(height: 30),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Expanded(
                                child: _SectionTitle(
                                  title: 'Recent sessions',
                                  subtitle: 'Your latest physiotherapy sessions',
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
                          if (snapshot.connectionState == ConnectionState.waiting &&
                              sessions.isEmpty)
                            const _LoadingAssessmentsCard()
                          else if (sessions.isEmpty)
                            const _EmptyAssessmentsCard()
                          else
                            ...sessions.take(3).map(
                              (session) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
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

                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 6),
                      leading: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.forum_outlined, color: Theme.of(context).colorScheme.primary),
                      ),
                      title: const Text('Doctor messages', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('View guidance and message your doctor.'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PatientMessages(user: widget.user))),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _AccountCard(user: widget.user),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}



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

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

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

class _SessionSummaryCard extends StatelessWidget {
  final AssessmentSession session;
  final VoidCallback onTap;

  const _SessionSummaryCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final successRate = session.reps == 0
        ? 0.0
        : (session.correctReps / session.reps) * 100;
    final good = successRate >= 70;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (good ? primary : Colors.orange).withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  good ? Icons.check_circle_outline : Icons.insights_outlined,
                  color: good ? primary : Colors.orange.shade700,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.exercise,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDate(session.date)}  •  ${session.reps} reps',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${session.correctReps}/${session.reps} correct  •  ${successRate.toStringAsFixed(0)}% success',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    session.averageScore.toStringAsFixed(0),
                    style: TextStyle(
                      color: good ? primary : Colors.orange.shade800,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'avg score',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssessmentSummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AssessmentSummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final form = data['form']?.toString() ?? 'Unknown';
    final formLabel = form.isEmpty ? 'Unknown' : '${form[0].toUpperCase()}${form.substring(1).toLowerCase()}';
    final incorrect = form.toLowerCase().contains('incorrect');
    final score = _number(data['score']);
    final rom = _number(data['rangeOfMotion']);
    final exercise = data['exercise']?.toString() ?? 'Assessment';
    final createdAt = data['createdAt'];
    final dateText = createdAt is Timestamp ? _formatDate(createdAt.toDate()) : 'Recent';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (incorrect ? Colors.red : primary).withValues(alpha: .09),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                incorrect ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: incorrect ? Colors.red.shade600 : primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$dateText  •  ${form[0].toUpperCase()}${form.substring(1).toLowerCase()}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${score.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Text(
                  'score  •  ${rom.toStringAsFixed(0)}° ROM',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return 'Today';
  }
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class _WelcomeHeader extends StatelessWidget {
  final String firstName;
  final bool compact;

  const _WelcomeHeader({
    required this.firstName,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 20 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, const Color(0xFF63B4E8), .45)!,
          ],
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
                  'Track your physiotherapy progress and complete guided movement assessments.',
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

class _PrimaryExerciseCard extends StatelessWidget {
  final bool compact;
  final VoidCallback onPressed;

  const _PrimaryExerciseCard({
    required this.compact,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 18 : 22),
        child: Row(
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
                  const Text(
                    'Ready for your next assessment?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Assisted Shoulder Flexion',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size(76, 46),
                padding: const EdgeInsets.symmetric(horizontal: 15),
              ),
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

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
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

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

class _ExerciseCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String buttonText;
  final VoidCallback? onPressed;

  const _ExerciseCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: enabled
                    ? primary.withValues(alpha: .09)
                    : Colors.grey.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 27,
                color: enabled ? primary : Colors.grey.shade500,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            enabled
                ? FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(74, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text(buttonText),
                  )
                : OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(92, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text(buttonText),
                  ),
          ],
        ),
      ),
    );
  }
}

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
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Complete your first assessment to see your results here.',
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

class _AccountCard extends StatelessWidget {
  final UserModel user;

  const _AccountCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'P';

    return Card(
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
                    user.email,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Patient',
                style: TextStyle(
                  color: primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

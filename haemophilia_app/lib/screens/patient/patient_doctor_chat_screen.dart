import '../../services/local_test_config.dart';
import '../../utils/firebase_errors.dart';
import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/clinical_data_service.dart';
import '../../utils/app_localizations.dart';
import 'patient_history.dart';

class PatientDoctorChatScreen extends StatefulWidget {
  final UserModel patient;
  final String doctorId;
  final String doctorName;

  const PatientDoctorChatScreen({
    super.key,
    required this.patient,
    required this.doctorId,
    required this.doctorName,
  });

  @override
  State<PatientDoctorChatScreen> createState() =>
      _PatientDoctorChatScreenState();
}

class _PatientDoctorChatScreenState extends State<PatientDoctorChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ClinicalDataService _service = ClinicalDataService();
  bool _sending = false;

  String get _conversationId =>
      _service.getConversationId(widget.patient.uid, widget.doctorId);

  @override
  void initState() {
    super.initState();
    _initConversation();
  }

  Future<void> _initConversation() async {
    try {
      // 1. Migrate any legacy unthreaded messages for this pair
      await _service.migrateLegacyMessagesIfAny(
        widget.patient.uid,
        widget.doctorId,
      );
      // 2. Mark unread messages as read by patient
      await _service.markConversationAsRead(
        conversationId: _conversationId,
        userRole: 'patient',
      );
    } catch (e) {
      debugPrint('Chat initialization: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _service.sendThreadMessage(
        patientId: widget.patient.uid,
        doctorId: widget.doctorId,
        text: text,
        senderRole: 'patient',
        patientName: widget.patient.name,
        doctorName: widget.doctorName,
      );
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            firebaseErrorMessage(
              e,
              fallback: 'Could not send message. Please try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate().toLocal();
      return '${date.day}/${date.month}/${date.year}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.doctorName.startsWith('Dr.')
                  ? widget.doctorName
                  : 'Dr. ${widget.doctorName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              tr('Physician'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: const [LanguageToggleButton()],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.watchConversationMessages(_conversationId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        firebaseErrorMessage(
                          snapshot.error,
                          fallback: 'Could not load messages.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.reversed.toList();

                // Whenever new messages arrive while this screen is active, mark read
                if (docs.isNotEmpty) {
                  _service.markConversationAsRead(
                    conversationId: _conversationId,
                    userRole: 'patient',
                  );
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, size: 52, color: primary),
                          const SizedBox(height: 12),
                          Text(
                            tr('No messages yet'),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AppText(
                            '${tr('Send a message to')} ${widget.doctorName} ${tr('to start the conversation')}.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final mine = d['senderRole'] == 'patient';

                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 330),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? primary.withValues(alpha: .10)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: .06),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (d['sessionContext'] != null)
                              _SessionReferenceCard(
                                sessionContext: Map<String, dynamic>.from(
                                  d['sessionContext'] as Map,
                                ),
                                onTap: () => _openSessionFromContext(
                                  context,
                                  widget.patient.uid,
                                  Map<String, dynamic>.from(
                                    d['sessionContext'] as Map,
                                  ),
                                ),
                              ),
                            Text(
                              d['text']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _time(d['createdAt']),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText:
                            '${tr('Write to')} ${widget.doctorName.startsWith("Dr.") ? widget.doctorName : "Dr. ${widget.doctorName}"}...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionReferenceCard extends StatelessWidget {
  final Map<String, dynamic> sessionContext;
  final VoidCallback? onTap;

  const _SessionReferenceCard({required this.sessionContext, this.onTap});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final exercise =
        sessionContext['sessionName']?.toString() ??
        sessionContext['exercise']?.toString() ??
        'Physiotherapy Session';
    final score = (sessionContext['score'] as num?)?.toDouble() ?? 0.0;
    final reps = (sessionContext['reps'] as num?)?.toInt() ?? 0;
    final correctReps = (sessionContext['correctReps'] as num?)?.toInt() ?? 0;
    final dateStr = sessionContext['date']?.toString();
    DateTime? dt;
    if (dateStr != null) {
      dt = DateTime.tryParse(dateStr)?.toLocal();
    }

    final scoreColor = score >= 80
        ? const Color(0xFF2E7D32)
        : (score >= 50 ? const Color(0xFFE65100) : const Color(0xFFC62828));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.fitness_center_rounded,
                  size: 15,
                  color: Color(0xFF1E293B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    exercise,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: AppText(
                    '${score.toStringAsFixed(0)}/100',
                    style: TextStyle(
                      color: scoreColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                AppText(
                  '$correctReps/$reps ${tr('correct reps')}${dt != null ? ' • ${dt.day}/${dt.month}/${dt.year}' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  tr('View Session ›'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2563EB),
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

void _openSessionFromContext(
  BuildContext context,
  String patientId,
  Map<String, dynamic> sessionContext,
) {
  final sessionId = sessionContext['sessionId']?.toString() ?? '';
  LocalTestConfig.database
      .collection('users')
      .doc(patientId)
      .collection('assessments')
      .where('sessionId', isEqualTo: sessionId)
      .get()
      .then((snap) {
        if (!context.mounted) return;
        if (snap.docs.isNotEmpty) {
          final sessions = groupAssessmentSessions(snap.docs);
          if (sessions.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionDetails(session: sessions.first),
              ),
            );
            return;
          }
        }

        final dateStr = sessionContext['date']?.toString();
        final dt = dateStr != null
            ? DateTime.tryParse(dateStr) ?? DateTime.now()
            : DateTime.now();
        final score = (sessionContext['score'] as num?)?.toDouble() ?? 0.0;
        final fallbackSession = AssessmentSession(
          id: sessionId,
          exercise: sessionContext['exercise']?.toString() ?? '',
          sessionName: sessionContext['sessionName']?.toString() ?? 'Session',
          date: dt,
          repsData: [
            {'score': score, 'form': 'Correct', 'repNumber': 1},
          ],
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetails(session: fallbackSession),
          ),
        );
      })
      .catchError((e) {
        debugPrint('Could not load session details: $e');
      });
}

import '../../services/local_test_config.dart';
import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../utils/app_localizations.dart';
import '../../utils/firebase_errors.dart';

String readableDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Older requests were stored as `closed`; both mean resolved.
bool ticketResolved(Map<String, dynamic> ticket) =>
    ticket['status'] == 'resolved' || ticket['status'] == 'closed';

enum _TicketFilter { open, resolved, all }

class TicketStatusChip extends StatelessWidget {
  final bool resolved;
  const TicketStatusChip({super.key, required this.resolved});

  @override
  Widget build(BuildContext context) {
    final color = resolved ? const Color(0xFF2E7D32) : const Color(0xFFB26A00);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr(resolved ? 'Resolved' : 'Open'),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class HelpScreen extends StatefulWidget {
  final bool admin;
  const HelpScreen({super.key, this.admin = false});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _db = LocalTestConfig.database;
  bool _saving = false;
  late _TicketFilter _filter = widget.admin
      ? _TicketFilter.open
      : _TicketFilter.all;
  String get _uid => LocalTestConfig.auth.currentUser!.uid;

  Future<void> _newRequest() async {
    if (_saving) return;
    setState(() => _saving = true);
    Map<String, dynamic> profile;
    try {
      profile = (await _db.collection('users').doc(_uid).get()).data() ?? {};
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(firebaseErrorMessage(error))));
      }
      return;
    }
    if (!mounted) return;
    final doctor =
        profile['role'] == 'doctor' || profile['role'] == 'pending_doctor';
    final categories = doctor
        ? [
            'Patient not responding',
            'Patient assignment or transfer',
            'Session scheduling',
            'Assessment or report problem',
            'Account or approval',
            'Technical problem',
            'Other',
          ]
        : [
            'Doctor not responding',
            'Doctor assignment',
            'Technical problem',
            'Other',
          ];
    var text = '';
    var category = categories.first;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          AppLocaleScope.of(context);
          return AlertDialog(
            title: Text(tr('Contact admin')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(value: c, child: Text(tr(c))),
                        )
                        .toList(),
                    onChanged: (c) => setState(() => category = c!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => text = value,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: tr('Describe your concern'),
                    ),
                  ),
                  if (!doctor)
                    Text(
                      tr(
                        'Help messages are reviewed by administrators. For urgent medical concerns, contact your treating doctor or local emergency service.',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (text.trim().isNotEmpty) {
                    Navigator.pop(context, {
                      'category': category,
                      'text': text.trim(),
                    });
                  }
                },
                child: Text(tr('Send')),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _saving = false);
      return;
    }
    try {
      final ticket = _db.collection('supportTickets').doc();
      final batch = _db.batch();
      batch.set(ticket, {
        'userId': _uid,
        'submittedByName':
            profile['name'] ??
            LocalTestConfig.auth.currentUser?.displayName ??
            '',
        'submittedByEmail':
            profile['email'] ?? LocalTestConfig.auth.currentUser?.email ?? '',
        'submittedByRole': profile['role'] ?? '',
        'category': result['category'],
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(ticket.collection('messages').doc(), {
        'senderId': _uid,
        'senderName': profile['name'] ?? '',
        'senderRole': profile['role'] ?? '',
        'text': result['text'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupportThread(ticketId: ticket.id, admin: false),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(firebaseErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final query = widget.admin
        ? _db.collection('supportTickets')
        : _db.collection('supportTickets').where('userId', isEqualTo: _uid);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(widget.admin ? 'Grievances' : 'Help / Contact admin')),
        actions: const [LanguageToggleButton()],
      ),
      floatingActionButton: widget.admin
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _newRequest,
              icon: const Icon(Icons.support_agent),
              label: Text(tr('Contact admin')),
            ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!widget.admin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr(
                    'Send a concern or message to the administrator and track replies here.',
                  ),
                ),
              ),
            ),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _db.collection('users').doc(_uid).snapshots(),
              builder: (context, snap) =>
                  snap.data?.data()?['role'] != 'patient'
                  ? const SizedBox.shrink()
                  : SwitchListTile(
                      title: Text(tr('Research and development consent')),
                      subtitle: Text(
                        tr('Optional. Change your choice at any time.'),
                      ),
                      value: snap.data?.data()?['researchConsent'] == true,
                      onChanged: !snap.hasData
                          ? null
                          : (value) async {
                              try {
                                await _db.collection('users').doc(_uid).update({
                                  'researchConsent': value,
                                  'researchConsentUpdatedAt':
                                      FieldValue.serverTimestamp(),
                                });
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        firebaseErrorMessage(error),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
            ),
          ],
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  firebaseErrorMessage(
                    snap.error,
                    fallback: 'Could not load requests. Please try again.',
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs.toList()
                ..sort(
                  (a, b) =>
                      ((b.data()['createdAt'] as Timestamp?)
                                  ?.millisecondsSinceEpoch ??
                              0)
                          .compareTo(
                            (a.data()['createdAt'] as Timestamp?)
                                    ?.millisecondsSinceEpoch ??
                                0,
                          ),
                );
              final openCount = docs
                  .where((doc) => !ticketResolved(doc.data()))
                  .length;
              final resolvedCount = docs.length - openCount;
              final visible = docs.where((doc) {
                final resolved = ticketResolved(doc.data());
                return switch (_filter) {
                  _TicketFilter.open => !resolved,
                  _TicketFilter.resolved => resolved,
                  _TicketFilter.all => true,
                };
              }).toList();
              final filters = Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in {
                      _TicketFilter.open: '${tr('Open')} ($openCount)',
                      _TicketFilter.resolved:
                          '${tr('Resolved')} ($resolvedCount)',
                      _TicketFilter.all: '${tr('All')} (${docs.length})',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _filter == entry.key,
                        onSelected: (_) =>
                            setState(() => _filter = entry.key),
                      ),
                  ],
                ),
              );
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('No requests yet.')),
                );
              }
              if (visible.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    filters,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr(
                          _filter == _TicketFilter.open
                              ? 'No open requests.'
                              : 'No resolved requests.',
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filters,
                  ...visible
                    .map(
                      (doc) => Card(
                        margin: const EdgeInsets.only(top: 12),
                        child: ListTile(
                          title: Text(
                            tr(doc.data()['category']?.toString() ?? 'Other'),
                          ),
                          subtitle: AppText(
                            '${doc.data()['submittedByName'] ?? doc.data()['userId'] ?? ''} · ${tr(doc.data()['submittedByRole']?.toString() ?? '')}\n${doc.data()['createdAt'] is Timestamp ? readableDate((doc.data()['createdAt'] as Timestamp).toDate()) : ''}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TicketStatusChip(
                                resolved: ticketResolved(doc.data()),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SupportThread(
                                ticketId: doc.id,
                                admin: widget.admin,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class SupportThread extends StatefulWidget {
  final String ticketId;
  final bool admin;
  const SupportThread({super.key, required this.ticketId, required this.admin});
  @override
  State<SupportThread> createState() => _SupportThreadState();
}

class _SupportThreadState extends State<SupportThread> {
  final _text = TextEditingController();
  bool _sending = false;
  DocumentReference<Map<String, dynamic>> get _ticket => LocalTestConfig
      .database
      .collection('supportTickets')
      .doc(widget.ticketId);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      final uid = LocalTestConfig.auth.currentUser!.uid;
      final profile =
          (await LocalTestConfig.database.collection('users').doc(uid).get())
              .data() ??
          {};
      final ticket = (await _ticket.get()).data() ?? {};
      final messageRef = _ticket.collection('messages').doc();
      final batch = LocalTestConfig.database.batch();
      batch.set(messageRef, {
        'senderId': LocalTestConfig.auth.currentUser!.uid,
        'senderName': profile['name'] ?? '',
        'senderRole': profile['role'] ?? '',
        'text': _text.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      final owner = ticket['userId']?.toString();
      // A reply from the person who raised a resolved request reopens it.
      if (owner == uid && ticketResolved(ticket)) {
        batch.update(_ticket, {
          'status': 'open',
          'reopenedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (profile['role'] == 'admin' && owner != null && owner != uid) {
        batch.set(
          LocalTestConfig.database
              .collection('users')
              .doc(owner)
              .collection('notifications')
              .doc('support_${widget.ticketId}_${messageRef.id}'),
          {
            'senderId': uid,
            'read': false,
            'title': 'Support message',
            'body': 'Your help request has a new message.',
            'createdAt': FieldValue.serverTimestamp(),
            'data': {'type': 'support', 'ticketId': widget.ticketId},
          },
        );
      }
      await batch.commit();
      _text.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(firebaseErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _updatingStatus = false;

  Future<void> _setResolved(Map<String, dynamic> ticket, bool resolve) async {
    if (_updatingStatus) return;
    if (resolve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('Mark this request as resolved?')),
          content: Text(
            tr(
              'The person who raised it will be notified. They can reply to reopen it.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr('Mark as resolved')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _updatingStatus = true);
    try {
      final uid = LocalTestConfig.auth.currentUser!.uid;
      final now = FieldValue.serverTimestamp();
      final batch = LocalTestConfig.database.batch();
      batch.update(
        _ticket,
        resolve
            ? {
                'status': 'resolved',
                'resolvedAt': now,
                'resolvedBy': uid,
                'updatedAt': now,
              }
            : {'status': 'open', 'reopenedAt': now, 'updatedAt': now},
      );
      final owner = ticket['userId']?.toString();
      if (resolve && widget.admin && owner != null && owner != uid) {
        batch.set(
          LocalTestConfig.database
              .collection('users')
              .doc(owner)
              .collection('notifications')
              .doc(
                'support_resolved_${widget.ticketId}_${DateTime.now().millisecondsSinceEpoch}',
              ),
          {
            'senderId': uid,
            'read': false,
            'title': 'Help request resolved',
            'body': 'Your help request was marked as resolved.',
            'createdAt': now,
            'data': {'type': 'support_resolved', 'ticketId': widget.ticketId},
          },
        );
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(resolve ? 'Request marked as resolved.' : 'Request reopened.'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(firebaseErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Contact admin')),
        actions: const [LanguageToggleButton()],
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _ticket.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Text(firebaseErrorMessage(snap.error));
              final d = snap.data?.data() ?? {};
              final resolved = ticketResolved(d);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    title: Text(
                      '${tr('Submitted by')}: ${d['submittedByName'] ?? d['userId'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${d['submittedByEmail'] ?? ''} · ${tr(d['submittedByRole']?.toString() ?? '')}',
                    ),
                    trailing: snap.hasData
                        ? TicketStatusChip(resolved: resolved)
                        : null,
                  ),
                  if (snap.hasData)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (resolved)
                            Text(
                              tr(
                                widget.admin
                                    ? 'This request is resolved.'
                                    : 'This request is resolved. Send a message to reopen it.',
                              ),
                            ),
                          resolved
                              ? OutlinedButton.icon(
                                  onPressed: _updatingStatus
                                      ? null
                                      : () => _setResolved(d, false),
                                  icon: const Icon(Icons.replay),
                                  label: Text(tr('Reopen request')),
                                )
                              : FilledButton.icon(
                                  onPressed: _updatingStatus
                                      ? null
                                      : () => _setResolved(d, true),
                                  icon: const Icon(Icons.task_alt),
                                  label: Text(tr('Mark as resolved')),
                                ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                ],
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _ticket
                  .collection('messages')
                  .orderBy('createdAt')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      firebaseErrorMessage(
                        snap.error,
                        fallback: 'Could not load requests. Please try again.',
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: snap.data!.docs.map((doc) {
                    final d = doc.data();
                    final mine =
                        d['senderId'] == LocalTestConfig.auth.currentUser!.uid;
                    final timestamp = d['createdAt'];
                    return Card(
                      child: ListTile(
                        title: Text(d['text']?.toString() ?? ''),
                        subtitle: AppText(
                          '${mine ? tr('You') : d['senderName'] ?? tr(widget.admin ? 'Submitted by' : 'Admin')} · ${tr(d['senderRole']?.toString() ?? '')} · ${timestamp is Timestamp ? '${readableDate(timestamp.toDate())} ${TimeOfDay.fromDateTime(timestamp.toDate()).format(context)}' : ''}',
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLines: 3,
                      minLines: 1,
                      maxLength: 2000,
                      decoration: InputDecoration(hintText: tr('Message')),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Send message'),
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
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

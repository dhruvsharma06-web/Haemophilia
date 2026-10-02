import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_localizations.dart';
import '../../utils/firebase_errors.dart';

String readableDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class HelpScreen extends StatefulWidget {
  final bool admin;
  const HelpScreen({super.key, this.admin = false});
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _db = FirebaseFirestore.instance;
  bool _saving = false;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _newRequest() async {
    var text = '';
    var category = 'Doctor not responding';
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
                  items:
                      [
                            'Doctor not responding',
                            'Doctor assignment',
                            'Technical problem',
                            'Other',
                          ]
                          .map(
                            (c) =>
                                DropdownMenuItem(value: c, child: Text(tr(c))),
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
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final ticket = _db.collection('supportTickets').doc();
      final batch = _db.batch();
      batch.set(ticket, {
        'userId': _uid,
        'category': result['category'],
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(ticket.collection('messages').doc(), {
        'senderId': _uid,
        'text': result['text'],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => SupportThread(ticketId: ticket.id, admin: false)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(firebaseErrorMessage(error))),
        );
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
              builder: (context, snap) => snap.data?.data()?['role'] != 'patient' ? const SizedBox.shrink() : SwitchListTile(
                title: Text(tr('Research and development consent')),
                subtitle: Text(tr('Optional. Change your choice at any time.')),
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
                return Text(firebaseErrorMessage(snap.error, fallback: 'Could not load requests. Please try again.'));
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
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('No requests yet.')),
                );
              }
              return Column(
                children: docs
                    .map(
                      (doc) => Card(
                        margin: const EdgeInsets.only(top: 12),
                        child: ListTile(
                          title: Text(
                            tr(doc.data()['category']?.toString() ?? 'Other'),
                          ),
                          subtitle: AppText(
                            '${tr(doc.data()['status']?.toString() ?? 'open')} · ${doc.data()['createdAt'] is Timestamp ? readableDate((doc.data()['createdAt'] as Timestamp).toDate()) : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
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
                    )
                    .toList(),
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
  DocumentReference<Map<String, dynamic>> get _ticket => FirebaseFirestore
      .instance
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
      await _ticket.collection('messages').add({
        'senderId': FirebaseAuth.instance.currentUser!.uid,
        'text': _text.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _text.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(firebaseErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Contact admin')),
        actions: [
          const LanguageToggleButton(),
          if (widget.admin)
            IconButton(
              tooltip: tr('Close request'),
              icon: const Icon(Icons.task_alt),
              onPressed: () async {
                try {
                  await _ticket.update({
                    'status': 'closed',
                    'closedAt': FieldValue.serverTimestamp(),
                  });
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(firebaseErrorMessage(error)),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
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
                      firebaseErrorMessage(snap.error, fallback: 'Could not load requests. Please try again.'),
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
                        d['senderId'] == FirebaseAuth.instance.currentUser!.uid;
                    final timestamp = d['createdAt'];
                    return Card(
                      child: ListTile(
                        title: Text(d['text']?.toString() ?? ''),
                        subtitle: AppText(
                          '${tr(mine ? 'You' : 'Reply')} · ${timestamp is Timestamp ? readableDate(timestamp.toDate()) : ''}',
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

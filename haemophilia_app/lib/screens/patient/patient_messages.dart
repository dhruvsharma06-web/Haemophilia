import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/clinical_data_service.dart';

class PatientMessages extends StatefulWidget {
  final UserModel user;
  const PatientMessages({super.key, required this.user});

  @override
  State<PatientMessages> createState() => _PatientMessagesState();
}

class _PatientMessagesState extends State<PatientMessages> {
  final _controller = TextEditingController();
  final _service = ClinicalDataService();
  bool _sending = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(
        patientId: widget.user.uid,
        text: text,
        senderRole: 'patient',
      );
      _controller.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send message: $e')));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  String _time(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate().toLocal();
      return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor messages', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
            stream: _service.watchPatientMessages(widget.user.uid),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load messages.\n\n${snapshot.error}', textAlign: TextAlign.center)));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.forum_outlined, size: 52, color: primary), const SizedBox(height: 12),
                const Text('No messages yet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6), Text('Your doctor can leave guidance here.', style: TextStyle(color: Colors.grey)),
              ])));
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final mine = d['senderRole'] == 'patient';
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 330),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                      decoration: BoxDecoration(
                        color: mine ? primary.withValues(alpha: .10) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: .06)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['text']?.toString() ?? '', style: const TextStyle(fontSize: 14, height: 1.35)),
                        const SizedBox(height: 4),
                        Text(_time(d['createdAt']), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Row(children: [
          Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 4, textInputAction: TextInputAction.newline, decoration: const InputDecoration(hintText: 'Write to your doctor...'))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.send_rounded)),
        ]))),
      ]),
    );
  }
}

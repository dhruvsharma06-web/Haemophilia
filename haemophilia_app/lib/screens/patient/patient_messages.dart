import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/clinical_data_service.dart';
import 'patient_doctor_chat_screen.dart';

class PatientMessages extends StatefulWidget {
  final UserModel user;

  const PatientMessages({super.key, required this.user});

  @override
  State<PatientMessages> createState() => _PatientMessagesState();
}

class _PatientMessagesState extends State<PatientMessages> {
  final ClinicalDataService _service = ClinicalDataService();

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate().toLocal();
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    if (isToday) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else {
      return '${date.day}/${date.month}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Stream all doctors from the users collection
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'doctor')
            .snapshots(),
        builder: (context, doctorSnap) {
          if (doctorSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load doctors.\n\n${doctorSnap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!doctorSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doctorDocs = doctorSnap.data!.docs;

          if (doctorDocs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.medical_services_outlined,
                      size: 54,
                      color: primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No doctors available',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your clinician team will appear here once registered.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            );
          }

          // Stream active conversations for this patient
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.watchPatientConversations(widget.user.uid),
            builder: (context, convSnap) {
              final convDocs = convSnap.data?.docs ?? [];
              final convMap = <String, Map<String, dynamic>>{};
              for (final doc in convDocs) {
                final docData = doc.data();
                final docId = docData['doctorId']?.toString();
                if (docId != null) {
                  convMap[docId] = docData;
                }
              }

              // Build list items for each doctor
              final items = doctorDocs.map((dDoc) {
                final docData = dDoc.data();
                final doctorId = dDoc.id;
                final rawName = docData['name']?.toString() ?? 'Doctor';
                final displayName =
                    rawName.startsWith('Dr.') ? rawName : 'Dr. $rawName';
                final conv = convMap[doctorId];
                final lastMessage = conv?['lastMessage']?.toString();
                final lastMessageAt = conv?['lastMessageAt'] as Timestamp?;
                final unreadCount =
                    (conv?['unreadCountPatient'] as num?)?.toInt() ?? 0;
                final isAssigned = widget.user.doctorId == doctorId;

                return _DoctorThreadItem(
                  doctorId: doctorId,
                  doctorName: displayName,
                  lastMessage: lastMessage,
                  lastMessageAt: lastMessageAt,
                  unreadCount: unreadCount,
                  isAssigned: isAssigned,
                );
              }).toList();

              // Sort:
              // 1. Doctors with active messages (sorted by lastMessageAt descending)
              // 2. Doctors without messages (assigned doctor first, then name)
              items.sort((a, b) {
                if (a.lastMessageAt != null && b.lastMessageAt != null) {
                  return b.lastMessageAt!.compareTo(a.lastMessageAt!);
                }
                if (a.lastMessageAt != null && b.lastMessageAt == null) {
                  return -1;
                }
                if (a.lastMessageAt == null && b.lastMessageAt != null) {
                  return 1;
                }
                if (a.isAssigned && !b.isAssigned) return -1;
                if (!a.isAssigned && b.isAssigned) return 1;
                return a.doctorName.compareTo(b.doctorName);
              });

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];

                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: primary.withValues(alpha: .10),
                            child: Text(
                              item.doctorName.replaceFirst('Dr. ', '').isNotEmpty
                                  ? item.doctorName
                                      .replaceFirst('Dr. ', '')[0]
                                      .toUpperCase()
                                  : 'D',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (item.unreadCount > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.doctorName,
                              style: TextStyle(
                                fontWeight: item.unreadCount > 0
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (item.isAssigned) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ASSIGNED',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (item.lastMessageAt != null)
                            Text(
                              _formatTimestamp(item.lastMessageAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: item.unreadCount > 0
                                    ? primary
                                    : Colors.grey.shade600,
                                fontWeight: item.unreadCount > 0
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.lastMessage ??
                                    'No messages yet • Tap to start chat',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: item.unreadCount > 0
                                      ? Colors.black87
                                      : Colors.grey.shade600,
                                  fontSize: 13,
                                  fontWeight: item.unreadCount > 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontStyle: item.lastMessage == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ),
                            if (item.unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${item.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatientDoctorChatScreen(
                              patient: widget.user,
                              doctorId: item.doctorId,
                              doctorName: item.doctorName,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _DoctorThreadItem {
  final String doctorId;
  final String doctorName;
  final String? lastMessage;
  final Timestamp? lastMessageAt;
  final int unreadCount;
  final bool isAssigned;

  const _DoctorThreadItem({
    required this.doctorId,
    required this.doctorName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.isAssigned,
  });
}

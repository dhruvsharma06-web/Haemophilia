import '../../services/local_test_config.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/firebase_errors.dart';
import '../support/help_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final uid = LocalTestConfig.auth.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Notifications')),
        actions: [
          IconButton(
            tooltip: tr('Mark all as read'),
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              try {
                await NotificationService().markAllRead();
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(firebaseErrorMessage(error))),
                  );
                }
              }
            },
          ),
          const LanguageToggleButton(),
        ],
      ),
      body: uid == null
          ? Center(child: Text(tr('Please sign in.')))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: LocalTestConfig.database
                  .collection('users')
                  .doc(uid)
                  .collection('notifications')
                  .where('read', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(firebaseErrorMessage(snapshot.error)),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs.toList()
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
                  return Center(child: Text(tr('No notifications yet.')));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final d = doc.data();
                    final date = d['createdAt'];
                    final unread = d['read'] != true;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Icon(
                          Icons.notifications_outlined,
                          color: unread
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          tr(d['title']?.toString() ?? 'Notification'),
                          style: TextStyle(
                            fontWeight: unread
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${tr(d['body']?.toString() ?? '')}\n${date is Timestamp ? '${readableDate(date.toDate())} · ${TimeOfDay.fromDateTime(date.toDate()).format(context)}' : ''}',
                        ),
                        isThreeLine: true,
                        onTap: () async {
                          try {
                            await NotificationService().handleNotificationTap(
                              Map<String, dynamic>.from(d['data'] as Map? ?? {})
                                ..['notificationId'] = doc.id,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(firebaseErrorMessage(e)),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

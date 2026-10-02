import '../utils/app_localizations.dart';
import '../screens/support/help_screen.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/doctor/doctor_messages.dart';
import '../screens/patient/assigned_assessment_screen.dart';
import '../screens/patient/patient_doctor_chat_screen.dart';
import '../screens/patient/session_reports_screen.dart';
import '../widgets/consent_form.dart';

/// Top-level background message handler for FCM.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM Background message received: ${message.messageId}');
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  String? _lastToken;
  String? _lastSavedToken;
  String? _lastSavedUid;

  /// Sets the navigator key used for notification-based navigation.
  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Initializes FCM permissions, token registration, and message listeners.
  Future<void> initialize({GlobalKey<NavigatorState>? navKey}) async {
    if (navKey != null) {
      _navigatorKey = navKey;
    }

    if (_initialized) {
      debugPrint('NotificationService already initialized. Skipping duplicate listeners.');
      return;
    }
    _initialized = true;

    try {
      // 1. Request permission for notifications (Android 13+ and iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('FCM Authorization status: ${settings.authorizationStatus}');

      // 2. Configure foreground notification presentation options
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 3. Register current device token for the signed-in user
      await syncUserToken();

      // 4. Listen for token refresh events
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM device token refreshed.');
        _lastToken = newToken;
        await _saveTokenToFirestore(newToken);
      });

      // 5. Handle foreground messages
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message: ${message.notification?.title}');
        _showInAppNotification(message);
      });

      // 6. Handle notification click when app is in background
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub =
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM Message opened from background: ${message.data}');
        handleNotificationTap(message.data);
      });

      // 7. Check if app was opened from a terminated state via a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM App opened from terminated via: ${initialMessage.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleNotificationTap(initialMessage.data);
        });
      }
    } catch (e) {
      debugPrint('NotificationService initialization failed: $e');
    }
  }

  /// Syncs the current FCM device token to Firestore under the authenticated user's profile.
  Future<void> syncUserToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final token = await _messaging.getToken().timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      if (token != null && token.isNotEmpty) {
        if (_lastSavedToken == token && _lastSavedUid == user.uid) {
          // Token is already synced for this user session; do not write redundantly
          return;
        }
        _lastToken = token;
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (_lastSavedToken == token && _lastSavedUid == user.uid) {
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
        'language': AppLocaleService.currentLocale.value,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));
      _lastSavedToken = token;
      _lastSavedUid = user.uid;
      debugPrint('FCM Token saved to users/${user.uid}');
    } catch (e) {
      debugPrint('Error saving FCM token to Firestore: $e');
    }
  }

  /// Removes the device token on logout so this device stops receiving the user's notifications.
  Future<void> clearTokenOnLogout(String uid) async {
    try {
      final token = _lastToken ??
          await _messaging.getToken().timeout(
                const Duration(seconds: 2),
                onTimeout: () => null,
              );
      if (token != null && token.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
          'fcmToken': FieldValue.delete(),
        }).timeout(const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('Error clearing FCM token on logout (non-fatal): $e');
    } finally {
      try { await _messaging.deleteToken().timeout(const Duration(seconds:2)); } catch (_) {}
      _lastToken = null;
      _lastSavedToken = null;
      _lastSavedUid = null;
    }
  }

  /// Handles routing when a user taps a notification.
  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    final navContext = _navigatorKey?.currentContext;
    if (navContext == null) {
      debugPrint('Cannot navigate: navigatorContext is null');
      return;
    }

    final type = data['type']?.toString().toLowerCase();

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    Map<String,dynamic>? account;
    try { account=(await _firestore.collection('users').doc(currentUser.uid).get()).data(); }
    catch (_) { return; }
    if (!navContext.mounted || _auth.currentUser?.uid != currentUser.uid || account==null || account['accountActive']==false || (account['role'] != 'admin' && account['consentVersion'] != consentVersion) || account['role']=='pending_doctor' || (account['role']=='doctor' && account['isApproved']==false) || (account['role']=='patient' && account['onboardingCompleted'] != true)) return;
    switch (type) {
      case 'new_patient':
        if (account['role'] != 'admin') return;
        Navigator.push(
          navContext,
          MaterialPageRoute(
            builder: (_) => AdminDashboard(
              user: UserModel.fromMap(currentUser.uid, account!),
            ),
          ),
        );
        break;
      case 'support':
        final ticketId = data['ticketId']?.toString();
        if (ticketId == null) return;
        _firestore.collection('users').doc(_auth.currentUser!.uid).get().then((profile) {
          if (!navContext.mounted) return;
          Navigator.push(navContext, MaterialPageRoute(builder: (_) => SupportThread(ticketId: ticketId, admin: profile.data()?['role'] == 'admin')));
        });
        break;
      case 'session_assigned':
      case 'assignment':
        if (account['role'] != 'patient' || data['patientId'] != currentUser.uid) return;
        Navigator.push(
          navContext,
          MaterialPageRoute(
            builder: (_) => const AssignedAssessmentScreen(),
          ),
        );
        break;

      case 'session_completed':
        final patientId=data['patientId']?.toString();
        if (patientId == null || account['role'] != 'doctor' || data['doctorId'] != currentUser.uid) return;
        try {
          final patient=(await _firestore.collection('users').doc(patientId).get()).data();
          if (!navContext.mounted || patient?['doctorId'] != currentUser.uid) return;
          Navigator.push(navContext,MaterialPageRoute(builder:(_)=>SessionReportsScreen(patientId:patientId)));
        } catch (_) { return; }
        break;

      case 'new_message':
      case 'message':
        final patientId = data['patientId']?.toString();
        final doctorId = data['doctorId']?.toString();
        final currentUid = _auth.currentUser?.uid;

        if (currentUid != null) {
          // If the recipient is the patient, route to PatientDoctorChatScreen
          if (account['doctorId'] == doctorId && currentUid == patientId &&
              doctorId != null &&
              doctorId.isNotEmpty) {
            _firestore
                .collection('users')
                .doc(currentUid)
                .get()
                .then((patientDoc) {
              if (!patientDoc.exists || navContext.mounted != true || patientDoc.data()?['doctorId'] != doctorId) return;
              final patient =
                  UserModel.fromMap(patientDoc.id, patientDoc.data()!);
              _firestore.collection('users').doc(doctorId).get().then((docDoc) {
                if (navContext.mounted != true) return;
                final docName =
                    docDoc.data()?['name']?.toString() ?? 'Doctor';
                Navigator.push(
                  navContext,
                  MaterialPageRoute(
                    builder: (_) => PatientDoctorChatScreen(
                      patient: patient,
                      doctorId: doctorId,
                      doctorName: docName,
                    ),
                  ),
                );
              });
            });
          } else if (currentUid == doctorId &&
              patientId != null &&
              patientId.isNotEmpty) {
            // If the recipient is the doctor, route to DoctorMessages
            _firestore
                .collection('users')
                .doc(patientId)
                .get()
                .then((patientDoc) {
              if (!patientDoc.exists || navContext.mounted != true || patientDoc.data()?['doctorId'] != doctorId) return;
              final patient =
                  UserModel.fromMap(patientDoc.id, patientDoc.data()!);
              Navigator.push(
                navContext,
                MaterialPageRoute(
                  builder: (_) => DoctorMessages(
                    patientId: patientId,
                    patient: patient,
                  ),
                ),
              );
            });
          }
        }
        break;

      default:
        debugPrint('Unhandled notification type: $type');
    }
  }

  /// Shows an in-app banner for foreground notifications.
  void _showInAppNotification(RemoteMessage message) {
    final navContext = _navigatorKey?.currentContext;
    if (navContext == null) return;

    final title = message.notification?.title ?? message.data['title'] ?? 'Notification';
    final body = message.notification?.body ?? message.data['body'] ?? '';

    ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        action: SnackBarAction(
          label: tr('View'),
          onPressed: () => handleNotificationTap(message.data),
        ),
      ),
    );
  }

  /// Sends a notification to a target user.
  /// 1. Persists a notification record in `users/{targetUserId}/notifications`.
  /// 2. The server Firestore trigger dispatches FCM to registered devices.
  Future<void> sendNotification({
    required String targetUserId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final currentUser = _auth.currentUser;
    final now = Timestamp.now();

    // 1. Persist notification in Firestore under target user's notification subcollection
    try {
      await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('notifications')
          .add({
        'title': title,
        'body': body,
        'data': data,
        'senderId': currentUser?.uid ?? '',
        'read': false,
        'createdAt': now,
      });
      debugPrint('Notification document created for user $targetUserId');
    } catch (e) {
      debugPrint('Error creating notification document in Firestore: $e');
    }

  }
}

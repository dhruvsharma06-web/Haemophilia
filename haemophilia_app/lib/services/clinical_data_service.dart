import 'local_test_config.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dart:async';

class ClinicalDataService {
  final FirebaseFirestore _firestore = LocalTestConfig.database;
  final FirebaseAuth _auth = LocalTestConfig.auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _assessments(String uid) =>
      _users.doc(uid).collection('assessments');

  CollectionReference<Map<String, dynamic>> _messages(String uid) =>
      _users.doc(uid).collection('messages');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAssignedPatients() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _users
        .where('role', isEqualTo: 'patient')
        .where('doctorId', isEqualTo: uid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPatientAssessments(
    String patientId,
  ) {
    return _assessments(patientId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPatientMessages(
    String patientId,
  ) {
    return _messages(patientId)
        .orderBy('createdAt', descending: false)
        .limit(100)
        .snapshots();
  }

  Future<void> sendMessage({
    required String patientId,
    required String text,
    required String senderRole,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You are not signed in.');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 2000) {
      throw StateError('Keep messages within 2000 characters.');
    }

    await _messages(patientId).add({
      'senderId': user.uid,
      'senderRole': senderRole,
      'text': trimmed,
      'createdAt': Timestamp.now(),
      'readByPatient': senderRole == 'patient',
      'readByDoctor': senderRole == 'doctor',
    });
  }

  // --- CONVERSATION THREADS (1:1 Patient-Doctor) ---
  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection('conversations');

  String getConversationId(String patientId, String doctorId) =>
      '${patientId}_$doctorId';

  CollectionReference<Map<String, dynamic>> _conversationMessages(
    String conversationId,
  ) => _conversations.doc(conversationId).collection('messages');

  /// Streams all conversations for a patient.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPatientConversations(
    String patientId,
  ) {
    return _conversations.where('patientId', isEqualTo: patientId).snapshots();
  }

  /// Streams all conversations for a doctor.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchDoctorConversations(
    String doctorId,
  ) {
    return _conversations.where('doctorId', isEqualTo: doctorId).snapshots();
  }

  /// Streams messages in a specific conversation thread.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchConversationMessages(
    String conversationId,
  ) {
    return _conversationMessages(conversationId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  /// Sends a message in a 1:1 patient-doctor conversation thread.
  Future<void> sendThreadMessage({
    required String patientId,
    required String doctorId,
    required String text,
    required String senderRole,
    String? patientName,
    String? doctorName,
    Map<String, dynamic>? sessionContext,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You are not signed in.');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.length > 2000) {
      throw StateError('Keep messages within 2000 characters.');
    }
    final profile = await _users.doc(patientId).get();
    final doctor = await _users.doc(doctorId).get();
    if (profile.data()?['doctorId'] != doctorId ||
        profile.data()?['accountActive'] == false ||
        doctor.data()?['role'] != 'doctor' ||
        doctor.data()?['isApproved'] == false ||
        doctor.data()?['accountActive'] == false ||
        (senderRole == 'patient'
            ? user.uid != patientId
            : senderRole != 'doctor' || user.uid != doctorId)) {
      throw StateError(
        'You can only message your assigned clinician or patient.',
      );
    }
    final batch = _firestore.batch();
    final conversationId = getConversationId(patientId, doctorId);
    final isPatient = senderRole == 'patient';
    final receiverId = isPatient ? doctorId : patientId;
    final now = Timestamp.now();

    // 1. Add message to the conversation's messages subcollection
    final messagePayload = <String, dynamic>{
      'conversationId': conversationId,
      'senderId': user.uid,
      'receiverId': receiverId,
      'patientId': patientId,
      'doctorId': doctorId,
      'senderRole': senderRole,
      'text': trimmed,
      'createdAt': now,
      'read': false,
      'readByPatient': isPatient,
      'readByDoctor': !isPatient,
    };

    if (sessionContext != null) {
      messagePayload['sessionContext'] = sessionContext;
    }

    final messageRef = _conversationMessages(conversationId).doc();
    batch.set(messageRef, messagePayload);
    batch.set(
      _users
          .doc(receiverId)
          .collection('notifications')
          .doc('message_${conversationId}_${messageRef.id}'),
      {
        'senderId': user.uid,
        'read': false,
        'title': 'New message',
        'body': 'You have a new message. Open the app to read it.',
        'createdAt': FieldValue.serverTimestamp(),
        'data': {
          'type': 'new_message',
          'patientId': patientId,
          'doctorId': doctorId,
          'conversationId': conversationId,
        },
      },
    );

    // 2. Upsert conversation parent document with latest preview and increment unread for receiver
    final convDoc = <String, dynamic>{
      'patientId': patientId,
      'doctorId': doctorId,
      'lastMessage': trimmed,
      'lastMessageAt': now,
      'lastSenderId': user.uid,
      'lastSenderRole': senderRole,
      'updatedAt': now,
    };
    if (patientName != null && patientName.isNotEmpty) {
      convDoc['patientName'] = patientName;
    }
    if (doctorName != null && doctorName.isNotEmpty) {
      convDoc['doctorName'] = doctorName;
    }

    if (isPatient) {
      convDoc['unreadCountDoctor'] = FieldValue.increment(1);
    } else {
      convDoc['unreadCountPatient'] = FieldValue.increment(1);
    }

    batch.set(
      _conversations.doc(conversationId),
      convDoc,
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Streams active assessment sessions for this doctor's patients.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  watchActiveDoctorSessions(String doctorId) {
    // Subscribe by current patient ownership. Historical doctorId values can
    // briefly lag a transfer, so they cannot authorize the live query.
    final subscriptions =
        <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
    final records =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    var ownedPatientIds = <String>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? patients;
    late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    controller;
    void emit() {
      if (!controller.isClosed) {
        controller.add(records.values.expand((value) => value).toList());
      }
    }

    controller = StreamController(
      onListen: () {
        patients = _users
            .where('role', isEqualTo: 'patient')
            .where('doctorId', isEqualTo: doctorId)
            .snapshots()
            .listen(
              (snapshot) {
                final ids = snapshot.docs.map((doc) => doc.id).toSet();
                ownedPatientIds = ids;
                for (final id
                    in subscriptions.keys
                        .where((id) => !ids.contains(id))
                        .toList()) {
                  subscriptions.remove(id)?.cancel();
                  records.remove(id);
                }
                emit();
                for (final id in ids) {
                  subscriptions.putIfAbsent(
                    id,
                    () => _firestore
                        .collection('assessmentSessions')
                        .where('patientId', isEqualTo: id)
                        .snapshots()
                        .listen(
                          (snapshot) {
                            if (!ownedPatientIds.contains(id)) return;
                            records[id] = snapshot.docs;
                            emit();
                          },
                          onError: (Object e) {
                            if (!controller.isClosed) controller.addError(e);
                          },
                        ),
                  );
                }
              },
              onError: (Object e) {
                if (!controller.isClosed) controller.addError(e);
              },
            );
      },
      onCancel: () async {
        await patients?.cancel();
        for (final subscription in subscriptions.values) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Marks unread messages as read in a conversation for the viewing role.
  Future<void> markConversationAsRead({
    required String conversationId,
    required String userRole,
  }) async {
    try {
      final docRef = _conversations.doc(conversationId);
      final docSnap = await docRef.get();
      if (!docSnap.exists) return;

      if (userRole == 'patient') {
        await docRef.update({'unreadCountPatient': 0});
      } else if (userRole == 'doctor') {
        await docRef.update({'unreadCountDoctor': 0});
      }
    } catch (e) {
      // Best-effort read marker
    }
  }

  /// Migrates legacy messages from users/{patientId}/messages to conversations/{patientId}_{doctorId}/messages
  /// if the conversation is newly created or empty, preserving backward compatibility.
  Future<void> migrateLegacyMessagesIfAny(
    String patientId,
    String doctorId,
  ) async {
    try {
      final conversationId = getConversationId(patientId, doctorId);
      final existing = await _conversationMessages(conversationId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return;
      }

      final legacy = await _messages(patientId)
          .orderBy('createdAt', descending: false)
          .get();
      if (legacy.docs.isEmpty) return;

      final batch = _firestore.batch();
      Timestamp? lastTime;
      String? lastText;
      String? lastSender;
      String? lastRole;

      for (final doc in legacy.docs) {
        final data = doc.data();
        final senderRole = data['senderRole']?.toString() ?? 'patient';
        final senderId = data['senderId']?.toString() ?? '';

        if (senderRole == 'doctor' && senderId != doctorId) {
          continue;
        }

        final isPatient = senderRole == 'patient';
        final receiverId = isPatient ? doctorId : patientId;
        final createdAt = data['createdAt'] as Timestamp? ?? Timestamp.now();
        final text = data['text']?.toString() ?? '';

        final newMsgRef = _conversationMessages(conversationId).doc(doc.id);
        batch.set(newMsgRef, {
          'conversationId': conversationId,
          'senderId': senderId,
          'receiverId': receiverId,
          'patientId': patientId,
          'doctorId': doctorId,
          'senderRole': senderRole,
          'text': text,
          'createdAt': createdAt,
          'read': true,
          'readByPatient': true,
          'readByDoctor': true,
        });

        lastTime = createdAt;
        lastText = text;
        lastSender = senderId;
        lastRole = senderRole;
      }

      if (lastText != null) {
        final convRef = _conversations.doc(conversationId);
        batch.set(convRef, {
          'patientId': patientId,
          'doctorId': doctorId,
          'lastMessage': lastText,
          'lastMessageAt': lastTime ?? Timestamp.now(),
          'lastSenderId': lastSender ?? '',
          'lastSenderRole': lastRole ?? 'patient',
          'unreadCountPatient': 0,
          'unreadCountDoctor': 0,
          'updatedAt': lastTime ?? Timestamp.now(),
        }, SetOptions(merge: true));

        await batch.commit();
      }
    } catch (e) {
      // Non-fatal
    }
  }

  Future<void> addDoctorFeedback({
    required String patientId,
    required String assessmentId,
    required String feedback,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You are not signed in.');
    final trimmed = feedback.trim();
    if (trimmed.isEmpty) return;

    await _assessments(patientId).doc(assessmentId).update({
      'doctorFeedback': trimmed,
      'doctorFeedbackBy': user.uid,
      'doctorFeedbackAt': Timestamp.now(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllUsers() {
    return _users.snapshots();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getDoctors() async {
    final snapshot = await _users.where('role', isEqualTo: 'doctor').get();
    return snapshot.docs
        .where(
          (doc) =>
              doc.data()['accountActive'] != false &&
              doc.data()['isApproved'] != false,
        )
        .toList();
  }

  Future<void> updateUserRole({
    required String uid,
    required String role,
  }) async {
    await _users.doc(uid).update({'role': role});
  }

  Future<void> assignDoctor({
    required String patientId,
    required String? doctorId,
  }) async {
    await _users.doc(patientId).update({'doctorId': doctorId});
  }
}

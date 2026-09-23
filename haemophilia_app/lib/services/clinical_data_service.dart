import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClinicalDataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
  ) =>
      _conversations.doc(conversationId).collection('messages');

  /// Streams all conversations for a patient.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPatientConversations(
    String patientId,
  ) {
    return _conversations
        .where('patientId', isEqualTo: patientId)
        .snapshots();
  }

  /// Streams all conversations for a doctor.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchDoctorConversations(
    String doctorId,
  ) {
    return _conversations
        .where('doctorId', isEqualTo: doctorId)
        .snapshots();
  }

  /// Streams messages in a specific conversation thread.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchConversationMessages(
    String conversationId,
  ) {
    return _conversationMessages(conversationId)
        .orderBy('createdAt', descending: false)
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
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('You are not signed in.');
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final conversationId = getConversationId(patientId, doctorId);
    final isPatient = senderRole == 'patient';
    final receiverId = isPatient ? doctorId : patientId;
    final now = Timestamp.now();

    // 1. Add message to the conversation's messages subcollection
    await _conversationMessages(conversationId).add({
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
    });

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

    await _conversations.doc(conversationId).set(
      convDoc,
      SetOptions(merge: true),
    );
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
        await docRef.update({
          'unreadCountPatient': 0,
        });
      } else if (userRole == 'doctor') {
        await docRef.update({
          'unreadCountDoctor': 0,
        });
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
      final existing =
          await _conversationMessages(conversationId).limit(1).get();
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
        batch.set(
          convRef,
          {
            'patientId': patientId,
            'doctorId': doctorId,
            'lastMessage': lastText,
            'lastMessageAt': lastTime ?? Timestamp.now(),
            'lastSenderId': lastSender ?? '',
            'lastSenderRole': lastRole ?? 'patient',
            'unreadCountPatient': 0,
            'unreadCountDoctor': 0,
            'updatedAt': lastTime ?? Timestamp.now(),
          },
          SetOptions(merge: true),
        );

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
    return snapshot.docs;
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
    await _users.doc(patientId).update({
      'doctorId': doctorId,
    });
  }
}

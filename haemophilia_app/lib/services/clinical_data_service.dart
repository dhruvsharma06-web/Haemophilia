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

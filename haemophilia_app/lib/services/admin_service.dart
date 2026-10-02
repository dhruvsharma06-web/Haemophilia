import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

class AdminService {
  final _db = FirebaseFirestore.instance;

  Future<void> createDoctor(Map<String, String> details) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in.');
    final token = await user.getIdToken();
    final project = Firebase.app().options.projectId;
    final response = await http
        .post(
          Uri.parse(
            'https://us-central1-$project.cloudfunctions.net/create_doctor_account',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'data': details}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) {
      throw StateError('Doctor account creation is currently unavailable. Please contact support.');
    }
    Map<String, dynamic> decoded;
    try { decoded = jsonDecode(response.body) as Map<String, dynamic>; }
    catch (_) { throw StateError('Could not save. Please try again.'); }
    if (response.statusCode != 200 || decoded['error'] != null) {
      throw StateError((decoded['error'] as Map?)?['message']?.toString() ?? 'Could not save. Please try again.');
    }
  }

  Future<void> manageUser({
    required String uid,
    required String role,
    required bool active,
    String? doctorId,
  }) async {
    final actor = FirebaseAuth.instance.currentUser?.uid;
    if (actor == null) throw StateError('Please sign in.');
    final userRef = _db.collection('users').doc(uid);
    final assignmentRef = _db.collection('exerciseAssignments').doc(uid);
    await _db.runTransaction((tx) async {
      final actorDoc = await tx.get(_db.collection('users').doc(actor));
      final userDoc = await tx.get(userRef);
      final assignment = await tx.get(assignmentRef);
      if (actorDoc.data()?['role'] != 'admin' || actorDoc.data()?['accountActive'] == false) {
        throw StateError('Administrator access required.');
      }
      if (!userDoc.exists) throw StateError('This record is no longer available. Refresh and try again.');
      if (uid == actor) {
        throw StateError(
          'Your own administrator account cannot be changed here.',
        );
      }
      if (doctorId != null) {
        final doctor = await tx.get(_db.collection('users').doc(doctorId));
        final d = doctor.data();
        if (d == null ||
            d['role'] != 'doctor' ||
            d['isApproved'] == false ||
            d['accountActive'] == false) {
          throw StateError('Select an active approved doctor.');
        }
      }
      final oldDoctor = userDoc.data()?['doctorId'];
      if (role == 'doctor' && userDoc.data()?['role'] != 'doctor') {
        for (final field in [
          'registrationNumber',
          'specialization',
          'hospital',
        ]) {
          if (userDoc.data()?[field]?.toString().trim().isNotEmpty != true) {
            throw StateError(
              'Complete the doctor registration details before approval.',
            );
          }
        }
      }
      final newDoctor = role == 'patient' ? doctorId : null;
      tx.update(userRef, {
        'role': role,
        'accountActive': active,
        'isApproved': role == 'doctor' || role == 'admin',
        'status': !active
            ? 'inactive'
            : role == 'pending_doctor'
            ? 'pending_approval'
            : 'approved',
        'doctorId': newDoctor,
        'approvedBy': actor,
        'approvalUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (assignment.exists && oldDoctor != newDoctor) {
        tx.update(assignmentRef, {
          'doctorId': newDoctor,
          'previousDoctorId': oldDoctor,
          'status': newDoctor == null
              ? 'cancelled'
              : assignment.data()?['status'] ?? 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      tx.set(_db.collection('adminAudit').doc(), {
        'actorId': actor,
        'userId': uid,
        'action': 'manage_user',
        'previousRole': userDoc.data()?['role'],
        'role': role,
        'previousDoctorId': oldDoctor,
        'doctorId': newDoctor,
        'accountActive': active,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return oldDoctor != newDoctor;
    });
  }
}

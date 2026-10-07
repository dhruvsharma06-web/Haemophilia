import 'local_test_config.dart';
import 'session_lifecycle_service.dart';
import '../utils/schedule_utils.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AssessmentHistoryService {
  final FirebaseFirestore _firestore = LocalTestConfig.database;
  final FirebaseAuth _auth = LocalTestConfig.auth;
  final FirebaseStorage _storage = LocalTestConfig.storage;

  String? get currentUserId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _collection(String uid) {
    return _firestore.collection('users').doc(uid).collection('assessments');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAssessments([
    String? uid,
    int limit = 50,
  ]) {
    final targetUid = uid ?? _auth.currentUser?.uid;
    if (targetUid == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return _collection(targetUid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Streams unfinished (active or paused) assessment sessions for a patient.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchUnfinishedSessions(
    String patientId,
  ) {
    return _firestore
        .collection('assessmentSessions')
        .where('patientId', isEqualTo: patientId)
        .snapshots();
  }

  /// Explicitly marks a session as abandoned so it does not linger in active/paused state.
  /// Historical completed sessions and completed assignments are NEVER modified.
  Future<void> abandonSession(String sessionId, [String? patientId]) async {
    final uid = patientId ?? _auth.currentUser?.uid;
    if (uid == null) return;
    await SessionLifecycleService().expire(uid);
    final assignmentRef = _firestore.collection('exerciseAssignments').doc(uid);
    final sessionRef = _firestore
        .collection('assessmentSessions')
        .doc(sessionId);
    await _firestore.runTransaction((tx) async {
      final assignment = (await tx.get(assignmentRef)).data();
      final session = (await tx.get(sessionRef)).data();
      if (assignment == null ||
          session == null ||
          assignment['sessionId'] != sessionId ||
          !assignmentAvailable(assignment, DateTime.now()) ||
          !unfinishedSessionStatuses.contains(session['status'])) {
        return;
      }
      final now = FieldValue.serverTimestamp();
      tx.update(assignmentRef, {
        'status': 'discarded',
        'discardedAt': now,
        'lastUpdatedAt': now,
        'updatedAt': now,
      });
      tx.update(sessionRef, {
        'status': 'abandoned',
        'abandonedAt': now,
        'lastUpdatedAt': now,
        'updatedAt': now,
      });
    });
  }

  Future<void> saveCompletedRep({
    required String exercise,
    required String sessionId,
    required Map<String, dynamic> rep,
    String? sessionName,
    String? errorFrameUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated Firebase user is available.');
    }

    final uid = user.uid;
    final now = Timestamp.now();
    String? uploadedErrorFrameUrl;

    // Prefer the URL passed by the live screen. Also accept a URL embedded
    // directly in the completed-rep payload.
    final frameUrl = (errorFrameUrl != null && errorFrameUrl.trim().isNotEmpty)
        ? errorFrameUrl.trim()
        : (rep['error_frame_url']?.toString().trim() ??
              rep['errorFrameUrl']?.toString().trim() ??
              '');

    if (frameUrl.isNotEmpty) {
      try {
        uploadedErrorFrameUrl = await _uploadErrorFrame(
          uid: uid,
          sessionId: sessionId,
          repNumber: _number(rep['rep_number'])?.toInt() ?? 0,
          url: frameUrl,
        );
      } catch (e) {
        debugPrint('Error frame upload failed: $e');
      }
    }

    final resolvedSessionName =
        (sessionName != null && sessionName.trim().isNotEmpty)
        ? sessionName.trim()
        : (rep['sessionName']?.toString().trim() ?? '');

    final data = <String, dynamic>{
      'exercise': exercise,
      'sessionId': sessionId,
      'sessionName': resolvedSessionName,
      'form': rep['form']?.toString() ?? rep['label']?.toString() ?? 'Unknown',
      'repNumber': _number(rep['rep_number'])?.toInt(),
      'score': _number(rep['score']),
      'rangeOfMotion': _number(rep['range_of_motion'] ?? rep['rom']),
      'duration': _number(rep['duration']),
      'speed': rep['speed']?.toString() ?? 'Unknown',
      'modelIdentity': rep['model_identity']?.toString(),
      'modelVersion': rep['model_version']?.toString(),
      'decisionScore': _number(rep['decision_score']),
      'confidence': _number(rep['confidence'] ?? rep['lstm_confidence']),
      'smoothness': _number(rep['smoothness']),
      'minimumAngle': _number(rep['minimum_angle']),
      'maximumAngle': _number(rep['maximum_angle']),
      'returnCompletion': _number(rep['return_completion']),
      'angularSpeed': _number(rep['angular_speed']),
      'scoreKind': rep['score_kind']?.toString(),
      'hand': rep['hand']?.toString(),
      'feedbackDetails': rep['feedback_details'],
      'angleTrace': rep['angle_trace'],
      'experimental': rep['experimental'] == true,
      'errorType':
          rep['error_type']?.toString() ?? rep['error']?.toString() ?? '',
      'feedback': rep['feedback']?.toString() ?? '',
      'errorFramePath': rep['error_frame_path']?.toString() ?? '',
      'errorFrameUrl': uploadedErrorFrameUrl ?? '',
      'createdAt': now,
      'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
    };

    final number = _number(rep['rep_number'])?.toInt();
    final document = number == null
        ? _collection(uid).doc()
        : _collection(uid).doc('${sessionId}_rep_$number');
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(document);
      if (!existing.exists) transaction.set(document, data);
    });
    debugPrint(
      'Assessment history saved: users/$uid/assessments/${document.id} '
      '(session: $sessionId)',
    );
  }

  Future<String> _uploadErrorFrame({
    required String uid,
    required String sessionId,
    required int repNumber,
    required String url,
  }) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Backend returned HTTP ${response.statusCode}.');
    }

    final Uint8List bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw Exception('Backend returned an empty error-frame image.');
    }

    final safeRep = repNumber > 0
        ? repNumber
        : DateTime.now().millisecondsSinceEpoch;

    final ref = _storage.ref(
      'assessment_errors/$uid/$sessionId/rep_$safeRep.jpg',
    );

    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

    return ref.getDownloadURL();
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AssessmentHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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
    final now = FieldValue.serverTimestamp();
    try {
      final sessionDoc = await _firestore
          .collection('assessmentSessions')
          .doc(sessionId)
          .get();
      final sessionData = sessionDoc.data();
      // Historical completed sessions must NEVER be marked abandoned or deleted!
      if (sessionData?['status'] == 'completed') {
        debugPrint('AssessmentHistoryService: Will NOT abandon completed session $sessionId');
        return;
      }

      await _firestore
          .collection('assessmentSessions')
          .doc(sessionId)
          .set({
        'status': 'abandoned',
        'abandonedAt': now,
        'lastUpdatedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      debugPrint('AssessmentHistoryService: Session $sessionId marked as abandoned');

      if (patientId != null && patientId.isNotEmpty) {
        final assignDoc = await _firestore
            .collection('exerciseAssignments')
            .doc(patientId)
            .get();
        final assignData = assignDoc.data();
        final assignSessionId = assignData?['sessionId']?.toString();
        final assignStatus = assignData?['status']?.toString().toLowerCase();

        // Historical completed assignments must NEVER be marked abandoned!
        if (assignStatus == 'completed') {
          return;
        }

        // Only abandon the assignment if it corresponds to this abandoned session,
        // or is currently paused/in_progress. Never overwrite a newly assigned session!
        if (assignSessionId == sessionId ||
            assignStatus == 'paused' ||
            assignStatus == 'in_progress') {
          await _firestore
              .collection('exerciseAssignments')
              .doc(patientId)
              .set({
            'status': 'discarded',
            'discardedAt': now,
            'lastUpdatedAt': now,
            'updatedAt': now,
          }, SetOptions(merge: true));
          debugPrint('AssessmentHistoryService: Assignment for $patientId marked as discarded');
        }
      }
    } catch (e) {
      debugPrint('Error abandoning session $sessionId: $e');
    }
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

    final resolvedSessionName = (sessionName != null && sessionName.trim().isNotEmpty)
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
      'confidence': _number(rep['confidence'] ?? rep['lstm_confidence']),
      'errorType': rep['error_type']?.toString() ?? rep['error']?.toString() ?? '',
      'feedback': rep['feedback']?.toString() ?? '',
      'errorFramePath': rep['error_frame_path']?.toString() ?? '',
      'errorFrameUrl': uploadedErrorFrameUrl ?? '',
      'createdAt': now,
      'createdAtMillis': DateTime.now().millisecondsSinceEpoch,
    };

    final number = _number(rep['rep_number'])?.toInt();
    final document = number == null ? _collection(uid).doc() : _collection(uid).doc('${sessionId}_rep_$number');
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

    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return ref.getDownloadURL();
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

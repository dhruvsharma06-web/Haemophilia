import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/local_test_config.dart';
import '../../utils/app_localizations.dart';
import '../../utils/firebase_errors.dart';
import '../../utils/schedule_utils.dart';
import 'live_assessment_screen.dart';

/// Legacy entry points share the local camera assessment and expiry policy.
class AssignedAssessmentScreen extends StatefulWidget {
  const AssignedAssessmentScreen({super.key});
  @override
  State<AssignedAssessmentScreen> createState() =>
      _AssignedAssessmentScreenState();
}

class _AssignedAssessmentScreenState extends State<AssignedAssessmentScreen> {
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _assignment;
  @override
  void initState() {
    super.initState();
    final uid = LocalTestConfig.auth.currentUser?.uid;
    _assignment = uid == null
        ? Future.error(StateError('Please sign in.'))
        : LocalTestConfig.database
              .collection('exerciseAssignments')
              .doc(uid)
              .get();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _assignment,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data?.data();
        final exercises = data?['exercises'] is List
            ? (data!['exercises'] as List)
                  .whereType<Map>()
                  .map((value) => Map<String, dynamic>.from(value))
                  .toList()
            : <Map<String, dynamic>>[];
        if (snapshot.hasError ||
            data == null ||
            exercises.isEmpty ||
            !assignmentAvailable(data, DateTime.now())) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('Assigned Session'))),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.hasError
                      ? firebaseErrorMessage(
                          snapshot.error,
                          fallback: 'Could not load the session. Please retry.',
                        )
                      : tr('This session is no longer available.'),
                ),
              ),
            ),
          );
        }
        exercises.sort(
          (a, b) =>
              ((a['order'] as num?) ?? 0).compareTo((b['order'] as num?) ?? 0),
        );
        return LiveAssessmentScreen(
          exerciseName: exercises.first['exercise']?.toString() ?? '',
          assignedExercises: exercises,
          assignedDoctorId: data['doctorId']?.toString(),
          sessionName: data['sessionName']?.toString(),
          sessionId: data['sessionId']?.toString(),
        );
      },
    );
  }
}

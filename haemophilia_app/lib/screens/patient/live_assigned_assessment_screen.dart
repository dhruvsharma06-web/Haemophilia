import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../assessment/live_assessment_screen.dart';

class AssignedAssessmentScreen extends StatefulWidget {
  const AssignedAssessmentScreen({
    super.key,
  });

  @override
  State<AssignedAssessmentScreen> createState() =>
      _AssignedAssessmentScreenState();
}

class _AssignedAssessmentScreenState
    extends State<AssignedAssessmentScreen> {
  bool _loading = true;
  String? _error;

  String _sessionName = '';
  String _doctorId = '';

  List<Map<String, dynamic>> _exercises = [];

  @override
  void initState() {
    super.initState();
    _loadAssignment();
  }

  // ============================================================
  // LOAD ASSIGNMENT
  // ============================================================

  Future<void> _loadAssignment() async {
    try {
      final user =
          FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception(
          'Please log in again.',
        );
      }

      final snapshot =
          await FirebaseFirestore.instance
              .collection('exerciseAssignments')
              .doc(user.uid)
              .get();

      if (!snapshot.exists) {
        throw Exception(
          'No exercise session has been assigned yet.',
        );
      }

      final data =
          snapshot.data();

      if (data == null) {
        throw Exception(
          'Assignment data could not be loaded.',
        );
      }

      // ----------------------------------------------------------
      // SESSION NAME
      // ----------------------------------------------------------

      final sessionName =
          data['sessionName']
                  ?.toString()
                  .trim() ??
              '';

      if (sessionName.isEmpty) {
        throw Exception(
          'The assigned session has no session name.',
        );
      }

      // ----------------------------------------------------------
      // DOCTOR
      // ----------------------------------------------------------

      final doctorId =
          data['doctorId']
                  ?.toString()
                  .trim() ??
              '';

      if (doctorId.isEmpty) {
        throw Exception(
          'The assigned session has no doctor.',
        );
      }

      // ----------------------------------------------------------
      // EXERCISES
      // ----------------------------------------------------------

      final rawExercises =
          data['exercises'];

      if (rawExercises is! List) {
        throw Exception(
          'No exercises were found in this session.',
        );
      }

      final exercises =
          rawExercises
              .whereType<Map>()
              .map(
                (exercise) =>
                    Map<String, dynamic>.from(
                  exercise,
                ),
              )
              .toList();

      if (exercises.isEmpty) {
        throw Exception(
          'No exercises were assigned.',
        );
      }

      // ----------------------------------------------------------
      // NORMALIZE EXERCISE IDs
      // ----------------------------------------------------------

      for (final exercise in exercises) {
        final rawExercise =
            exercise['exercise']
                ?.toString()
                .trim();

        final rawName =
            exercise['name']
                ?.toString()
                .trim();

        final value =
            (rawExercise?.isNotEmpty == true
                    ? rawExercise
                    : rawName)
                ?.toLowerCase()
                .replaceAll(
                  '&',
                  'and',
                )
                .replaceAll(
                  ' ',
                  '_',
                );

        if (value == null ||
            value.isEmpty) {
          continue;
        }

        if (value.contains(
              'assisted_shoulder_flexion',
            ) ||
            value.contains(
              'assisted_shoulder',
            )) {
          exercise['exercise'] =
              'assisted_shoulder_flexion';
        } else if (value.contains(
              'elbow_flexion',
            ) ||
            value.contains(
              'elbow_flexion_extension',
            ) ||
            value.contains(
              'elbow',
            )) {
          exercise['exercise'] =
              'elbow_flexion';
        } else if (value.contains(
              'shoulder_rotation',
            ) ||
            value.contains(
              'shoulder_rotation',
            )) {
          exercise['exercise'] =
              'shoulder_rotation';
        }
      }

      // ----------------------------------------------------------
      // SORT BY ASSIGNED ORDER
      // ----------------------------------------------------------

      exercises.sort(
        (a, b) {
          final aOrder =
              _toInt(a['order']);

          final bOrder =
              _toInt(b['order']);

          return aOrder.compareTo(
            bOrder,
          );
        },
      );

      if (!mounted) return;

      setState(() {
        _sessionName = sessionName;
        _doctorId = doctorId;
        _exercises = exercises;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint(
        'ASSIGNED ASSESSMENT LOAD ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  String _exerciseTitle(
    Map<String, dynamic> exercise,
  ) {
    final name =
        exercise['name']
            ?.toString()
            .trim();

    if (name != null &&
        name.isNotEmpty) {
      return name;
    }

    switch (
        exercise['exercise']
            ?.toString()) {
      case 'assisted_shoulder_flexion':
        return 'Assisted Shoulder Flexion';

      case 'elbow_flexion':
        return 'Elbow Flexion & Extension';

      case 'shoulder_rotation':
        return 'Shoulder Rotation';

      default:
        return 'Exercise';
    }
  }

  IconData _exerciseIcon(
    Map<String, dynamic> exercise,
  ) {
    switch (
        exercise['exercise']
            ?.toString()) {
      case 'assisted_shoulder_flexion':
        return Icons.accessibility_new_rounded;

      case 'elbow_flexion':
        return Icons.fitness_center_rounded;

      case 'shoulder_rotation':
        return Icons.rotate_right_rounded;

      default:
        return Icons.fitness_center_rounded;
    }
  }

  // ============================================================
  // START SESSION
  // ============================================================

  void _startAssessment() {
    if (_exercises.isEmpty) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LiveAssessmentScreen(
          exerciseName:
              _exercises.first['exercise']
                      ?.toString() ??
                  'Assisted Shoulder Flexion',

          assignedExercises:
              _exercises,

          assignedDoctorId:
              _doctorId,

          sessionName:
              _sessionName,
        ),
      ),
    );
  }

  // ============================================================
  // EXERCISE CARD
  // ============================================================

  Widget _exerciseCard(
    Map<String, dynamic> exercise,
    int index,
  ) {
    final target =
        _toInt(
      exercise['targetCorrectReps'],
    );

    return Card(
      elevation: 0,
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
        side: BorderSide(
          color:
              Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Row(
          children: [
            // --------------------------------------------------
            // NUMBER
            // --------------------------------------------------

            Container(
              width: 44,
              height: 44,
              decoration:
                  BoxDecoration(
                color: Theme.of(
                  context,
                )
                    .colorScheme
                    .primary
                    .withValues(
                      alpha: 0.09,
                    ),
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
              ),
              alignment:
                  Alignment.center,
              child: Text(
                '${index + 1}',
                style:
                    TextStyle(
                  color:
                      Theme.of(
                    context,
                  )
                          .colorScheme
                          .primary,
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ),

            const SizedBox(
              width: 13,
            ),

            // --------------------------------------------------
            // EXERCISE INFO
            // --------------------------------------------------

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    _exerciseTitle(
                      exercise,
                    ),
                    style:
                        const TextStyle(
                      fontSize: 15,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    'Target: $target correct reps',
                    style:
                        TextStyle(
                      fontSize: 12,
                      color:
                          Colors.grey
                              .shade600,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              _exerciseIcon(
                exercise,
              ),
              color:
                  Theme.of(
                context,
              )
                      .colorScheme
                      .primary,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoading() {
    return const Center(
      child:
          CircularProgressIndicator(),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(28),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .assignment_late_outlined,
              size: 54,
              color:
                  Colors.grey.shade500,
            ),

            const SizedBox(
              height: 16,
            ),

            const Text(
              'Unable to load session',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              _error ??
                  'Something went wrong.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color:
                    Colors.grey.shade600,
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            FilledButton.icon(
              onPressed:
                  _loadAssignment,
              icon: const Icon(
                Icons.refresh,
              ),
              label:
                  const Text(
                'Try Again',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Assigned Session',
          style: TextStyle(
            fontWeight:
                FontWeight.w800,
          ),
        ),
      ),

      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : SafeArea(
                  child:
                      SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(
                      20,
                      18,
                      20,
                      30,
                    ),
                    child:
                        Center(
                      child:
                          ConstrainedBox(
                        constraints:
                            const BoxConstraints(
                          maxWidth:
                              700,
                        ),
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            // ==========================================
                            // SESSION NAME
                            // ==========================================

                            Card(
                              elevation:
                                  0,
                              color:
                                  Theme.of(
                                context,
                              )
                                      .colorScheme
                                      .primary
                                      .withValues(
                                        alpha:
                                            0.06,
                                      ),
                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  20,
                                ),
                              ),
                              child:
                                  Padding(
                                padding:
                                    const EdgeInsets.all(
                                  20,
                                ),
                                child:
                                    Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Container(
                                      width:
                                          50,
                                      height:
                                          50,
                                      decoration:
                                          BoxDecoration(
                                        color:
                                            Theme.of(
                                          context,
                                        )
                                                .colorScheme
                                                .primary
                                                .withValues(
                                                  alpha:
                                                      0.12,
                                                ),
                                        borderRadius:
                                            BorderRadius
                                                .circular(
                                          15,
                                        ),
                                      ),
                                      child:
                                          Icon(
                                        Icons
                                            .assignment_rounded,
                                        color:
                                            Theme.of(
                                          context,
                                        )
                                                .colorScheme
                                                .primary,
                                        size:
                                            27,
                                      ),
                                    ),

                                    const SizedBox(
                                      width:
                                          14,
                                    ),

                                    Expanded(
                                      child:
                                          Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          Text(
                                            'Physiotherapy Session',
                                            style:
                                                TextStyle(
                                              fontSize:
                                                  12,
                                              color:
                                                  Colors.grey.shade600,
                                              fontWeight:
                                                  FontWeight.w600,
                                            ),
                                          ),

                                          const SizedBox(
                                            height:
                                                4,
                                          ),

                                          Text(
                                            _sessionName,
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  21,
                                              fontWeight:
                                                  FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(
                              height: 26,
                            ),

                            // ==========================================
                            // EXERCISES
                            // ==========================================

                            const Text(
                              'Exercises',
                              style:
                                  TextStyle(
                                fontSize:
                                    21,
                                fontWeight:
                                    FontWeight
                                        .w800,
                              ),
                            ),

                            const SizedBox(
                              height: 5,
                            ),

                            Text(
                              'Complete each exercise in order. '
                              'Only correct repetitions count.',
                              style:
                                  TextStyle(
                                color:
                                    Colors.grey.shade600,
                                fontSize:
                                    13,
                              ),
                            ),

                            const SizedBox(
                              height: 18,
                            ),

                            ..._exercises
                                .asMap()
                                .entries
                                .map(
                              (entry) =>
                                  _exerciseCard(
                                entry
                                    .value,
                                entry
                                    .key,
                              ),
                            ),

                            const SizedBox(
                              height: 14,
                            ),

                            // ==========================================
                            // START BUTTON
                            // ==========================================

                            SizedBox(
                              width:
                                  double.infinity,
                              height:
                                  54,
                              child:
                                  FilledButton
                                      .icon(
                                onPressed:
                                    _startAssessment,
                                icon:
                                    const Icon(
                                  Icons
                                      .play_arrow_rounded,
                                ),
                                label:
                                    const Text(
                                  'Start Session',
                                  style:
                                      TextStyle(
                                    fontSize:
                                        16,
                                    fontWeight:
                                        FontWeight
                                            .w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
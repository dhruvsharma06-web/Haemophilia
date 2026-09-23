import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../services/notification_service.dart';
import '../../utils/exercise_utils.dart';

class AssignExercisesScreen extends StatefulWidget {
  final String patientId;
  final UserModel patient;

  const AssignExercisesScreen({
    super.key,
    required this.patientId,
    required this.patient,
  });

  @override
  State<AssignExercisesScreen> createState() =>
      _AssignExercisesScreenState();
}

class _AssignExercisesScreenState
    extends State<AssignExercisesScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // ============================================================
  // SESSION NAME
  // ============================================================

  final TextEditingController _sessionNameController =
      TextEditingController();

  // ============================================================
  // EXERCISE SELECTION
  // ============================================================

  final Map<String, bool> _selected = {
    'assisted_shoulder_flexion': true,
    'elbow_flexion': false,
    'shoulder_rotation': false,
  };

  final Map<String, TextEditingController> _repControllers = {
    'assisted_shoulder_flexion':
        TextEditingController(text: '10'),
    'elbow_flexion':
        TextEditingController(text: '10'),
    'shoulder_rotation':
        TextEditingController(text: '10'),
  };

  bool _saving = false;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void dispose() {
    _sessionNameController.dispose();

    for (final controller in _repControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _exerciseTitle(String exercise) {
    return getExerciseDisplayName(exercise);
  }

  IconData _exerciseIcon(String exercise) {
    switch (exercise) {
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
  // SAVE ASSIGNMENT
  // ============================================================

  Future<void> _saveAssignment() async {
    if (_saving) return;

    final sessionName =
        _sessionNameController.text.trim();

    // ----------------------------------------------------------
    // Validate session name
    // ----------------------------------------------------------

    if (sessionName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a session name.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // Build selected exercises
    // ----------------------------------------------------------

    final selectedExercises =
        <Map<String, dynamic>>[];

    final exerciseOrder = [
      'assisted_shoulder_flexion',
      'elbow_flexion',
      'shoulder_rotation',
    ];

    for (final exercise in exerciseOrder) {
      if (_selected[exercise] != true) {
        continue;
      }

      final reps = int.tryParse(
        _repControllers[exercise]!.text.trim(),
      );

      if (reps == null || reps <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter a valid target for '
              '${_exerciseTitle(exercise)}.',
            ),
          ),
        );

        return;
      }

      selectedExercises.add({
        'exercise': exercise,
        'name': _exerciseTitle(exercise),
        'targetCorrectReps': reps,
        'order': selectedExercises.length + 1,
      });
    }

    // ----------------------------------------------------------
    // Validate exercise selection
    // ----------------------------------------------------------

    if (selectedExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one exercise.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // Get doctor ID
    // ----------------------------------------------------------

    final doctorId = _auth.currentUser?.uid;

    if (doctorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Doctor account not found. Please log in again.',
          ),
        ),
      );

      return;
    }

    // ----------------------------------------------------------
    // Save
    // ----------------------------------------------------------

    setState(() {
      _saving = true;
    });

    try {
      await _firestore
          .collection('exerciseAssignments')
          .doc(widget.patientId)
          .set({
        'patientId': widget.patientId,
        'doctorId': doctorId,

        // NEW:
        'sessionName': sessionName,

        'exercises': selectedExercises,
        'status': 'assigned',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send push notification to patient
      await NotificationService().sendNotification(
        targetUserId: widget.patientId,
        title: 'New Physiotherapy Session',
        body: 'You have a new session assigned by your doctor: $sessionName',
        data: {
          'type': 'session_assigned',
          'sessionName': sessionName,
          'patientId': widget.patientId,
          'doctorId': doctorId,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Exercises assigned successfully.',
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint(
        'ASSIGNMENT FIRESTORE ERROR: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save assignment: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ============================================================
  // EXERCISE CARD
  // ============================================================

  Widget _exerciseCard(String exercise) {
    final selected =
        _selected[exercise] ?? false;

    final controller =
        _repControllers[exercise]!;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.35)
              : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.09),
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _exerciseIcon(exercise),
                    color: Theme.of(context)
                        .colorScheme
                        .primary,
                  ),
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _exerciseTitle(exercise),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isWorkInProgressExercise(exercise)) ...[
                            const SizedBox(width: 8),
                            buildWipBadge(compact: true),
                          ],
                        ],
                      ),
                      if (isWorkInProgressExercise(exercise)) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Under active clinical validation',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                Switch(
                  value: selected,
                  onChanged: (value) {
                    setState(() {
                      _selected[exercise] = value;
                    });
                  },
                ),
              ],
            ),

            if (selected) ...[
              const SizedBox(height: 16),

              TextField(
                controller: controller,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Target correct reps',
                  hintText: 'Example: 10',
                  prefixIcon: Icon(
                    Icons.repeat_rounded,
                  ),
                  border:
                      OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 7),

              Align(
                alignment:
                    Alignment.centerLeft,
                child: Text(
                  'Only correct repetitions will '
                  'count toward this target.',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Assign Exercises',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            30,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 700,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // PATIENT CARD
                  // ==================================================

                  Card(
                    elevation: 0,
                    child: Padding(
                      padding:
                          const EdgeInsets.all(17),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 27,
                            child: Text(
                              widget.patient.name
                                      .isEmpty
                                  ? 'P'
                                  : widget.patient
                                      .name[0]
                                      .toUpperCase(),
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                          ),

                          const SizedBox(width: 13),

                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                const Text(
                                  'Assign exercises for',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Colors.grey,
                                  ),
                                ),

                                const SizedBox(height: 3),

                                Text(
                                  widget.patient
                                          .name
                                          .isEmpty
                                      ? 'Patient'
                                      : widget.patient
                                          .name,
                                  style:
                                      const TextStyle(
                                    fontSize: 19,
                                    fontWeight:
                                        FontWeight
                                            .w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==================================================
                  // SESSION NAME
                  // ==================================================

                  const Text(
                    'Session details',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    'Give this physiotherapy session '
                    'a name before assigning exercises.',
                    style: TextStyle(
                      color:
                          Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    controller:
                        _sessionNameController,
                    textCapitalization:
                        TextCapitalization.words,
                    decoration:
                        InputDecoration(
                      labelText:
                          'Session Name',
                      hintText:
                          'e.g. Morning Upper Body Rehab',
                      prefixIcon: const Icon(
                        Icons.assignment_outlined,
                      ),
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ==================================================
                  // EXERCISE PLAN
                  // ==================================================

                  const Text(
                    'Exercise plan',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    'Select the exercises and set '
                    'the number of correct repetitions required.',
                    style: TextStyle(
                      color:
                          Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 18),

                  _exerciseCard(
                    'assisted_shoulder_flexion',
                  ),

                  _exerciseCard(
                    'elbow_flexion',
                  ),

                  _exerciseCard(
                    'shoulder_rotation',
                  ),

                  const SizedBox(height: 12),

                  // ==================================================
                  // SAVE BUTTON
                  // ==================================================

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child:
                        FilledButton.icon(
                      onPressed:
                          _saving
                              ? null
                              : _saveAssignment,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons
                                  .assignment_turned_in_rounded,
                            ),
                      label: Text(
                        _saving
                            ? 'Saving...'
                            : 'Save Assignment',
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
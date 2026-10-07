import '../../services/local_test_config.dart';
import '../../widgets/app_text.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../../utils/schedule_utils.dart';
import '../../services/exercise_schedule_service.dart';
import '../../utils/firebase_errors.dart';
import '../support/help_screen.dart';
import '../../utils/app_localizations.dart';
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
  State<AssignExercisesScreen> createState() => _AssignExercisesScreenState();
}

class _AssignExercisesScreenState extends State<AssignExercisesScreen> {
  final FirebaseFirestore _firestore = LocalTestConfig.database;

  final FirebaseAuth _auth = LocalTestConfig.auth;

  // ============================================================
  // SESSION NAME
  // ============================================================

  final TextEditingController _sessionNameController = TextEditingController();

  // ============================================================
  // EXERCISE SELECTION
  // ============================================================

  final Map<String, bool> _selected = {
    kAssistedShoulderFlexion: true,
    kShoulderRotation: false,
    kAssistedElbowFlexionV5: false,
    kElbowFlexionExtension: false,
  };

  final Map<String, TextEditingController> _repControllers = {
    kAssistedShoulderFlexion: TextEditingController(text: '10'),
    kShoulderRotation: TextEditingController(text: '10'),
    kAssistedElbowFlexionV5: TextEditingController(text: '10'),
    kElbowFlexionExtension: TextEditingController(text: '10'),
  };

  bool _saving = false;
  bool _assignNow = true;
  String? _editingScheduleId;
  DateTime _start = DateTime.now().add(const Duration(minutes: 5));
  final Set<int> _additionalTimes = {};
  String _repeat = 'Once';
  int _days = 7;
  final Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 366)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time != null && mounted) {
      setState(
        () => _setStart(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        ),
      );
    }
  }

  List<int> get _dailyTimes =>
      {_start.hour * 60 + _start.minute, ..._additionalTimes}.toList()..sort();

  void _setStart(DateTime value) {
    final times = {value.hour * 60 + value.minute, ..._additionalTimes}.toList()
      ..sort();
    _start = DateTime(
      value.year,
      value.month,
      value.day,
      times.first ~/ 60,
      times.first % 60,
    );
    _additionalTimes
      ..clear()
      ..addAll(times.skip(1));
  }

  Future<void> _addTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start.add(const Duration(hours: 3))),
    );
    if (time == null || !mounted) return;
    final minute = time.hour * 60 + time.minute;
    if (_dailyTimes.contains(minute)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('This time is already selected.'))),
      );
      return;
    }
    setState(() {
      final times = {..._dailyTimes, minute}.toList()..sort();
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        times.first ~/ 60,
        times.first % 60,
      );
      _additionalTimes
        ..clear()
        ..addAll(times.skip(1));
    });
  }

  Widget _scheduleCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Assign now')),
            subtitle: Text(
              tr('Available for 1 hour from the scheduled start time.'),
            ),
            value: _assignNow && _editingScheduleId == null,
            onChanged: _saving || _editingScheduleId != null
                ? null
                : (value) => setState(() => _assignNow = value),
          ),
          if (!_assignNow || _editingScheduleId != null) ...[
            if (_editingScheduleId != null)
              Text(
                tr('Editing this occurrence. Changes apply only after saving.'),
              ),
            Text(
              tr('Schedule'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: AppText(
                '${readableDate(_start)} · ${TimeOfDay.fromDateTime(_start).format(context)}',
              ),
              subtitle: Text(
                tr('Start date and time (this device’s timezone)'),
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: _saving ? null : _pickStart,
            ),
            Text(
              tr('Daily session times'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final minute in _dailyTimes)
                  InputChip(
                    label: Text(
                      TimeOfDay(
                        hour: minute ~/ 60,
                        minute: minute % 60,
                      ).format(context),
                    ),
                    onDeleted: _saving || minute == _dailyTimes.first
                        ? null
                        : () => setState(() => _additionalTimes.remove(minute)),
                  ),
              ],
            ),
            if (_editingScheduleId == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving || _dailyTimes.length >= 12
                      ? null
                      : _addTime,
                  icon: const Icon(Icons.add),
                  label: Text(tr('Add another time')),
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _repeat,
              items: ['Once', 'One week', 'One month', 'Custom days']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(tr(value))),
                  )
                  .toList(),
              onChanged: _saving || _editingScheduleId != null
                  ? null
                  : (value) => setState(() => _repeat = value!),
            ),
            if (_repeat == 'Custom days')
              TextFormField(
                initialValue: '7',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Number of days (1–366)'),
                ),
                onChanged: (value) => _days = int.tryParse(value) ?? 0,
              ),
            if (_repeat != 'Once')
              Wrap(
                spacing: 4,
                children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(
                      label: Text(
                        tr(
                          ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i -
                              1],
                        ),
                      ),
                      selected: _weekdays.contains(i),
                      onSelected: _saving
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _weekdays.add(i);
                              } else {
                                _weekdays.remove(i);
                              }
                            }),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Patients are notified only when a session becomes available. An active or paused session is never overwritten.',
              ),
            ),
          ],
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('exerciseAssignments')
                .doc(widget.patientId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(firebaseErrorMessage(snapshot.error));
              }
              final d = snapshot.data?.data();
              if (d == null ||
                  !unfinishedSessionStatuses.contains(d['status'])) {
                return const SizedBox.shrink();
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${tr('Current session')}: ${d['sessionName'] ?? ''}',
                      ),
                      Text(trStatus(d['status']?.toString())),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(tr('Cancel this session?')),
                                    content: Text(
                                      tr(
                                        'The patient will no longer be able to start or resume this session.',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: Text(tr('Keep session')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(tr('Cancel session')),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                try {
                                  await ExerciseScheduleService().cancelSession(
                                    widget.patientId,
                                    assignmentKey(d),
                                  );
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          e is StateError
                                              ? tr(e.message.toString())
                                              : firebaseErrorMessage(e),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Text(tr('Cancel session')),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('exerciseScheduleSeries')
                .where('patientId', isEqualTo: widget.patientId)
                .where('doctorId', isEqualTo: _auth.currentUser?.uid)
                .snapshots(),
            builder: (context, seriesSnapshot) {
              if (seriesSnapshot.hasError) {
                return Text(
                  firebaseErrorMessage(
                    seriesSnapshot.error,
                    fallback: 'Could not load schedule.',
                  ),
                );
              }
              if (!seriesSnapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final readySeries = seriesSnapshot.data!.docs
                  .where((doc) => doc.data()['status'] == 'ready')
                  .map((doc) => doc.id)
                  .toSet();
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('exerciseSchedules')
                    .where('patientId', isEqualTo: widget.patientId)
                    .where('doctorId', isEqualTo: _auth.currentUser?.uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      firebaseErrorMessage(
                        snap.error,
                        fallback: 'Could not load schedule.',
                      ),
                    );
                  }
                  if (!snap.hasData) return const LinearProgressIndicator();
                  final pending =
                      (snap.data?.docs ?? [])
                          .where(
                            (d) =>
                                d.data()['status'] == 'scheduled' &&
                                sessionExpiry(d.data()) != null &&
                                DateTime.now().isBefore(
                                  sessionExpiry(d.data())!,
                                ) &&
                                (d.data()['managedSeries'] != true ||
                                    readySeries.contains(d.data()['seriesId'])),
                          )
                          .toList()
                        ..sort(
                          (a, b) => (a.data()['scheduledAt'] as Timestamp)
                              .compareTo(b.data()['scheduledAt'] as Timestamp),
                        );
                  return Column(
                    children: pending.map((doc) {
                      final d = doc.data();
                      final date = (d['scheduledAt'] as Timestamp).toDate();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(d['sessionName']?.toString() ?? ''),
                        subtitle: AppText(
                          '${readableDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            try {
                              if (action == 'Cancel remaining series' &&
                                  d['managedSeries'] == true) {
                                await ExerciseScheduleService().cancelSeries(
                                  d['seriesId'].toString(),
                                );
                              } else if (action != 'Edit this session') {
                                final toCancel =
                                    action == 'Cancel remaining series'
                                    ? pending.where(
                                        (p) =>
                                            p.data()['seriesId'] ==
                                            d['seriesId'],
                                      )
                                    : [doc];
                                final batch = _firestore.batch();
                                for (final p in toCancel) {
                                  batch.update(p.reference, {
                                    'status': 'cancelled',
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  });
                                }
                                await batch.commit();
                              }
                              if (action == 'Edit this session' && mounted) {
                                setState(() {
                                  _editingScheduleId = doc.id;
                                  _start = date;
                                  _additionalTimes.clear();
                                  _repeat = 'Once';
                                  _sessionNameController.text =
                                      d['sessionName']?.toString() ?? '';
                                  for (final key in _selected.keys) {
                                    _selected[key] = false;
                                  }
                                  for (final raw in (d['exercises'] as List)) {
                                    final e = Map<String, dynamic>.from(raw);
                                    final id = normalizeExerciseId(
                                      e['exercise']?.toString(),
                                    );
                                    if (_selected.containsKey(id)) {
                                      _selected[id] = true;
                                      _repControllers[id]!.text =
                                          e['targetCorrectReps'].toString();
                                    }
                                  }
                                });
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(firebaseErrorMessage(error)),
                                  ),
                                );
                              }
                            }
                          },
                          itemBuilder: (_) =>
                              [
                                    'Edit this session',
                                    'Cancel this session',
                                    'Cancel remaining series',
                                  ]
                                  .map(
                                    (a) => PopupMenuItem(
                                      value: a,
                                      child: Text(tr(a)),
                                    ),
                                  )
                                  .toList(),
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    ),
  );

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
    return tr(getExerciseDisplayName(exercise));
  }

  IconData _exerciseIcon(String exercise) {
    return getExerciseIcon(exercise);
  }

  // ============================================================
  // SAVE ASSIGNMENT
  // ============================================================

  Future<void> _saveAssignment() async {
    if (_saving) return;

    final sessionName = _sessionNameController.text.trim();

    // ----------------------------------------------------------
    // Validate session name
    // ----------------------------------------------------------

    if (sessionName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Please enter a session name.')),
      );

      return;
    }

    // ----------------------------------------------------------
    // Build selected exercises
    // ----------------------------------------------------------

    final selectedExercises = <Map<String, dynamic>>[];

    final exerciseOrder = [
      kAssistedShoulderFlexion,
      kShoulderRotation,
      kAssistedElbowFlexionV5,
      kElbowFlexionExtension,
    ];

    for (final exercise in exerciseOrder) {
      if (_selected[exercise] != true) {
        continue;
      }

      final reps = int.tryParse(_repControllers[exercise]!.text.trim());

      if (reps == null || reps <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
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
        const SnackBar(content: AppText('Select at least one exercise.')),
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
          content: AppText('Doctor account not found. Please log in again.'),
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
      final initialExerciseProgress = selectedExercises.map((e) {
        final exName = e['exercise']?.toString() ?? '';
        return {
          'exercise': exName,
          'name': getExerciseDisplayName(exName),
          'targetCorrectReps':
              int.tryParse(e['targetCorrectReps']?.toString() ?? '0') ?? 0,
          'completedCorrectReps': 0,
          'completedTotalReps': 0,
          'status': 'pending',
        };
      }).toList();

      if (_assignNow && _editingScheduleId == null) {
        await ExerciseScheduleService().assignNow(
          patientId: widget.patientId,
          doctorId: doctorId,
          sessionName: sessionName,
          exercises: selectedExercises,
          exerciseProgress: initialExerciseProgress,
        );
      } else {
        final now = DateTime.now();
        if (!_start.isAfter(now)) {
          throw StateError('Choose a future start time.');
        }
        final monthEnd = DateTime(_start.year, _start.month + 2, 0);
        final nextMonth = DateTime(
          _start.year,
          _start.month + 1,
          _start.day > monthEnd.day ? monthEnd.day : _start.day,
        );
        final days = _repeat == 'Once'
            ? 1
            : _repeat == 'One week'
            ? 7
            : _repeat == 'One month'
            ? DateTime(nextMonth.year, nextMonth.month, nextMonth.day)
                  .difference(DateTime(_start.year, _start.month, _start.day))
                  .inDays
            : _days;
        final dates = scheduledOccurrences(
          start: _start,
          days: days,
          weekdays: _repeat == 'Once' ? {_start.weekday} : _weekdays,
          timesOfDayMinutes: _dailyTimes,
        );
        if (dates.isEmpty) {
          throw StateError('Select at least one scheduled day.');
        }
        await ExerciseScheduleService().save(
          patientId: widget.patientId,
          doctorId: doctorId,
          sessionName: sessionName,
          dates: dates,
          exercises: selectedExercises,
          exerciseProgress: initialExerciseProgress,
          replacedScheduleId: _editingScheduleId,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('Exercise schedule saved.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('ASSIGNMENT FIRESTORE ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? tr(e.message.toString())
                : firebaseErrorMessage(
                    e,
                    fallback: 'Could not save assignment. Please try again.',
                  ),
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
    final selected = _selected[exercise] ?? false;

    final controller = _repControllers[exercise]!;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
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
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _exerciseIcon(exercise),
                    color: Theme.of(context).colorScheme.primary,
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
                          tr('Preview exercise'),
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (exercise == kAssistedElbowFlexionV5)
                        Text(
                          tr('Experimental model'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                          ),
                        ),
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
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Target correct reps'),
                  hintText: tr('Example: 10'),
                  prefixIcon: const Icon(Icons.repeat_rounded),
                  border: const OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 7),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('Only correct repetitions will count toward this target.'),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
    AppLocaleScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Assign Exercises'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [LanguageToggleButton(), SizedBox(width: 8)],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // PATIENT CARD
                  // ==================================================

                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 27,
                            child: Text(
                              widget.patient.name.isEmpty
                                  ? 'P'
                                  : widget.patient.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),

                          const SizedBox(width: 13),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Assign exercises for'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),

                                const SizedBox(height: 3),

                                Text(
                                  widget.patient.name.isEmpty
                                      ? tr('Patient')
                                      : widget.patient.name,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
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

                  _scheduleCard(),
                  const SizedBox(height: 20),
                  // ==================================================
                  // SESSION NAME
                  // ==================================================

                  Text(
                    tr('Session details'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    tr(
                      'Give this physiotherapy session a name before assigning exercises.',
                    ),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    controller: _sessionNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: tr('Session Name'),
                      hintText: tr('e.g. Morning Upper Body Rehab'),
                      prefixIcon: const Icon(Icons.assignment_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ==================================================
                  // EXERCISE PLAN
                  // ==================================================
                  Text(
                    tr('Exercise plan'),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    tr(
                      'Select the exercises and set the number of correct repetitions required.',
                    ),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),

                  const SizedBox(height: 18),

                  _exerciseCard(kAssistedShoulderFlexion),

                  _exerciseCard(kShoulderRotation),

                  _exerciseCard(kAssistedElbowFlexionV5),

                  _exerciseCard(kElbowFlexionExtension),

                  const SizedBox(height: 12),

                  // ==================================================
                  // SAVE BUTTON
                  // ==================================================
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveAssignment,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.assignment_turned_in_rounded),
                      label: Text(
                        _saving ? tr('Saving...') : tr('Save Assignment'),
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

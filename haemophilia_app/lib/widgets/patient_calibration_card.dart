import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/exercise_rules.dart';
import '../services/local_test_config.dart';
import '../services/patient_calibration.dart';
import '../utils/app_localizations.dart';
import '../utils/exercise_utils.dart';
import '../utils/firebase_errors.dart';

/// Doctor view: choose standard, adaptive or manual targets per exercise and
/// preview the adaptive target computed from the patient's recent history.
class PatientCalibrationCard extends StatelessWidget {
  final String patientId;
  final List<Map<String, dynamic>> history;

  const PatientCalibrationCard({
    super.key,
    required this.patientId,
    required this.history,
  });

  static String _modeLabel(CalibrationMode mode) => switch (mode) {
    CalibrationMode.standard => 'Standard targets',
    CalibrationMode.adaptive => 'Adaptive (from recent sessions)',
    CalibrationMode.manual => 'Manual target',
  };

  Future<void> _edit(
    BuildContext context,
    String exercise,
    CalibrationSettings current,
  ) async {
    final rule = ExerciseRule.forExercise(exercise);
    var mode = current.mode;
    final target = TextEditingController(
      text: (current.manualTarget ?? rule.target).toStringAsFixed(0),
    );
    String? error;
    var saving = false;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr(getExerciseDisplayName(exercise))),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in CalibrationMode.values)
                      ChoiceChip(
                        label: Text(tr(_modeLabel(option))),
                        selected: mode == option,
                        onSelected: saving
                            ? null
                            : (_) => setDialogState(() => mode = option),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (mode == CalibrationMode.manual)
                  TextField(
                    controller: target,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('Target angle (degrees)'),
                      helperText:
                          '${tr('Standard target')}: ${rule.target.toStringAsFixed(0)}°',
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Adaptive targets start from the patient\'s recent best range and move toward the standard target in small steps. They never exceed the standard target.',
                  ),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      double? manual;
                      if (mode == CalibrationMode.manual) {
                        manual = double.tryParse(target.text.trim());
                        final valid =
                            manual != null &&
                            (rule.increasing
                                ? manual > rule.enter && manual <= rule.target
                                : manual >= rule.target && manual < rule.enter);
                        if (!valid) {
                          setDialogState(
                            () => error = tr(
                              'Enter a target between the start angle and the standard target.',
                            ),
                          );
                          return;
                        }
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await PatientCalibration.saveSettings(
                          patientId: patientId,
                          exercise: exercise,
                          mode: mode,
                          manualTarget: manual,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        messenger.showSnackBar(
                          SnackBar(content: Text(tr('Calibration saved.'))),
                        );
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = firebaseErrorMessage(e);
                        });
                      }
                    },
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    target.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final exercises = kAllExercises
        .map((e) => normalizeExerciseId(e.id))
        .where(PatientCalibration.supports)
        .toSet()
        .toList();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: LocalTestConfig.database
          .collection('users')
          .doc(patientId)
          .collection('calibrations')
          .snapshots(),
      builder: (context, snapshot) {
        final settings = {
          for (final doc in snapshot.data?.docs ?? const [])
            doc.id: CalibrationSettings.fromMap(doc.data()),
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Movement calibration'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (snapshot.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(firebaseErrorMessage(snapshot.error)),
                  ),
                for (final exercise in exercises)
                  Builder(
                    builder: (context) {
                      final setting =
                          settings[exercise] ?? CalibrationSettings.standard;
                      final result = PatientCalibration.compute(
                        exercise: exercise,
                        settings: setting,
                        history: history,
                        now: DateTime.now(),
                      );
                      final detail = result.status == 'insufficient_history'
                          ? tr(
                              'Not enough recent sessions yet; standard target in use.',
                            )
                          : '${tr(result.personalised ? 'Personalised target' : 'Standard target')}: ${result.target.toStringAsFixed(0)}° (${tr('Standard target')}: ${result.standardTarget.toStringAsFixed(0)}°)';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr(getExerciseDisplayName(exercise))),
                        subtitle: Text('${tr(_modeLabel(setting.mode))}\n$detail'),
                        isThreeLine: true,
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.tune),
                          label: Text(tr('Edit')),
                          onPressed: () => _edit(context, exercise, setting),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../services/exercise_tutorial_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/exercise_utils.dart';
import '../../utils/firebase_errors.dart';

/// Web admin portal: attach one reviewed YouTube tutorial to each exercise.
class ExerciseTutorialsAdminScreen extends StatelessWidget {
  const ExerciseTutorialsAdminScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    ExerciseMetadata exercise,
    ExerciseTutorial? current,
  ) async {
    final link = TextEditingController(text: current?.url ?? '');
    final title = TextEditingController(text: current?.title ?? '');
    String? error;
    var saving = false;
    final service = ExerciseTutorialService();
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> run(Future<void> Function() action, String done) async {
            setDialogState(() {
              saving = true;
              error = null;
            });
            try {
              await action();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              messenger.showSnackBar(SnackBar(content: Text(tr(done))));
            } catch (e) {
              setDialogState(() {
                saving = false;
                error = e is StateError
                    ? tr(e.message.toString())
                    : firebaseErrorMessage(e);
              });
            }
          }

          return AlertDialog(
            title: Text(tr(exercise.displayName)),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Add a YouTube link reviewed by your clinical team. Patients see it on the exercise guide.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: link,
                    enabled: !saving,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: tr('YouTube link'),
                      hintText: 'https://www.youtube.com/watch?v=…',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    enabled: !saving,
                    maxLength: 120,
                    decoration: InputDecoration(labelText: tr('Video title')),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (current != null)
                TextButton(
                  onPressed: saving
                      ? null
                      : () => run(
                          () => service.remove(exercise.id),
                          'Tutorial removed.',
                        ),
                  child: Text(tr('Remove')),
                ),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(tr('Cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () => run(
                        () => service.save(exercise.id, link.text, title.text),
                        'Tutorial saved.',
                      ),
                child: Text(tr('Save')),
              ),
            ],
          );
        },
      ),
    );
    link.dispose();
    title.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    final exercises = kAllExercises
        .where((e) => e.id != kAssistedElbowFlexion)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Exercise tutorials')),
        actions: const [LanguageToggleButton(), SizedBox(width: 8)],
      ),
      body: StreamBuilder<Map<String, ExerciseTutorial>>(
        stream: ExerciseTutorialService().watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(firebaseErrorMessage(snapshot.error)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tutorials = snapshot.data!;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: exercises.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final exercise = exercises[index];
                  final tutorial = tutorials[exercise.id];
                  return Card(
                    child: ListTile(
                      leading: Icon(exercise.icon),
                      title: Text(tr(exercise.displayName)),
                      subtitle: Text(
                        tutorial == null
                            ? tr('No tutorial')
                            : (tutorial.title.isEmpty
                                  ? tutorial.url
                                  : '${tutorial.title}\n${tutorial.url}'),
                      ),
                      isThreeLine: tutorial != null && tutorial.title.isNotEmpty,
                      trailing: TextButton.icon(
                        icon: Icon(
                          tutorial == null ? Icons.add_link : Icons.edit,
                        ),
                        label: Text(tr(tutorial == null ? 'Add' : 'Edit')),
                        onPressed: () => _edit(context, exercise, tutorial),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

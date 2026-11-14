import 'package:flutter/material.dart';

import '../services/exercise_tutorial_service.dart';
import '../utils/app_localizations.dart';

/// "Watch video tutorial" for an exercise, shown only when the clinical team
/// has added a reviewed YouTube link for it.
class ExerciseTutorialButton extends StatelessWidget {
  final String exercise;
  const ExerciseTutorialButton({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ExerciseTutorial?>(
      stream: ExerciseTutorialService().watch(exercise),
      builder: (context, snapshot) {
        final tutorial = snapshot.data;
        if (tutorial == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.ondemand_video_outlined),
            label: Text(
              tutorial.title.isEmpty
                  ? tr('Watch video tutorial')
                  : '${tr('Watch video tutorial')}: ${tutorial.title}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () async {
              final opened = await ExerciseTutorialService.open(tutorial);
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      tr(
                        'Could not open the video. Check your internet connection and try again.',
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/local_test_config.dart';
import '../utils/app_localizations.dart';
import '../utils/exercise_utils.dart';
import '../utils/firebase_errors.dart';

/// Doctor review of the representative images selected from each day's
/// exercise sessions (newest first, last 14 day-exercise records).
class ExerciseSnapshotGallery extends StatelessWidget {
  final String patientId;
  const ExerciseSnapshotGallery({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    AppLocaleScope.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: LocalTestConfig.database
          .collection('users')
          .doc(patientId)
          .collection('exerciseSnapshots')
          .orderBy('day', descending: true)
          .limit(14)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Exercise snapshots'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Representative images selected automatically from each day\'s session.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  Text(firebaseErrorMessage(snapshot.error))
                else if (!snapshot.hasData)
                  const LinearProgressIndicator()
                else if (docs.isEmpty)
                  Text(tr('No exercise snapshots yet.'))
                else
                  for (final doc in docs) _DayRow(data: doc.data()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DayRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final raw in (data['images'] as List? ?? const []))
        if (raw is Map && raw['path'] is String) Map<String, dynamic>.from(raw),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data['day'] ?? ''} · ${tr(getExerciseDisplayName(data['exercise']?.toString()))}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            tr(
              data['trainingEligible'] == true
                  ? 'Research use permitted'
                  : 'Clinical review only',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final image in images) _Thumb(image: image)],
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatefulWidget {
  final Map<String, dynamic> image;
  const _Thumb({required this.image});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late Future<String> _url = _load();

  Future<String> _load() =>
      LocalTestConfig.storage.ref(widget.image['path'] as String).getDownloadURL();

  @override
  void didUpdateWidget(covariant _Thumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image['path'] != widget.image['path']) _url = _load();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final label = tr(
      image['role'] == 'representative' ? 'Most representative' : 'Closest match',
    );
    return FutureBuilder<String>(
      future: _url,
      builder: (context, url) {
        Widget child;
        if (url.hasError) {
          child = Center(child: Text(tr('Could not load image.')));
        } else if (!url.hasData) {
          child = const Center(child: CircularProgressIndicator());
        } else {
          child = Image.network(
            url.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Center(child: Text(tr('Could not load image.'))),
          );
        }
        return InkWell(
          onTap: url.hasData
              ? () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: InteractiveViewer(child: Image.network(url.data!)),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 132, height: 176, child: child),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 132,
                child: Text(
                  '$label · ${tr(image['form']?.toString() ?? '')}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

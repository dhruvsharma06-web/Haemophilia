import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/exercise_utils.dart';
import 'local_test_config.dart';

/// A clinician-reviewed YouTube tutorial for one exercise.
class ExerciseTutorial {
  final String exerciseId;
  final String videoId;
  final String title;

  const ExerciseTutorial({
    required this.exerciseId,
    required this.videoId,
    required this.title,
  });

  String get url => ExerciseTutorialService.canonicalUrl(videoId);

  static ExerciseTutorial? fromMap(String exerciseId, Map<String, dynamic>? d) {
    final id = d?['videoId'];
    if (id is! String || !ExerciseTutorialService.validVideoId(id)) return null;
    final title = d?['title'];
    return ExerciseTutorial(
      exerciseId: exerciseId,
      videoId: id,
      title: title is String ? title : '',
    );
  }
}

/// Tutorials live in `exerciseTutorials/{exerciseId}` and are curated by
/// administrators in the web portal. Only YouTube video links are accepted,
/// and they are stored in one canonical form so rules can validate them.
class ExerciseTutorialService {
  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
    'www.youtu.be',
  };

  static bool validVideoId(String id) => _videoId.hasMatch(id);

  static String canonicalUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';

  /// Extracts the video ID from a pasted YouTube link, or returns null.
  /// Accepts watch, youtu.be, shorts, embed and live links over https.
  static String? parseVideoId(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    if (!_hosts.contains(host)) return null;
    String? candidate;
    if (host.endsWith('youtu.be')) {
      candidate = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (uri.path == '/watch') {
      candidate = uri.queryParameters['v'];
    } else if (uri.pathSegments.length >= 2 &&
        const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
      candidate = uri.pathSegments[1];
    }
    return candidate != null && validVideoId(candidate) ? candidate : null;
  }

  CollectionReference<Map<String, dynamic>> get _collection =>
      LocalTestConfig.database.collection('exerciseTutorials');

  Stream<ExerciseTutorial?> watch(String exercise) {
    if (Firebase.apps.isEmpty) return Stream.value(null);
    final id = normalizeExerciseId(exercise);
    return _collection
        .doc(id)
        .snapshots()
        .map((doc) => ExerciseTutorial.fromMap(id, doc.data()))
        .handleError((Object _) {});
  }

  Stream<Map<String, ExerciseTutorial>> watchAll() =>
      _collection.snapshots().map(
        (query) => {
          for (final doc in query.docs)
            if (ExerciseTutorial.fromMap(doc.id, doc.data()) case final t?)
              doc.id: t,
        },
      );

  Future<void> save(String exercise, String link, String title) async {
    final videoId = parseVideoId(link);
    if (videoId == null) {
      throw StateError('Enter a YouTube link that starts with https://');
    }
    final uid = LocalTestConfig.auth.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in.');
    await _collection.doc(normalizeExerciseId(exercise)).set({
      'videoId': videoId,
      'url': canonicalUrl(videoId),
      'title': title.trim().length > 120
          ? title.trim().substring(0, 120)
          : title.trim(),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> remove(String exercise) =>
      _collection.doc(normalizeExerciseId(exercise)).delete();

  /// Opens the video in the YouTube app or browser. Returns false on failure.
  static Future<bool> open(ExerciseTutorial tutorial) async {
    try {
      return await launchUrl(
        Uri.parse(tutorial.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

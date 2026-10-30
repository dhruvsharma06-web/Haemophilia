import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../utils/exercise_utils.dart';
import 'local_test_config.dart';

/// Pose keypoints used to compare frames: shoulders, elbows, wrists, hips,
/// knees and ankles.
const List<int> snapshotKeypoints = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];

/// Pure functions for choosing representative frames.
class RepresentativeSelector {
  /// Translation- and scale-normalised (x, y) pairs for [snapshotKeypoints].
  /// Hidden points are null. Returns null if the torso is not visible.
  static List<double?>? poseVector(List<Map<String, dynamic>> landmarks) {
    if (landmarks.length < 33) return null;
    double? coord(int id, String axis) {
      final point = landmarks[id];
      final value = point[axis];
      final visibility = point['visibility'];
      if (value is! num || !value.isFinite) return null;
      if (visibility is num && visibility < 0.5) return null;
      return value.toDouble();
    }

    final torso = [11, 12, 23, 24];
    if (torso.any((id) => coord(id, 'x') == null || coord(id, 'y') == null)) {
      return null;
    }
    final shoulderX = (coord(11, 'x')! + coord(12, 'x')!) / 2;
    final shoulderY = (coord(11, 'y')! + coord(12, 'y')!) / 2;
    final hipX = (coord(23, 'x')! + coord(24, 'x')!) / 2;
    final hipY = (coord(23, 'y')! + coord(24, 'y')!) / 2;
    final scale = math.sqrt(
      math.pow(shoulderX - hipX, 2) + math.pow(shoulderY - hipY, 2),
    );
    if (!scale.isFinite || scale < 1e-4) return null;
    final centreX = (shoulderX + hipX) / 2;
    final centreY = (shoulderY + hipY) / 2;
    return [
      for (final id in snapshotKeypoints) ...[
        coord(id, 'x') == null ? null : (coord(id, 'x')! - centreX) / scale,
        coord(id, 'y') == null ? null : (coord(id, 'y')! - centreY) / scale,
      ],
    ];
  }

  /// Root-mean-square difference over coordinates visible in both poses.
  /// Infinity when fewer than half the coordinates can be compared.
  static double distance(List<double?> a, List<double?> b) {
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      final x = a[i], y = b[i];
      if (x == null || y == null) continue;
      sum += (x - y) * (x - y);
      count++;
    }
    if (count * 2 < math.max(a.length, b.length)) return double.infinity;
    return math.sqrt(sum / count);
  }

  /// Picks up to two indices: the medoid (the frame most similar to all
  /// others, i.e. the most representative) and the frame closest to it.
  /// When [preferred] marks any frame (for example correct-form repetitions),
  /// selection is restricted to those frames.
  static List<int> select(List<List<double?>> poses, {List<bool>? preferred}) {
    if (poses.isEmpty) return const [];
    var pool = [for (var i = 0; i < poses.length; i++) i];
    if (preferred != null && preferred.length == poses.length) {
      final good = [for (final i in pool) if (preferred[i]) i];
      if (good.isNotEmpty) pool = good;
    }
    if (pool.length == 1) return pool;
    double cost(int i) {
      var total = 0.0;
      for (final j in pool) {
        if (j == i) continue;
        final d = distance(poses[i], poses[j]);
        total += d.isFinite ? d : 1e6;
      }
      return total;
    }

    var medoid = pool.first;
    var best = double.infinity;
    for (final i in pool) {
      final value = cost(i);
      if (value < best) {
        best = value;
        medoid = i;
      }
    }
    int? closest;
    var closestDistance = double.infinity;
    for (final j in pool) {
      if (j == medoid) continue;
      final d = distance(poses[medoid], poses[j]);
      if (d < closestDistance) {
        closestDistance = d;
        closest = j;
      }
    }
    return [medoid, ?closest];
  }
}

class SnapshotCandidate {
  final Uint8List? jpeg;
  final List<double?> pose;
  final int repIndex;
  String form;
  final DateTime capturedAt;
  final String? storagePath;
  final String sessionId;

  SnapshotCandidate({
    required this.jpeg,
    required this.pose,
    required this.repIndex,
    required this.form,
    required this.capturedAt,
    required this.sessionId,
    this.storagePath,
  });

  static SnapshotCandidate? fromStored(Map<String, dynamic> data) {
    final path = data['path'];
    final pose = data['pose'];
    if (path is! String || pose is! List) return null;
    return SnapshotCandidate(
      jpeg: null,
      pose: [for (final v in pose) v is num ? v.toDouble() : null],
      repIndex: (data['repIndex'] as num?)?.toInt() ?? 0,
      form: data['form']?.toString() ?? '',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        (data['capturedAtMillis'] as num?)?.toInt() ?? 0,
      ),
      sessionId: data['sessionId']?.toString() ?? '',
      storagePath: path,
    );
  }
}

/// Collects candidate frames during one exercise and, after the exercise,
/// stores the one or two most representative images of the day for doctor
/// review (and, with research consent, possible future model training).
///
/// Real-time safety: at most one capture per repetition, taken when the
/// target is reached, requested without awaiting it in the frame loop and
/// encoded natively on a low-priority thread. Memory is bounded by reservoir
/// sampling. Upload happens only after the exercise ends.
class SessionSnapshotCollector {
  static const maxCandidates = 12;
  static const maxBytes = 4 * 1024 * 1024;

  final _random = math.Random();
  final List<SnapshotCandidate> _candidates = [];
  String? _exercise;
  int _seen = 0;
  bool _capturing = false;
  bool _wasTargetReached = false;
  int? _capturedForRep;

  /// Call once per processed frame with the rule engine's state. Never awaits.
  void observe({
    required String exercise,
    required String sessionId,
    required Map<String, dynamic> state,
    required List<Map<String, dynamic>> landmarks,
    required Future<Uint8List?> Function() capture,
  }) {
    final id = normalizeExerciseId(exercise);
    if (_exercise != id) _reset(id);
    final completed = state['completed_rep'];
    if (completed is Map) {
      final index = (completed['rep_index'] as num?)?.toInt();
      for (final candidate in _candidates) {
        if (candidate.repIndex == index) {
          candidate.form = completed['form']?.toString() ?? candidate.form;
        }
      }
    }
    final reached = state['target_reached'] == true;
    final repsDone = (state['rep_count'] as num?)?.toInt() ?? 0;
    final rising = reached && !_wasTargetReached;
    _wasTargetReached = reached;
    if (!rising || _capturing || _capturedForRep == repsDone) return;
    final pose = RepresentativeSelector.poseVector(landmarks);
    if (pose == null) return;
    _capturing = true;
    _capturedForRep = repsDone;
    final repIndex = repsDone + 1;
    final form = state['form']?.toString() ?? '';
    final capturedAt = DateTime.now();
    unawaited(
      capture()
          .then((bytes) {
            if (bytes == null || bytes.isEmpty || bytes.length > maxBytes) {
              return;
            }
            if (_exercise != id) return;
            _add(
              SnapshotCandidate(
                jpeg: bytes,
                pose: pose,
                repIndex: repIndex,
                form: form,
                capturedAt: capturedAt,
                sessionId: sessionId,
              ),
            );
          })
          .catchError((Object error) {
            debugPrint('Snapshot capture skipped: $error');
          })
          .whenComplete(() => _capturing = false),
    );
  }

  void _reset(String id) {
    _exercise = id;
    _candidates.clear();
    _seen = 0;
    _capturing = false;
    _wasTargetReached = false;
    _capturedForRep = null;
  }

  void _add(SnapshotCandidate candidate) {
    _seen++;
    if (_candidates.length < maxCandidates) {
      _candidates.add(candidate);
      return;
    }
    final slot = _random.nextInt(_seen);
    if (slot < maxCandidates) _candidates[slot] = candidate;
  }

  /// Hands over the current exercise's candidates and clears the collector.
  List<SnapshotCandidate> take() {
    final taken = List<SnapshotCandidate>.of(_candidates);
    _reset(_exercise ?? '');
    return taken;
  }

  String? get exercise => _exercise;
}

class SessionSnapshotService {
  static String dayKey(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  static bool _good(SnapshotCandidate c) =>
      c.form.toLowerCase() == 'correct';

  /// Merges [fresh] with the images already kept for today, keeps the best
  /// two, uploads only new winners and removes replaced files. Never throws.
  static Future<void> store({
    required String exercise,
    required String sessionId,
    required List<SnapshotCandidate> fresh,
  }) async {
    if (fresh.isEmpty) return;
    try {
      final uid = LocalTestConfig.auth.currentUser?.uid;
      if (uid == null) return;
      final id = normalizeExerciseId(exercise);
      final day = dayKey(DateTime.now());
      final user = LocalTestConfig.database.collection('users').doc(uid);
      final profile = (await user.get()).data() ?? const {};
      final docRef = user.collection('exerciseSnapshots').doc('${day}_$id');
      final existingDoc = await docRef.get();
      final existing = [
        for (final raw in (existingDoc.data()?['images'] as List? ?? const []))
          if (raw is Map)
            ?SnapshotCandidate.fromStored(Map<String, dynamic>.from(raw)),
      ];
      final pool = [...existing, ...fresh];
      final chosen = RepresentativeSelector.select(
        [for (final c in pool) c.pose],
        preferred: [for (final c in pool) _good(c)],
      ).map((i) => pool[i]).toList();
      if (chosen.every((c) => c.jpeg == null) &&
          chosen.length == existing.length) {
        return; // Today's stored selection is still the best.
      }
      final storage = LocalTestConfig.storage;
      final images = <Map<String, dynamic>>[];
      final uploaded = <Reference>[];
      for (var i = 0; i < chosen.length; i++) {
        final c = chosen[i];
        var path = c.storagePath;
        if (c.jpeg != null) {
          final name =
              '${id}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 30)}.jpg';
          final ref = storage.ref('exercise_snapshots/$uid/$day/$name');
          await ref.putData(
            c.jpeg!,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          uploaded.add(ref);
          path = ref.fullPath;
        }
        images.add({
          'path': path,
          'role': i == 0 ? 'representative' : 'closest_match',
          'repIndex': c.repIndex,
          'form': c.form,
          'pose': c.pose,
          'capturedAtMillis': c.capturedAt.millisecondsSinceEpoch,
          'sessionId': c.sessionId,
        });
      }
      try {
        await docRef.set({
          'patientId': uid,
          'doctorId': profile['doctorId'] ?? '',
          'exercise': id,
          'day': day,
          'sessionId': sessionId,
          'images': images,
          'trainingEligible': profile['researchConsent'] == true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        // Do not leave orphaned uploads behind a failed record.
        for (final ref in uploaded) {
          unawaited(ref.delete().catchError((Object _) {}));
        }
        rethrow;
      }
      final kept = {for (final c in chosen) c.storagePath};
      for (final old in existing) {
        if (old.storagePath != null && !kept.contains(old.storagePath)) {
          unawaited(
            storage.ref(old.storagePath!).delete().catchError((Object _) {}),
          );
        }
      }
    } catch (error) {
      debugPrint('Exercise snapshots were not stored: $error');
    }
  }

  static final _random = math.Random.secure();
}

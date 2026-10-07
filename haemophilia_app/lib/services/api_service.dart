import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend_config.dart';
import '../utils/exercise_utils.dart';

class ApiService {
  static const String baseUrl = BackendConfig.baseUrl;

  Future<void> requireExerciseModel(String exercise) async {
    final id = normalizeExerciseId(exercise);
    final version = switch (id) {
      kAssistedElbowFlexionV5 => 'SVM_V5_Controller_V6_Telemetry2',
      kElbowFlexionExtension => 'Elbow_LSTM_V4_22F',
      _ => null,
    };
    if (version == null) return;
    final response = await http
        .get(Uri.parse('$baseUrl/v1/exercises'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final entries = body is Map ? body['exercises'] : null;
      if (entries is List &&
          entries.any(
            (entry) =>
                entry is Map &&
                entry['id'] == id &&
                entry['model_version'] == version &&
                entry['available'] == true,
          )) {
        return;
      }
    }
    throw StateError(
      'The updated exercise model is not available yet. Please try again after the server update.',
    );
  }

  Future<Map<String, dynamic>> assessVideo({
    required Uint8List videoBytes,
    required String fileName,
    required String exercise,
  }) async {
    await requireExerciseModel(exercise);
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/v1/assessments/video'),
    );

    request.fields['exercise'] = exercise;

    request.files.add(
      http.MultipartFile.fromBytes('file', videoBytes, filename: fileName),
    );

    final streamedResponse = await request.send().timeout(
      const Duration(minutes: 2),
    );

    final responseBody = await streamedResponse.stream.bytesToString().timeout(
      const Duration(minutes: 2),
    );

    if (streamedResponse.statusCode != 200) {
      throw Exception(
        'Assessment failed (${streamedResponse.statusCode}): '
        '$responseBody',
      );
    }

    final decoded = jsonDecode(responseBody);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from assessment server.');
    }

    return decoded;
  }

  Future<Map<String, dynamic>> predictHealthScreening(
    Map<String, dynamic> features,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/v1/chatbot/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(features),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Screening failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from screening service.');
    }
    return decoded;
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

class ApiService {
  static String get baseUrl => BackendConfig.baseUrl;

  Future<Map<String, dynamic>> assessVideo({
    required Uint8List videoBytes,
    required String fileName,
    required String exercise,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/v1/assessments/video'),
    );

    request.fields['exercise'] = exercise;

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        videoBytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await request.send();

    final responseBody =
        await streamedResponse.stream.bytesToString();

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
    final response = await http.post(
      Uri.parse('$baseUrl/v1/chatbot/predict'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(features),
    );

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

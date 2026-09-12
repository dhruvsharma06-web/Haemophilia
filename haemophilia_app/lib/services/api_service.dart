import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

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
}
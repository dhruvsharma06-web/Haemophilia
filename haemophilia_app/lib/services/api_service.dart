import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_config.dart';

class ApiService {
  static const String baseUrl = BackendConfig.baseUrl;

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

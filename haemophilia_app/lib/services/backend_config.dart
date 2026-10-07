/// Supply the current tunnel at launch with --dart-define=BACKEND_URL=https://...
class BackendConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://34.173.173.123:8000',
  );

  static Uri endpoint(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');

  static Uri get liveAssessmentUri {
    final uri = endpoint('/v1/assessments/live');
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
  }

  static String get errorFrameBaseUrl =>
      endpoint('/v1/assets/error-frames/').toString();
}

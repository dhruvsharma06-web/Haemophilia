/// Supply the current tunnel at launch with --dart-define=BACKEND_URL=https://...
class BackendConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://headers-auditor-plc-eternal.trycloudflare.com',
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

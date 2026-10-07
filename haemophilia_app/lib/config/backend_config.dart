/// One backend address for HTTP, live assessment and generated frame images.
/// Override when launching: --dart-define=BACKEND_URL=http://HOST:8000
class BackendConfig {
  static const _configuredUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://lessons-family-councils-obvious.trycloudflare.com',
  );

  static String get baseUrl {
    return _configuredUrl.replaceFirst(RegExp(r'/+$'), '');
  }

  static Uri endpoint(String path) => Uri.parse('$baseUrl$path');

  static Uri liveAssessment(String exercise) {
    final uri = endpoint('/v1/assessments/live');
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'exercise': exercise},
    );
  }

  static String errorFrame(String filename) =>
      '$baseUrl/v1/assets/error-frames/${Uri.encodeComponent(filename)}';
}

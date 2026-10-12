class BackendConfig {
  /// Host IP or domain for the FastAPI backend server.
  /// Configurable at build time via `--dart-define=BACKEND_HOST=<IP>`.
  /// Defaults to the active laptop Wi-Fi IPv4 address (172.20.10.2).
  static const String host = String.fromEnvironment(
    'BACKEND_HOST',
    defaultValue: '172.20.10.2',
  );

  /// Port for the backend server.
  /// Configurable at build time via `--dart-define=BACKEND_PORT=8000`.
  static const int port = int.fromEnvironment(
    'BACKEND_PORT',
    defaultValue: 8000,
  );

  /// HTTP scheme ('http' for development, 'https' for production).
  static const String httpScheme = String.fromEnvironment(
    'BACKEND_HTTP_SCHEME',
    defaultValue: 'http',
  );

  /// WebSocket scheme ('ws' for development, 'wss' for production).
  static const String wsScheme = String.fromEnvironment(
    'BACKEND_WS_SCHEME',
    defaultValue: 'ws',
  );

  /// Base URL for REST API calls (e.g. 'http://172.20.10.2:8000').
  static String get baseUrl => '$httpScheme://$host:$port';

  /// Base URL for WebSocket connections (e.g. 'ws://172.20.10.2:8000').
  static String get baseWsUrl => '$wsScheme://$host:$port';

  /// Live assessment WebSocket URL endpoint.
  static String get liveAssessmentWsUrl => '$baseWsUrl/v1/assessments/live';

  /// Static assets error frames base URL.
  static String get errorFramesBaseUrl => '$baseUrl/v1/assets/error-frames/';

  /// Push notification dispatch endpoint.
  static String get sendNotificationUrl => '$baseUrl/v1/notifications/send';
}

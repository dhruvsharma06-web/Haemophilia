import 'package:flutter_test/flutter_test.dart';
import 'package:haemophilia_app/config/backend_config.dart';

void main() {
  test('HTTP, live camera and error images use the same configured host', () {
    final api = BackendConfig.endpoint('/v1/assessments/video');
    final live = BackendConfig.liveAssessment('Shoulder Rotation');
    final image = Uri.parse(BackendConfig.errorFrame('rep frame.jpg'));
    expect(live.host, api.host);
    expect(image.host, api.host);
    final livePort = live.hasPort ? live.port : (live.scheme == 'wss' ? 443 : 80);
    expect(livePort, api.port);
    expect(live.scheme, api.scheme == 'https' ? 'wss' : 'ws');
    expect(live.queryParameters['exercise'], 'Shoulder Rotation');
    expect(image.pathSegments.last, 'rep frame.jpg');
  });
}

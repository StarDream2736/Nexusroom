import 'package:flutter_test/flutter_test.dart';
import 'package:nexusroom/core/network/api_client.dart';
import 'package:nexusroom/core/network/api_response.dart';

void main() {
  group('ApiClient.normalizeServerUrl', () {
    test('normalizes a server origin', () {
      expect(
        ApiClient.normalizeServerUrl('  http://127.0.0.1:18080/  '),
        'http://127.0.0.1:18080',
      );
    });

    test('rejects API paths and unsupported schemes', () {
      expect(
        () => ApiClient.normalizeServerUrl('http://localhost:8080/api/v1'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => ApiClient.normalizeServerUrl('ws://localhost:8080'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

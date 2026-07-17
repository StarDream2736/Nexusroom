import 'package:flutter_test/flutter_test.dart';
import 'package:nexusroom/core/models/media_models.dart';

void main() {
  test('builds a complete RTMP publish URL', () {
    final ingress = IngressModel.fromJson({
      'id': 1,
      'ingress_id': 'ingress-1',
      'rtmp_url': 'rtmp://127.0.0.1:1935/live/',
      'stream_key': 'stream-key',
      'label': 'Desktop',
      'is_active': false,
    });

    expect(ingress.rtmpUrl, 'rtmp://127.0.0.1:1935/live');
    expect(ingress.publishUrl, 'rtmp://127.0.0.1:1935/live/stream-key');
  });

  test('rejects malformed RTMP server addresses', () {
    expect(
      () => IngressModel.fromJson({
        'id': 1,
        'ingress_id': 'ingress-1',
        'rtmp_url': 'rtmp://http://127.0.0.1:1935/live',
        'stream_key': 'stream-key',
        'label': 'Desktop',
      }),
      throwsFormatException,
    );
  });

  test('uses and validates server supplied publish URL', () {
    final ingress = IngressModel.fromJson({
      'id': 1,
      'ingress_id': 'ingress-1',
      'rtmp_url': 'rtmps://stream.example.com/live',
      'stream_key': 'stream-key',
      'publish_url': 'rtmps://stream.example.com/live/stream-key',
      'label': 'Desktop',
    });

    expect(ingress.publishUrl, 'rtmps://stream.example.com/live/stream-key');
  });
}

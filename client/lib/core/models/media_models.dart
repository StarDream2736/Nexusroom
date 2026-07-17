/// NexusRoom RTMP publishing endpoint.
class IngressModel {
  const IngressModel({
    required this.id,
    required this.ingressId,
    required this.rtmpUrl,
    required this.streamKey,
    required this.publishUrl,
    required this.label,
    required this.isActive,
  });

  final int id;
  final String ingressId;
  final String rtmpUrl;
  final String streamKey;
  final String publishUrl;
  final String label;
  final bool isActive;

  factory IngressModel.fromJson(Map<String, dynamic> json) {
    final rtmpUrl = json['rtmp_url']?.toString().trim() ?? '';
    final streamKey = json['stream_key']?.toString().trim() ?? '';
    final serverPublishUrl = json['publish_url']?.toString().trim();
    return IngressModel(
      id: (json['id'] as num).toInt(),
      ingressId: json['ingress_id'] as String,
      rtmpUrl: _validateRTMPServerUrl(rtmpUrl),
      streamKey: _validateStreamKey(streamKey),
      publishUrl: _validatePublishUrl(
        serverPublishUrl == null || serverPublishUrl.isEmpty
            ? buildPublishUrl(rtmpUrl, streamKey)
            : serverPublishUrl,
        streamKey,
      ),
      label: json['label'] as String,
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  static String buildPublishUrl(String rtmpUrl, String streamKey) {
    final base = _validateRTMPServerUrl(rtmpUrl);
    final key = _validateStreamKey(streamKey);
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/$key';
  }

  static String _validateRTMPServerUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'rtmp' && uri.scheme != 'rtmps') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.pathSegments.isEmpty ||
        uri.path.contains('//') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('推流服务器地址无效');
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static String _validateStreamKey(String value) {
    if (value.isEmpty || value.contains(RegExp(r'[\\/?#\s]'))) {
      throw const FormatException('推流密钥无效');
    }
    return value;
  }

  static String _validatePublishUrl(String value, String streamKey) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'rtmp' && uri.scheme != 'rtmps') ||
        uri.host.isEmpty ||
        uri.pathSegments.isEmpty ||
        uri.pathSegments.last != streamKey ||
        uri.path.contains('//') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('完整推流地址无效');
    }
    return uri.toString();
  }
}

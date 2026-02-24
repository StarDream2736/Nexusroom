/// LiveKit Token 响应
class LiveKitTokenResult {
  const LiveKitTokenResult({
    required this.token,
    required this.url,
    required this.roomName,
  });

  final String token;
  final String url;
  final String roomName;

  factory LiveKitTokenResult.fromJson(Map<String, dynamic> json) {
    return LiveKitTokenResult(
      token: json['token'] as String,
      url: json['url'] as String,
      roomName: json['room_name'] as String,
    );
  }
}

/// Ingress 推流入口模型
class IngressModel {
  const IngressModel({
    required this.id,
    required this.ingressId,
    required this.rtmpUrl,
    required this.streamKey,
    required this.label,
    required this.isActive,
  });

  final int id;
  final String ingressId;
  final String rtmpUrl;
  final String streamKey;
  final String label;
  final bool isActive;

  factory IngressModel.fromJson(Map<String, dynamic> json) {
    return IngressModel(
      id: (json['id'] as num).toInt(),
      ingressId: json['ingress_id'] as String,
      rtmpUrl: json['rtmp_url'] as String,
      streamKey: json['stream_key'] as String,
      label: json['label'] as String,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

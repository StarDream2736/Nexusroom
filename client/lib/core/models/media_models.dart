/// NexusRoom RTMP publishing endpoint.
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
      isActive: json['is_active'] as bool? ?? false,
    );
  }
}

class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.name,
    required this.inviteCode,
  });

  final int id;
  final String name;
  final String inviteCode;

  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    return RoomSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
    );
  }
}

class RoomMember {
  const RoomMember({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.role,
  });

  final int userId;
  final String nickname;
  final String? avatarUrl;
  final String role;

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      userId: (json['user_id'] as num).toInt(),
      nickname: json['nickname'] as String,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String,
    );
  }
}

class RoomDetail {
  const RoomDetail({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.livekitRoomName,
    required this.members,
    required this.ingresses,
    this.liveKitUrl = '',
  });

  final int id;
  final String name;
  final String inviteCode;
  final int ownerId;
  final String livekitRoomName;
  final List<RoomMember> members;
  final List<RoomIngressSummary> ingresses;
  final String liveKitUrl;

  factory RoomDetail.fromJson(Map<String, dynamic> json) {
    final membersJson = (json['members'] as List<dynamic>? ?? []);
    final ingressJson = (json['ingresses'] as List<dynamic>? ?? []);
    return RoomDetail(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      ownerId: (json['owner_id'] as num?)?.toInt() ?? 0,
      livekitRoomName: json['livekit_room_name'] as String? ?? '',
      members: membersJson
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList(),
      ingresses: ingressJson
          .map((item) =>
              RoomIngressSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      liveKitUrl: json['livekit_url'] as String? ?? '',
    );
  }
}

/// 房间中 Ingress 推流入口摘要
class RoomIngressSummary {
  const RoomIngressSummary({
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

  factory RoomIngressSummary.fromJson(Map<String, dynamic> json) {
    return RoomIngressSummary(
      id: (json['id'] as num).toInt(),
      ingressId: json['ingress_id'] as String,
      rtmpUrl: json['rtmp_url'] as String,
      streamKey: json['stream_key'] as String,
      label: json['label'] as String,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

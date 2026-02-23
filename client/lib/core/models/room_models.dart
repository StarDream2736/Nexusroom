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
    required this.members,
  });

  final int id;
  final String name;
  final String inviteCode;
  final List<RoomMember> members;

  factory RoomDetail.fromJson(Map<String, dynamic> json) {
    final membersJson = (json['members'] as List<dynamic>? ?? []);
    return RoomDetail(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      members: membersJson
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

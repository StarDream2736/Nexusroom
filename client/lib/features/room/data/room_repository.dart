import '../../../core/models/room_models.dart';
import '../../../core/models/livekit_models.dart';
import '../../../core/network/api_client.dart';

class RoomRepository {
  RoomRepository(this._client);

  final ApiClient _client;

  Future<List<RoomSummary>> listRooms() async {
    final data = await _client.getData('/api/v1/rooms');
    final list = (data as List<dynamic>);
    return list
        .map((item) => RoomSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<RoomSummary> createRoom(String name) async {
    final data = await _client.postData('/api/v1/rooms', body: {
      'name': name,
    });
    return RoomSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomSummary> joinRoom(String inviteCode) async {
    final data = await _client.postData('/api/v1/rooms/join', body: {
      'invite_code': inviteCode,
    });
    return RoomSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<RoomDetail> getRoomDetail(int roomId) async {
    final data = await _client.getData('/api/v1/rooms/$roomId');
    return RoomDetail.fromJson(data as Map<String, dynamic>);
  }

  Future<void> updateRoom(int roomId, String name) async {
    await _client.patchData('/api/v1/rooms/$roomId', body: {
      'name': name,
    });
  }

  /// 获取 LiveKit Token（语音房间）
  Future<LiveKitTokenResult> getLiveKitToken(int roomId) async {
    final data =
        await _client.postData('/api/v1/rooms/$roomId/livekit-token');
    return LiveKitTokenResult.fromJson(data as Map<String, dynamic>);
  }

  /// 获取 LiveKit Token（直播房间，按 Ingress 隔离）
  Future<LiveKitTokenResult> getStreamToken(int roomId, {required int ingressId}) async {
    final data = await _client
        .postData('/api/v1/rooms/$roomId/livekit-token?type=stream&ingress_id=$ingressId');
    return LiveKitTokenResult.fromJson(data as Map<String, dynamic>);
  }

  /// 获取 Ingress 列表
  Future<List<IngressModel>> listIngresses(int roomId) async {
    final data = await _client.getData('/api/v1/rooms/$roomId/ingresses');
    final list = (data as List<dynamic>);
    return list
        .map((item) => IngressModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// 创建 Ingress
  Future<IngressModel> createIngress(int roomId, String label) async {
    final data =
        await _client.postData('/api/v1/rooms/$roomId/ingresses', body: {
      'label': label,
    });
    return IngressModel.fromJson(data as Map<String, dynamic>);
  }

  /// 删除 Ingress
  Future<void> deleteIngress(int roomId, int ingressId) async {
    await _client.deleteData('/api/v1/rooms/$roomId/ingresses/$ingressId');
  }

  /// 退出房间（非房主）
  Future<void> leaveRoom(int roomId) async {
    await _client.deleteData('/api/v1/rooms/$roomId/leave');
  }

  /// 获取房间在线用户 ID 列表
  Future<Set<int>> getOnlineUsers(int roomId) async {
    final data = await _client.getData('/api/v1/rooms/$roomId/online-users');
    final map = data as Map<String, dynamic>;
    final list = (map['online_user_ids'] as List<dynamic>?) ?? [];
    return list.map((e) => (e as num).toInt()).toSet();
  }

  /// 解散房间（房主或超管）
  Future<void> deleteRoom(int roomId) async {
    await _client.deleteData('/api/v1/rooms/$roomId');
  }
}

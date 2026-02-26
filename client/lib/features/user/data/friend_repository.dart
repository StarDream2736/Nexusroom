import '../../../core/network/api_client.dart';

class FriendRepository {
  FriendRepository(this._client);

  final ApiClient _client;

  /// 获取好友列表
  Future<List<Map<String, dynamic>>> listFriends() async {
    final data = await _client.getData('/api/v1/friends');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// 获取待处理好友申请
  Future<List<Map<String, dynamic>>> listPendingRequests() async {
    final data = await _client.getData('/api/v1/friends/pending');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// 发送好友申请（通过 display_id）
  Future<void> sendRequest(String displayId) async {
    await _client.postData('/api/v1/friends/request', body: {
      'display_id': displayId,
    });
  }

  /// 处理好友申请（accept / reject）
  Future<void> handleRequest(int requesterId, String action) async {
    await _client.patchData('/api/v1/friends/request/$requesterId', body: {
      'action': action,
    });
  }
}

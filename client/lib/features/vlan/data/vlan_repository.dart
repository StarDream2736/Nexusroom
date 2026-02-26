import '../../../core/network/api_client.dart';

class VlanRepository {
  VlanRepository(this._client);

  final ApiClient _client;

  /// 加入 VLAN
  Future<Map<String, dynamic>> join(String roomId, String publicKey) async {
    final data = await _client.postData(
      '/api/v1/rooms/$roomId/vlan/join',
      body: {'public_key': publicKey},
    );
    return data as Map<String, dynamic>;
  }

  /// 离开 VLAN
  Future<void> leave(String roomId) async {
    await _client.deleteData('/api/v1/rooms/$roomId/vlan/leave');
  }

  /// 获取 VLAN Peers
  Future<List<Map<String, dynamic>>> getPeers(String roomId) async {
    final data = await _client.getData('/api/v1/rooms/$roomId/vlan/peers');
    return (data as List).cast<Map<String, dynamic>>();
  }
}

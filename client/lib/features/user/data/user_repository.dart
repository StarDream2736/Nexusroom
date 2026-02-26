import '../../../core/network/api_client.dart';

class UserRepository {
  UserRepository(this._client);

  final ApiClient _client;

  /// 获取当前用户信息
  Future<Map<String, dynamic>> getMe() async {
    final data = await _client.getData('/api/v1/users/me');
    return data as Map<String, dynamic>;
  }

  /// 修改昵称/头像
  Future<void> updateProfile({String? nickname, String? avatarUrl}) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;
    await _client.patchData('/api/v1/users/me', body: body);
  }

  /// 按 display_id 搜索用户
  Future<Map<String, dynamic>?> searchByDisplayID(String displayId) async {
    final data = await _client.getData(
      '/api/v1/users/search',
      queryParameters: {'display_id': displayId},
    );
    if (data == null) return null;
    return data as Map<String, dynamic>;
  }
}

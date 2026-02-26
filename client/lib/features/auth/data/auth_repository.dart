import '../../../core/models/auth_models.dart';
import '../../../core/network/api_client.dart';

class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<AuthResult> login(String username, String password) async {
    final data = await _client.postData('/api/v1/auth/login', body: {
      'username': username,
      'password': password,
    });
    return AuthResult.fromJson(data as Map<String, dynamic>);
  }

  Future<AuthResult> register({
    required String username,
    required String password,
    required String nickname,
    String? adminToken,
  }) async {
    final data = await _client.postData('/api/v1/auth/register', body: {
      'username': username,
      'password': password,
      'nickname': nickname,
      'admin_token': adminToken ?? '',
    });
    return AuthResult.fromJson(data as Map<String, dynamic>);
  }
}

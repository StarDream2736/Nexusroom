import '../db/daos/settings_dao.dart';

class SettingsRepository {
  SettingsRepository(this._dao);

  final SettingsDao _dao;

  static const _serverUrlKey = 'server_url';
  static const _tokenKey = 'token';
  static const _userIdKey = 'user_id';
  static const _userDisplayIdKey = 'user_display_id';
  static const _usernameKey = 'username';
  static const _nicknameKey = 'nickname';

  Future<String?> getServerUrl() => _dao.getValue(_serverUrlKey);
  Future<String?> getToken() => _dao.getValue(_tokenKey);
  Future<String?> getUserId() => _dao.getValue(_userIdKey);
  Future<String?> getUserDisplayId() => _dao.getValue(_userDisplayIdKey);
  Future<String?> getUsername() => _dao.getValue(_usernameKey);
  Future<String?> getNickname() => _dao.getValue(_nicknameKey);

  Future<void> setServerUrl(String value) => _dao.setValue(_serverUrlKey, value);
  Future<void> setToken(String value) => _dao.setValue(_tokenKey, value);
  Future<void> setUserId(String value) => _dao.setValue(_userIdKey, value);
  Future<void> setUserDisplayId(String value) =>
      _dao.setValue(_userDisplayIdKey, value);
  Future<void> setUsername(String value) => _dao.setValue(_usernameKey, value);
  Future<void> setNickname(String value) => _dao.setValue(_nicknameKey, value);

  Future<void> clearAuth() async {
    await _dao.remove(_tokenKey);
    await _dao.remove(_userIdKey);
    await _dao.remove(_userDisplayIdKey);
    await _dao.remove(_usernameKey);
    await _dao.remove(_nicknameKey);
  }

  /// 清除所有设置（包括服务器地址），用于“更换服务器”
  Future<void> clearAll() async {
    await clearAuth();
    await _dao.remove(_serverUrlKey);
  }
}

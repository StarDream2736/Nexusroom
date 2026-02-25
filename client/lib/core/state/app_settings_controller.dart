import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/auth_models.dart';
import '../repositories/settings_repository.dart';

class AppSettingsController extends StateNotifier<AsyncValue<AppSettings>> {
  AppSettingsController(this._repository)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    try {
      final serverUrl = await _repository.getServerUrl();
      final token = await _repository.getToken();
      final userId = await _repository.getUserId();
      final userDisplayId = await _repository.getUserDisplayId();
      final username = await _repository.getUsername();
      final nickname = await _repository.getNickname();
      final avatarUrl = await _repository.getAvatarUrl();
      final audioInputDeviceId = await _repository.getAudioInputDeviceId();
      final audioOutputDeviceId = await _repository.getAudioOutputDeviceId();
      state = AsyncValue.data(AppSettings(
        serverUrl: serverUrl,
        token: token,
        userId: userId == null ? null : int.tryParse(userId),
        userDisplayId: userDisplayId,
        username: username,
        nickname: nickname,
        avatarUrl: avatarUrl,
        audioInputDeviceId: audioInputDeviceId,
        audioOutputDeviceId: audioOutputDeviceId,
      ));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> setServerUrl(String serverUrl) async {
    final current = state.value?.serverUrl;
    await _repository.setServerUrl(serverUrl);
    if (current != null && current != serverUrl) {
      await _repository.clearAuth();
    }
    await _load();
  }

  Future<void> setAuth(AuthResult result) async {
    await _repository.setToken(result.token);
    await _repository.setUserId(result.userId.toString());
    await _repository.setUserDisplayId(result.userDisplayId);
    await _load();
  }

  /// 更新头像 URL并重新加载设置
  Future<void> setAvatarUrl(String url) async {
    await _repository.setAvatarUrl(url);
    await _load();
  }

  /// 更新昵称并重新加载设置
  Future<void> setNickname(String nickname) async {
    await _repository.setNickname(nickname);
    await _load();
  }

  /// 保存麦克风设备选择
  Future<void> setAudioInputDeviceId(String deviceId) async {
    await _repository.setAudioInputDeviceId(deviceId);
    await _load();
  }

  /// 保存扬声器设备选择
  Future<void> setAudioOutputDeviceId(String deviceId) async {
    await _repository.setAudioOutputDeviceId(deviceId);
    await _load();
  }

  Future<void> clearAuth() async {
    await _repository.clearAuth();
    await _load();
  }

  /// 清除所有设置（包含服务器地址），用于“更换服务器”
  Future<void> clearAll() async {
    await _repository.clearAll();
    await _load();
  }
}

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
      state = AsyncValue.data(AppSettings(
        serverUrl: serverUrl,
        token: token,
        userId: userId == null ? null : int.tryParse(userId),
        userDisplayId: userDisplayId,
        username: username,
        nickname: nickname,
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

  Future<void> clearAuth() async {
    await _repository.clearAuth();
    await _load();
  }
}

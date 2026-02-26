import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/auth_models.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../user/data/user_repository.dart';
import '../../data/auth_repository.dart';
import '../../../../core/state/app_settings_controller.dart';

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(appSettingsProvider.notifier),
    ref.watch(userRepositoryProvider),
  );
});

class AuthController {
  AuthController(this._repository, this._settingsController, this._userRepo);

  final AuthRepository _repository;
  final AppSettingsController _settingsController;
  final UserRepository _userRepo;

  /// 登录/注册 后同步用户资料（昵称、头像）到本地
  Future<void> _syncProfile() async {
    try {
      final me = await _userRepo.getMe();
      final nickname = me['nickname'] as String?;
      final avatarUrl = me['avatar_url'] as String?;
      // 批量写入，只触发一次 _load()，避免 WS 重连风暴
      await _settingsController.setProfile(
        nickname: nickname,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      debugPrint('[AuthController] _syncProfile failed: $e');
    }
  }

  Future<AuthResult> login(String username, String password) async {
    final result = await _repository.login(username, password);
    await _settingsController.setAuth(result);
    await _syncProfile();
    return result;
  }

  Future<AuthResult> register({
    required String username,
    required String password,
    required String nickname,
    String? adminToken,
  }) async {
    final result = await _repository.register(
      username: username,
      password: password,
      nickname: nickname,
      adminToken: adminToken,
    );
    await _settingsController.setAuth(result);
    await _syncProfile();
    return result;
  }
}

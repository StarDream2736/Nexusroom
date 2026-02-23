import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/auth_models.dart';
import '../../../../core/providers/app_providers.dart';
import '../../data/auth_repository.dart';
import '../../../../core/state/app_settings_controller.dart';

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(appSettingsProvider.notifier),
  );
});

class AuthController {
  AuthController(this._repository, this._settingsController);

  final AuthRepository _repository;
  final AppSettingsController _settingsController;

  Future<AuthResult> login(String username, String password) async {
    final result = await _repository.login(username, password);
    await _settingsController.setAuth(result);
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
    return result;
  }
}

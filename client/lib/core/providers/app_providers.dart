import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/app_settings.dart';
import '../network/api_client.dart';
import '../network/livekit_service.dart';
import '../network/ws_service.dart';
import '../native/wireguard_service.dart';
import '../repositories/settings_repository.dart';
import '../repositories/file_repository.dart';
import '../state/app_settings_controller.dart';
import '../window/window_lifecycle_service.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/room/data/message_repository.dart';
import '../../features/room/data/room_repository.dart';
import '../../features/user/data/user_repository.dart';
import '../../features/user/data/friend_repository.dart';
import '../../features/vlan/data/vlan_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(appDatabaseProvider).settingsDao);
});

final appSettingsProvider =
  StateNotifierProvider<AppSettingsController, AsyncValue<AppSettings>>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return AppSettingsController(repo);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  final settings = ref.read(appSettingsProvider).valueOrNull;
  client.updateConfig(baseUrl: settings?.serverUrl, token: settings?.token);
  ref.listen(appSettingsProvider, (_, next) {
    final settings = next.valueOrNull;
    client.updateConfig(baseUrl: settings?.serverUrl, token: settings?.token);
  });
  return client;
});

final wsServiceProvider = Provider<WsService>((ref) {
  debugPrint('[wsServiceProvider] factory START');
  final service = WsService(db: ref.watch(appDatabaseProvider));

  // 尝试立即连接（应用重启时 settings 可能已加载完成）
  final settingsState = ref.read(appSettingsProvider);
  debugPrint('[wsServiceProvider] appSettings state: ${settingsState.runtimeType} — loading=${settingsState is AsyncLoading} data=${settingsState.valueOrNull != null}');
  final settings = settingsState.valueOrNull;
  if (settings != null && settings.hasServerUrl && settings.hasToken) {
    debugPrint('[wsServiceProvider] connecting immediately with url=${settings.serverUrl}');
    service.connect(settings.serverUrl!, settings.token!);
  } else {
    debugPrint('[wsServiceProvider] settings not ready, waiting for listen callback');
  }

  // 监听 settings 变化：覆盖 loading→data（重启）和 data→data（登录/切换服务器）
  ref.listen<AsyncValue<AppSettings>>(appSettingsProvider, (prev, next) {
    debugPrint('[wsServiceProvider] listen callback: prev=${prev?.runtimeType} next=${next.runtimeType} hasValue=${next.valueOrNull != null}');
    final s = next.valueOrNull;
    if (s == null || !s.hasServerUrl || !s.hasToken) {
      debugPrint('[wsServiceProvider] settings incomplete, disconnecting');
      service.disconnect();
      return;
    }
    debugPrint('[wsServiceProvider] settings ready, calling connect serverUrl=${s.serverUrl}');
    service.connect(s.serverUrl!, s.token!);
  });

  ref.onDispose(service.dispose);
  debugPrint('[wsServiceProvider] factory END');
  return service;
});

final livekitServiceProvider = Provider<LiveKitService>((ref) {
  final service = LiveKitService();
  ref.onDispose(service.dispose);
  return service;
});

final windowLifecycleServiceProvider =
    Provider<WindowLifecycleService>((ref) {
  final livekitService = ref.watch(livekitServiceProvider);
  final service = WindowLifecycleService(livekitService);
  ref.onDispose(service.dispose);
  return service;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository(ref.watch(apiClientProvider));
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(
    ref.watch(apiClientProvider),
    ref.watch(appDatabaseProvider).messagesDao,
  );
});

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  return FileRepository(ref.watch(apiClientProvider));
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(apiClientProvider));
});

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepository(ref.watch(apiClientProvider));
});

final vlanRepositoryProvider = Provider<VlanRepository>((ref) {
  return VlanRepository(ref.watch(apiClientProvider));
});

final wireguardServiceProvider = Provider<WireGuardService>((ref) {
  final service = WireGuardService();
  ref.onDispose(service.dispose);
  return service;
});

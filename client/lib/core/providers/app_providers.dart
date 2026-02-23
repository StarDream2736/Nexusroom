import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/app_settings.dart';
import '../network/api_client.dart';
import '../network/ws_service.dart';
import '../repositories/settings_repository.dart';
import '../repositories/file_repository.dart';
import '../state/app_settings_controller.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/room/data/message_repository.dart';
import '../../features/room/data/room_repository.dart';

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
  final service = WsService(db: ref.watch(appDatabaseProvider));
  final settings = ref.read(appSettingsProvider).valueOrNull;
  if (settings != null && settings.hasServerUrl && settings.hasToken) {
    service.connect(settings.serverUrl!, settings.token!);
  }
  ref.listen(appSettingsProvider, (_, next) {
    final settings = next.valueOrNull;
    if (settings == null || !settings.hasServerUrl || !settings.hasToken) {
      service.disconnect();
      return;
    }
    service.connect(settings.serverUrl!, settings.token!);
  });
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

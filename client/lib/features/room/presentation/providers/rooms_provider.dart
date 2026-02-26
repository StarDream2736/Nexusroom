import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/room_models.dart';

final roomsProvider = FutureProvider<List<RoomSummary>>((ref) async {
  // 监听 auth 状态，切换账号时自动重新拉取
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  if (settings == null || !settings.hasToken) return [];
  return ref.watch(roomRepositoryProvider).listRooms();
});

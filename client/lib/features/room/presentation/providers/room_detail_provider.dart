import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/room_models.dart';
import '../../../../core/providers/app_providers.dart';

final roomDetailProvider = FutureProvider.family<RoomDetail, int>((ref, roomId) async {
  final detail = await ref.watch(roomRepositoryProvider).getRoomDetail(roomId);
  // 每3秒自动刷新一次成员信息，保证实时性
  final timer = Timer(const Duration(seconds: 3), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  return detail;
});

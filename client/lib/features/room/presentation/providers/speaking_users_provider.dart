import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';

/// 当前正在说话的用户 ID 集合（基于 LiveKit ActiveSpeakers 检测）
final speakingUsersProvider = StreamProvider<Set<int>>((ref) {
  final lk = ref.watch(livekitServiceProvider);
  return lk.speakingUsersStream;
});

/// 当前房间 ID（由 RightPanel / RoomDetailPage 设置）
final activeRoomIdProvider = StateProvider<int?>((ref) => null);

/// 当前房间在线用户 ID 集合（基于 WS 事件 + REST API fallback）
final onlineUsersProvider = StreamProvider<Set<int>>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  if (roomId == null) return const Stream.empty();

  final ws = ref.watch(wsServiceProvider);
  final roomRepo = ref.watch(roomRepositoryProvider);

  final controller = StreamController<Set<int>>();
  final onlineSet = <int>{};

  // 初始化：从 REST API 获取在线用户列表
  roomRepo.getOnlineUsers(roomId).then((users) {
    onlineSet
      ..clear()
      ..addAll(users);
    if (!controller.isClosed) controller.add(Set.from(onlineSet));
  }).catchError((e) {
    debugPrint('[onlineUsersProvider] REST API failed: $e');
  });

  // 监听 WS member_join 事件
  final joinSub = ws.on('room.member_join').listen((payload) {
    final userId = payload['user_id'] as int?;
    if (userId != null) {
      onlineSet.add(userId);
      if (!controller.isClosed) controller.add(Set.from(onlineSet));
    }
  });

  // 监听 WS member_leave 事件
  final leaveSub = ws.on('room.member_leave').listen((payload) {
    final userId = payload['user_id'] as int?;
    if (userId != null) {
      onlineSet.remove(userId);
      if (!controller.isClosed) controller.add(Set.from(onlineSet));
    }
  });

  // 定期刷新（10 秒）作为 fallback
  final timer = Timer.periodic(const Duration(seconds: 10), (_) {
    roomRepo.getOnlineUsers(roomId).then((users) {
      onlineSet
        ..clear()
        ..addAll(users);
      if (!controller.isClosed) controller.add(Set.from(onlineSet));
    }).catchError((e) {
      debugPrint('[onlineUsersProvider] periodic refresh failed: $e');
    });
  });

  ref.onDispose(() {
    joinSub.cancel();
    leaveSub.cancel();
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

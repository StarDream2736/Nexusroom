import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/rtc_service.dart';
import '../../../../core/network/ws_service.dart';
import '../../../../core/providers/app_providers.dart';

/// Speaking users scoped to one room. A new room always starts empty so state
/// from the previous RTC session cannot leak into its member list.
final speakingUsersProvider =
    StreamProvider.family<Set<int>, int>((ref, roomId) {
  final rtc = ref.watch(rtcServiceProvider);
  final controller = StreamController<Set<int>>();

  void publishCurrent() {
    if (controller.isClosed) return;
    controller.add(
      rtc.connectedRoomId == roomId ? rtc.currentSpeakers : const <int>{},
    );
  }

  publishCurrent();
  final speakingSub = rtc.speakingUsersStream.listen((users) {
    if (!controller.isClosed) {
      controller.add(rtc.connectedRoomId == roomId ? users : const <int>{});
    }
  });
  final connectionSub = rtc.connectionStateStream.listen((state) {
    if (state != RtcConnectionState.connected ||
        rtc.connectedRoomId != roomId) {
      if (!controller.isClosed) controller.add(const <int>{});
    }
  });

  ref.onDispose(() async {
    await speakingSub.cancel();
    await connectionSub.cancel();
    await controller.close();
  });
  return controller.stream;
});

/// Online users scoped to one room. WebSocket events update immediately while
/// REST refreshes repair any missed event without overwriting newer changes.
final onlineUsersProvider = StreamProvider.family<Set<int>, int>((ref, roomId) {
  final ws = ref.watch(wsServiceProvider);
  final roomRepo = ref.watch(roomRepositoryProvider);
  final controller = StreamController<Set<int>>();
  final online = <int>{};
  var revision = 0;

  void publish() {
    if (!controller.isClosed) controller.add(Set.unmodifiable(online));
  }

  Future<void> refresh() async {
    final startedAtRevision = revision;
    try {
      final users = await roomRepo.getOnlineUsers(roomId);
      if (controller.isClosed || startedAtRevision != revision) return;
      online
        ..clear()
        ..addAll(users);
      publish();
    } catch (error) {
      debugPrint('[onlineUsersProvider] refresh failed: $error');
    }
  }

  void setOnline(int userId, bool value) {
    revision++;
    if (value) {
      online.add(userId);
    } else {
      online.remove(userId);
    }
    publish();
  }

  publish();
  unawaited(refresh());

  final joinedSub = ws.on('room.joined').listen((payload) {
    if ((payload['room_id'] as num?)?.toInt() != roomId) return;
    final userId = ref.read(appSettingsProvider).valueOrNull?.userId;
    if (userId != null) setOnline(userId, true);
    unawaited(refresh());
  });
  final joinSub = ws.on('room.member_join').listen((payload) {
    if ((payload['room_id'] as num?)?.toInt() != roomId) return;
    final userId = (payload['user_id'] as num?)?.toInt();
    if (userId != null) setOnline(userId, true);
  });
  final leaveSub = ws.on('room.member_leave').listen((payload) {
    if ((payload['room_id'] as num?)?.toInt() != roomId) return;
    final userId = (payload['user_id'] as num?)?.toInt();
    if (userId != null) setOnline(userId, false);
  });
  final stateSub = ws.stateStream.listen((state) {
    revision++;
    if (state == WsConnectionState.connected) {
      unawaited(refresh());
    } else if (state == WsConnectionState.disconnected) {
      online.clear();
      publish();
    }
  });
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    if (ws.connectionState == WsConnectionState.connected) {
      unawaited(refresh());
    }
  });

  ref.onDispose(() async {
    timer.cancel();
    await joinedSub.cancel();
    await joinSub.cancel();
    await leaveSub.cancel();
    await stateSub.cancel();
    await controller.close();
  });
  return controller.stream;
});

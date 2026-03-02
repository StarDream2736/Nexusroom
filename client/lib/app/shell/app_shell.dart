import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../features/room/presentation/providers/rooms_provider.dart';
import '../../features/room/presentation/providers/speaking_users_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/title_bar.dart';
import 'sidebar.dart';
import 'right_panel.dart';

/// The top-level shell for all authenticated routes.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  /// Current matched route location, passed from ShellRoute builder.
  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  String? _currentRoomId;
  StreamSubscription? _disbandedSub;
  StreamSubscription? _kickedSub;

  @override
  void initState() {
    super.initState();
    // 提前触发 WsService 创建，确保 WS 在进入 Shell 时就尝试连接
    // 不要等到用户进入房间才首次读取
    final ws = ref.read(wsServiceProvider);
    _syncRoom(widget.location);

    // 全局监听 room.disbanded 事件
    _disbandedSub = ws.on('room.disbanded').listen((payload) {
      final disbandedRoomId = payload['room_id'];
      debugPrint('[AppShell] room.disbanded roomId=$disbandedRoomId');
      // 刷新房间列表
      ref.invalidate(roomsProvider);
      // 如果当前正在该房间中，导航回首页
      if (_currentRoomId != null && disbandedRoomId.toString() == _currentRoomId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('房间已被解散')),
          );
          context.go('/home');
        }
      }
    });

    // 全局监听 room.kicked 事件
    _kickedSub = ws.on('room.kicked').listen((payload) {
      debugPrint('[AppShell] room.kicked');
      ref.invalidate(roomsProvider);
      if (_currentRoomId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('你已被移出房间: ${payload['reason'] ?? ''}')),
        );
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _disbandedSub?.cancel();
    _kickedSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _syncRoom(widget.location);
    }
  }

  void _syncRoom(String location) {
    final roomId = _extractRoomId(location);
    debugPrint('[AppShell] location=$location  roomId=$roomId  prev=$_currentRoomId');
    if (roomId != _currentRoomId) {
      final oldRoomId = _currentRoomId;
      _currentRoomId = roomId;

      // 离开旧房间时立即发起 LiveKit 断开（fire-and-forget）
      // disconnect() 是并发安全的：立即清除字段，异步释放旧 Room 对象
      // 新页面的 connect() 会 await _pendingDisconnect，不会竞态
      if (oldRoomId != null) {
        debugPrint('[AppShell] disconnecting LiveKit (leaving room $oldRoomId)');
        ref.read(livekitServiceProvider).disconnect();

        // 同时断开 VLAN 隧道 + 通知服务器移除 peer
        final wgService = ref.read(wireguardServiceProvider);
        if (wgService.isConnected) {
          debugPrint('[AppShell] disconnecting VLAN (leaving room $oldRoomId)');
          wgService.stopTunnel();
          // 通知服务器移除 peer，避免其他客户端仍显示该用户在 VLAN 中
          try {
            ref.read(vlanRepositoryProvider).leave(oldRoomId);
          } catch (e) {
            debugPrint('[AppShell] VLAN leave API failed: $e');
          }
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ws = ref.read(wsServiceProvider);
        if (oldRoomId != null) {
          debugPrint('[AppShell] leaveRoom($oldRoomId)');
          ws.leaveRoom(int.parse(oldRoomId));
        }
        if (roomId != null) {
          debugPrint('[AppShell] joinRoom($roomId)');
          ws.joinRoom(int.parse(roomId));
        }
        // 更新 activeRoomIdProvider 以驱动 onlineUsersProvider
        ref.read(activeRoomIdProvider.notifier).state =
            roomId != null ? int.tryParse(roomId) : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final roomId = _extractRoomId(location);
    final showRightPanel = roomId != null && !location.endsWith('/settings');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const TitleBar(title: 'NexusRoom'),
          Expanded(
            child: Row(
              children: [
                const Sidebar(),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(location),
                    child: widget.child,
                  ),
                ),
                if (showRightPanel)
                  AnimatedContainer(
                    duration: AppTheme.durationPage,
                    curve: AppTheme.curveMovement,
                    child: KeyedSubtree(
                      key: ValueKey('right_$roomId'),
                      child: RightPanel(roomId: roomId!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _extractRoomId(String location) {
    final match = RegExp(r'^/rooms/(\d+)').firstMatch(location);
    return match?.group(1);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../features/room/presentation/providers/rooms_provider.dart';
import '../../features/room/presentation/providers/speaking_users_provider.dart';
import '../../features/user/data/user_repository.dart';
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
    // 每次进入 Shell 同步用户资料（昵称、头像）
    _syncUserProfile();

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ws = ref.read(wsServiceProvider);
        if (oldRoomId != null) {
          debugPrint('[AppShell] leaveRoom($oldRoomId)');
          ws.leaveRoom(int.parse(oldRoomId));
          // 注意：不在这里 disconnect LiveKit，而是由新房间页面的
          // connect() 内部先 disconnect 再 connect，避免竞态
        }
        if (roomId != null) {
          debugPrint('[AppShell] joinRoom($roomId)');
          ws.joinRoom(int.parse(roomId));
        } else {
          // 离开房间且没有进入新房间，断开 LiveKit
          ref.read(livekitServiceProvider).disconnect();
        }
        // 更新 activeRoomIdProvider 以驱动 onlineUsersProvider
        ref.read(activeRoomIdProvider.notifier).state =
            roomId != null ? int.tryParse(roomId) : null;
      });
    }
  }

  /// 同步用户资料（昵称、头像）到本地
  Future<void> _syncUserProfile() async {
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final me = await userRepo.getMe();
      final settings = ref.read(appSettingsProvider.notifier);
      final nickname = me['nickname'] as String?;
      final avatarUrl = me['avatar_url'] as String?;
      if (nickname != null && nickname.isNotEmpty) {
        await settings.setNickname(nickname);
      }
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        await settings.setAvatarUrl(avatarUrl);
      }
    } catch (e) {
      debugPrint('[AppShell] _syncUserProfile failed: $e');
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
                    child: RightPanel(roomId: roomId),
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
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

  @override
  void initState() {
    super.initState();
    // 提前触发 WsService 创建，确保 WS 在进入 Shell 时就尝试连接
    // 不要等到用户进入房间才首次读取
    ref.read(wsServiceProvider);
    _syncRoom(widget.location);
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
        }
        if (roomId != null) {
          debugPrint('[AppShell] joinRoom($roomId)');
          ws.joinRoom(int.parse(roomId));
        }
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

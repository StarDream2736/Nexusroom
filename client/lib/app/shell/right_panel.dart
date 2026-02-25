import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../features/room/presentation/providers/room_detail_provider.dart';
import '../../features/room/presentation/providers/room_stream_provider.dart';
import '../../features/room/presentation/providers/speaking_users_provider.dart';
import '../../features/vlan/presentation/widgets/vlan_panel.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/app_theme.dart';

/// Right panel (200px) — shown only when a room is active.
///
/// Contents:
///   - Online member list (with breathing voice indicator)
///   - Stream list (ingresses)
///   - VLAN panel
class RightPanel extends ConsumerWidget {
  const RightPanel({super.key, required this.roomId});

  final String roomId;

  int get _roomIdInt => int.parse(roomId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomAsync = ref.watch(roomDetailProvider(_roomIdInt));
    final baseUrl = ref.watch(appSettingsProvider).value?.serverUrl;
    final ingressesAsync = ref.watch(roomIngressesProvider(_roomIdInt));
    final selectedIngress = ref.watch(selectedIngressProvider);
    final speakingUsers = ref.watch(speakingUsersProvider).valueOrNull ?? {};
    final onlineUsers = ref.watch(onlineUsersProvider).valueOrNull ?? {};
    // 当前用户自己也算在线
    final myUserId = ref.watch(appSettingsProvider).valueOrNull?.userId;

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppColors.sidebar.withOpacity(0.6),
        border: Border(
          left: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Member header ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: roomAsync.when(
              data: (room) {
                final totalCount = room.members.length;
                final onlineCount = room.members.where((m) =>
                    onlineUsers.contains(m.userId) || m.userId == myUserId).length;
                return Row(
                  children: [
                    Text('成员列表', style: AppTypography.sectionHeader),
                    const Spacer(),
                    Text(
                      '$onlineCount/$totalCount',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
              loading: () => Text('成员列表', style: AppTypography.sectionHeader),
              error: (_, __) => Text('成员列表', style: AppTypography.sectionHeader),
            ),
          ),

          // ─── Member list ───────────────────────────────
          Expanded(
            child: roomAsync.when(
              data: (room) {
                if (room.members.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('暂无成员',
                        style: AppTypography.bodySecondary),
                  );
                }
                // 按在线状态排序：在线成员在前，离线在后
                final sorted = [...room.members];
                sorted.sort((a, b) {
                  final aOnline = onlineUsers.contains(a.userId) || a.userId == myUserId;
                  final bOnline = onlineUsers.contains(b.userId) || b.userId == myUserId;
                  if (aOnline && !bOnline) return -1;
                  if (!aOnline && bOnline) return 1;
                  // 同组内按 owner 优先
                  if (a.role == 'owner' && b.role != 'owner') return -1;
                  if (a.role != 'owner' && b.role == 'owner') return 1;
                  return 0;
                });
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  physics: const BouncingScrollPhysics(),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final member = sorted[index];
                    final avatarUrl = _resolveUrl(baseUrl, member.avatarUrl);
                    final isOnline = onlineUsers.contains(member.userId) || member.userId == myUserId;
                    final isSpeaking = speakingUsers.contains(member.userId);
                    return _MemberTile(
                      nickname: member.nickname,
                      avatarUrl: avatarUrl,
                      isOnline: isOnline,
                      isSpeaking: isSpeaking,
                    );
                  },
                );
              },
              loading: () => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败', style: AppTypography.bodySecondary),
              ),
            ),
          ),

          // ─── Divider ──────────────────────────────────
          Divider(height: 1, color: AppColors.border),

          // ─── Stream list ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Text('直播列表', style: AppTypography.sectionHeader),
                const Spacer(),
                _RefreshButton(
                  onTap: () =>
                      ref.invalidate(roomIngressesProvider(_roomIdInt)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 120,
            child: ingressesAsync.when(
              data: (ingresses) {
                if (ingresses.isEmpty) {
                  return Center(
                    child: Text('暂无直播',
                        style: TextStyle(
                            fontSize: AppTypography.sizeCaption,
                            color: AppColors.textMuted)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  physics: const BouncingScrollPhysics(),
                  itemCount: ingresses.length,
                  itemBuilder: (context, index) {
                    final ingress = ingresses[index];
                    final isSelected =
                        selectedIngress?.id == ingress.id;
                    return _StreamTile(
                      label: ingress.label,
                      isActive: ingress.isActive,
                      isSelected: isSelected,
                      onTap: () {
                        if (isSelected) {
                          // Deselect — room_detail_page watches this
                          ref
                              .read(selectedIngressProvider.notifier)
                              .state = null;
                        } else {
                          ref
                              .read(selectedIngressProvider.notifier)
                              .state = ingress;
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) => Center(
                child: Text('加载失败',
                    style: TextStyle(
                        fontSize: AppTypography.sizeCaption,
                        color: AppColors.textMuted)),
              ),
            ),
          ),

          // ─── Divider ──────────────────────────────────
          Divider(height: 1, color: AppColors.border),

          // ─── VLAN Panel ───────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: VlanPanel(roomId: roomId),
          ),
        ],
      ),
    );
  }

  String? _resolveUrl(String? baseUrl, String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('/') && baseUrl != null) {
      return '$baseUrl$value';
    }
    return value;
  }
}

// ═══════════════════════════════════════════════════════════════
// Private widgets
// ═══════════════════════════════════════════════════════════════

/// Tiny refresh icon button used in section headers.
class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.durationHover,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(Icons.refresh, size: 13, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

// ─── Stream tile ────────────────────────────────────────────

class _StreamTile extends StatefulWidget {
  const _StreamTile({
    required this.label,
    required this.isActive,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_StreamTile> createState() => _StreamTileState();
}

class _StreamTileState extends State<_StreamTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.primary.withOpacity(0.15)
                : _hovered
                    ? AppColors.hoverOverlay
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: widget.isSelected
                ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.videocam,
                size: 13,
                color: widget.isActive
                    ? AppColors.success
                    : AppColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight:
                        widget.isSelected ? FontWeight.w500 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.close, size: 12, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Member tile with online/speaking indicators ─────────

class _MemberTile extends StatefulWidget {
  const _MemberTile({
    required this.nickname,
    this.avatarUrl,
    this.isOnline = false,
    this.isSpeaking = false,
  });

  final String nickname;
  final String? avatarUrl;
  final bool isOnline;
  final bool isSpeaking;

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowAnimation = Tween(begin: 0.3, end: 0.9).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOutSine),
    );
    if (widget.isSpeaking) _glowCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _MemberTile old) {
    super.didUpdateWidget(old);
    if (widget.isSpeaking && !old.isSpeaking) {
      _glowCtrl.repeat(reverse: true);
    } else if (!widget.isSpeaking && old.isSpeaking) {
      _glowCtrl.stop();
      _glowCtrl.reset();
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 离线时降低透明度
    final opacity = widget.isOnline ? 1.0 : 0.45;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Opacity(
          opacity: opacity,
          child: Row(
            children: [
              // 头像，说话时带绿色发光边框
              AnimatedBuilder(
                animation: _glowCtrl,
                builder: (context, child) {
                  return Container(
                    decoration: widget.isSpeaking
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success
                                    .withOpacity(_glowAnimation.value),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          )
                        : null,
                    child: child,
                  );
                },
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.cardActive,
                  backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(widget.avatarUrl!)
                      : null,
                  child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                      ? Text(
                          widget.nickname.isNotEmpty
                              ? widget.nickname[0]
                              : '?',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.nickname,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusIndicator(
                isOnline: widget.isOnline,
                isSpeaking: widget.isSpeaking,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status indicator (online/speaking) ──────────────────

class _StatusIndicator extends StatefulWidget {
  const _StatusIndicator({
    required this.isOnline,
    required this.isSpeaking,
  });
  final bool isOnline;
  final bool isSpeaking;

  @override
  State<_StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<_StatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = Tween(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
    _scale = Tween(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
    if (widget.isSpeaking) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusIndicator old) {
    super.didUpdateWidget(old);
    if (widget.isSpeaking && !old.isSpeaking) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isSpeaking && old.isSpeaking) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 离线：灰色半透明圆点
    if (!widget.isOnline) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.textMuted.withOpacity(0.3),
        ),
      );
    }

    // 在线 + 说话：绿色呼吸灯动画
    if (widget.isSpeaking) {
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: Opacity(
              opacity: _opacity.value,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                ),
              ),
            ),
          );
        },
      );
    }

    // 在线 + 未说话：静态绿色实心圆点
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.success,
      ),
    );
  }
}

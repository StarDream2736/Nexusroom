import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../features/room/presentation/providers/rooms_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../widgets/sidebar_item.dart';

/// Left sidebar, always visible inside the authenticated shell.
///
/// Contents:
///   - User profile mini-card
///   - Room list (from roomsProvider)
///   - Bottom nav icons (friends, settings)
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);
    final currentLocation = GoRouterState.of(context).uri.toString();
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: context.colors.sidebar,
        border: Border(
          right: BorderSide(color: context.colors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // ─── User profile mini-card ──────────────────
          _UserCard(
            nickname: settings?.nickname ?? 'User',
            displayId: settings?.userDisplayId,
            avatarUrl:
                _resolveAvatarUrl(settings?.serverUrl, settings?.avatarUrl),
            onTap: () => context.go('/settings'),
          ),

          const SizedBox(height: 8),

          // ─── Section header ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 12, 6),
            child: Row(
              children: [
                Text('房间', style: AppTypography.sectionHeader(context)),
                const Spacer(),
                _MiniIconButton(
                  icon: Icons.home_outlined,
                  tooltip: '返回主页',
                  onTap: () => context.go('/home'),
                ),
              ],
            ),
          ),

          // ─── Room list ───────────────────────────────
          Expanded(
            child: roomsAsync.when(
              data: (rooms) {
                if (rooms.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('暂无房间',
                          style: AppTypography.bodySecondary(context)),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  physics: const BouncingScrollPhysics(),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final path = '/rooms/${room.id}';
                    final isSelected = currentLocation.startsWith(path);
                    return SidebarItem(
                      icon: Icons.tag,
                      label: room.name,
                      selected: isSelected,
                      onTap: () => context.go(path),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      Text('加载失败', style: AppTypography.bodySecondary(context)),
                ),
              ),
            ),
          ),

          // ─── Divider ─────────────────────────────────
          Divider(height: 1, color: context.colors.border),

          // ─── Bottom nav ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _BottomNavIcon(
                  icon: Icons.people_outline,
                  tooltip: '好友',
                  selected: currentLocation.startsWith('/friends'),
                  onTap: () => context.go('/friends'),
                ),
                const SizedBox(width: 4),
                _BottomNavIcon(
                  icon: Icons.settings_outlined,
                  tooltip: '设置',
                  selected: currentLocation.startsWith('/settings'),
                  onTap: () => context.go('/settings'),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _resolveAvatarUrl(String? baseUrl, String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    if (avatarUrl.startsWith('/') && baseUrl != null && baseUrl.isNotEmpty) {
      return '$baseUrl$avatarUrl';
    }
    return avatarUrl;
  }
}

// ─── Private sub-widgets ──────────────────────────────────────

class _UserCard extends StatefulWidget {
  const _UserCard({
    required this.nickname,
    this.displayId,
    this.avatarUrl,
    this.onTap,
  });

  final String nickname;
  final String? displayId;
  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? context.colors.hoverOverlay : Colors.transparent,
            borderRadius: AppTheme.radiusButton,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: context.colors.primary.withOpacity(0.2),
                backgroundImage:
                    widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                        ? NetworkImage(widget.avatarUrl!)
                        : null,
                child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                    ? Text(
                        widget.nickname.isNotEmpty ? widget.nickname[0] : '?',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.nickname,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.displayId != null)
                      Text(
                        '#${widget.displayId}',
                        style: TextStyle(
                          fontSize: 10,
                          color: context.colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatefulWidget {
  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
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
              color:
                  _hovered ? context.colors.hoverOverlay : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: context.colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavIcon extends StatefulWidget {
  const _BottomNavIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_BottomNavIcon> createState() => _BottomNavIconState();
}

class _BottomNavIconState extends State<_BottomNavIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTheme.durationHover,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.selected
                  ? context.colors.selectedOverlay
                  : _hovered
                      ? context.colors.hoverOverlay
                      : Colors.transparent,
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.selected
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

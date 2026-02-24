import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../app/widgets/hover_scale_card.dart';
import '../../../../app/widgets/mac_dialog.dart';
import '../../../../core/providers/app_providers.dart';
import '../providers/rooms_provider.dart';

class RoomListPage extends ConsumerWidget {
  const RoomListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Shell provides the sidebar with room list already.
    // This page is the center "welcome / quick actions" area.
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('欢迎回来', style: AppTypography.h1),
          const SizedBox(height: 4),
          Text('选择左侧房间进入，或从下方快速操作',
              style: AppTypography.bodySecondary),
          const SizedBox(height: 32),

          // Quick action cards
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.login,
                  label: '加入房间',
                  description: '输入邀请码加入',
                  onTap: () => _showJoinRoomDialog(context, ref),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.add_circle_outline,
                  label: '创建房间',
                  description: '创建并邀请好友',
                  onTap: () => context.go('/rooms/create'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Room count info
          _buildRoomInfo(ref),
        ],
      ),
    );
  }

  Widget _buildRoomInfo(WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);
    return roomsAsync.when(
      data: (rooms) => Text(
        '当前加入了 ${rooms.length} 个房间',
        style: AppTypography.caption,
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showJoinRoomDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    
    showMacDialog(
      context: context,
      title: '加入房间',
      contentWidget: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: '邀请码',
          hintText: '请输入6位邀请码',
        ),
        maxLength: 6,
        textCapitalization: TextCapitalization.characters,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            _joinRoom(context, ref, controller.text.trim());
          },
          child: const Text('加入'),
        ),
      ],
    );
  }

  Future<void> _joinRoom(
    BuildContext context,
    WidgetRef ref,
    String inviteCode,
  ) async {
    if (inviteCode.isEmpty) return;

    try {
      final room = await ref
          .read(roomRepositoryProvider)
          .joinRoom(inviteCode);
      if (context.mounted) {
        Navigator.pop(context);
        ref.invalidate(roomsProvider);
        context.go('/rooms/${room.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入失败: $e')),
        );
      }
    }
  }
}

/// A quick-action card with hover animation.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverScaleCard(
      onTap: onTap,
      borderRadius: AppTheme.radiusStandard,
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: AppTheme.radiusButton,
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTypography.h3),
            const SizedBox(height: 4),
            Text(description, style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../app/widgets/mac_dialog.dart';
import '../../../../core/models/livekit_models.dart';
import '../../../../core/providers/app_providers.dart';
import '../providers/room_detail_provider.dart';
import '../providers/room_stream_provider.dart';
import '../providers/rooms_provider.dart';

class RoomSettingsPage extends ConsumerStatefulWidget {
  final String roomId;

  const RoomSettingsPage({super.key, required this.roomId});

  @override
  ConsumerState<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends ConsumerState<RoomSettingsPage> {
  int get _roomId => int.parse(widget.roomId);
  List<IngressModel> _ingresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIngresses();
  }

  Future<void> _loadIngresses() async {
    try {
      final list =
          await ref.read(roomRepositoryProvider).listIngresses(_roomId);
      if (mounted) {
        setState(() {
          _ingresses = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createIngress() async {
    final labelController = TextEditingController();
    final label = await showMacDialog<String>(
      context: context,
      title: '创建推流入口',
      contentWidget: TextField(
        controller: labelController,
        decoration: const InputDecoration(
          labelText: '推流标签',
          hintText: '例如: OBS主推流',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, labelController.text),
          child: const Text('创建'),
        ),
      ],
    );

    if (label == null || label.trim().isEmpty) return;

    try {
      await ref
          .read(roomRepositoryProvider)
          .createIngress(_roomId, label.trim());
      _loadIngresses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteIngress(IngressModel ingress) async {
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '确认删除',
      content: '确定要删除推流入口 "${ingress.label}" 吗？',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('删除'),
        ),
      ],
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(roomRepositoryProvider)
          .deleteIngress(_roomId, ingress.id);

      // Clear selected ingress if it was the one deleted
      if (ref.read(selectedIngressProvider)?.id == ingress.id) {
        ref.read(selectedIngressProvider.notifier).state = null;
      }

      _loadIngresses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _leaveRoom() async {
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '退出房间',
      content: '确定要退出该房间吗？退出后需要重新通过邀请码加入。',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('退出'),
        ),
      ],
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(roomRepositoryProvider).leaveRoom(_roomId);
      if (!mounted) return;
      ref.invalidate(roomsProvider);
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('退出失败: $e')),
      );
    }
  }

  Future<void> _deleteRoom() async {
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '解散房间',
      content: '确定要解散该房间吗？此操作不可撤销，所有消息和设置将被永久删除。',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('解散'),
        ),
      ],
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(roomRepositoryProvider).deleteRoom(_roomId);
      if (!mounted) return;
      ref.invalidate(roomsProvider);
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解散失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final roomDetail = ref.watch(roomDetailProvider(_roomId)).valueOrNull;
    final currentUserId = ref.watch(appSettingsProvider).valueOrNull?.userId;
    final isOwner = roomDetail != null &&
        currentUserId != null &&
        roomDetail.ownerId == currentUserId;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: '返回房间',
                onPressed: () => context.go('/rooms/${widget.roomId}'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Text('房间设置', style: AppTypography.h1),
            ],
          ),
          const SizedBox(height: 24),

          // ─── 邀请码 ──────────────────────────────────────────────
          GlassContainer(
            padding: const EdgeInsets.all(16),
            child: _CopyableField(
              label: '房间邀请码',
              value: roomDetail?.inviteCode ?? '加载中...',
              onCopy: () {
                final code = roomDetail?.inviteCode;
                if (code != null && code.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('邀请码已复制到剪贴板')),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),

          // ─── Ingress section ─────────────────────────────
          Row(
            children: [
              Expanded(
                  child: Text('推流管理', style: AppTypography.h3)),
              ElevatedButton.icon(
                onPressed: _createIngress,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('创建推流入口'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_ingresses.isEmpty)
            GlassContainer(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('暂无推流入口，点击上方按钮创建',
                    style: AppTypography.bodySecondary),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _ingresses.length,
                itemBuilder: (context, index) {
                  final ingress = _ingresses[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _IngressCard(
                      ingress: ingress,
                      onDelete: () => _deleteIngress(ingress),
                    ),
                  );
                },
              ),
            ),

          // ─── Danger zone ────────────────────────────────
          const SizedBox(height: 24),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          if (!isOwner)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _leaveRoom,
                icon: Icon(Icons.exit_to_app, size: 16, color: AppColors.error),
                label: Text('退出房间',
                    style: TextStyle(color: AppColors.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

          if (isOwner)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _deleteRoom,
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('解散房间'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IngressCard extends StatelessWidget {
  final IngressModel ingress;
  final VoidCallback onDelete;

  const _IngressCard({required this.ingress, required this.onDelete});

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      ingress.isActive ? AppColors.success : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(ingress.label, style: AppTypography.h3)),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CopyableField(
            label: '推流服务器 (Server)',
            value: ingress.rtmpUrl,
            onCopy: () => _copy(context, ingress.rtmpUrl, '推流地址'),
          ),
          const SizedBox(height: 8),
          _CopyableField(
            label: '推流密钥 (Stream Key)',
            value: ingress.streamKey,
            onCopy: () => _copy(context, ingress.streamKey, '推流密钥'),
            obscure: true,
          ),
        ],
      ),
    );
  }
}

class _CopyableField extends StatefulWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool obscure;

  const _CopyableField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.obscure = false,
  });

  @override
  State<_CopyableField> createState() => _CopyableFieldState();
}

class _CopyableFieldState extends State<_CopyableField> {
  bool _revealed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final displayValue =
        widget.obscure && !_revealed ? '••••••••••••' : widget.value;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: TextStyle(
                          fontSize: AppTypography.sizeCaption,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(displayValue,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppTypography.sizeBody,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            if (widget.obscure)
              IconButton(
                icon: Icon(
                    _revealed ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                    color: AppColors.textSecondary),
                onPressed: () => setState(() => _revealed = !_revealed),
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              icon: Icon(Icons.copy,
                  size: 16, color: AppColors.textSecondary),
              onPressed: widget.onCopy,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

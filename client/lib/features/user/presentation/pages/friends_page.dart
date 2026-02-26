import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../app/widgets/mac_dialog.dart';
import '../../../../core/providers/app_providers.dart';

/// 好友系统页面：好友列表、待处理申请、搜索添加
class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = false;

  StreamSubscription? _friendRequestSub;
  StreamSubscription? _friendAcceptedSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _listenWsEvents();
  }

  void _listenWsEvents() {
    final ws = ref.read(wsServiceProvider);
    _friendRequestSub = ws.on('friend.request').listen((_) => _loadData());
    _friendAcceptedSub = ws.on('friend.accepted').listen((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final friendRepo = ref.read(friendRepositoryProvider);
      final results = await Future.wait([
        friendRepo.listFriends(),
        friendRepo.listPendingRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = results[0];
        _pendingRequests = results[1];
      });
    } catch (e) {
      debugPrint('[FriendsPage] _loadData failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController();
    await showMacDialog(
      context: context,
      title: '添加好友',
      contentWidget: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: '输入用户 Display ID',
          hintText: '例如: 483921',
        ),
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            final displayId = controller.text.trim();
            if (displayId.isEmpty) return;
            Navigator.pop(context);
            await _sendRequest(displayId);
          },
          child: const Text('发送申请'),
        ),
      ],
    );
    controller.dispose();
  }

  Future<void> _sendRequest(String displayId) async {
    try {
      final friendRepo = ref.read(friendRepositoryProvider);
      await friendRepo.sendRequest(displayId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('好友申请已发送')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    }
  }

  Future<void> _handleRequest(int requesterId, String action) async {
    try {
      final friendRepo = ref.read(friendRepositoryProvider);
      await friendRepo.handleRequest(requesterId, action);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'accept' ? '已接受好友申请' : '已拒绝好友申请'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  @override
  void dispose() {
    _friendRequestSub?.cancel();
    _friendAcceptedSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header row ─────────────────────────────────
          Row(
            children: [
              Expanded(child: Text('好友', style: AppTypography.h1)),
              _MiniIcon(
                  icon: Icons.person_add,
                  tooltip: '添加好友',
                  onTap: _showSearchDialog),
              const SizedBox(width: 6),
              _MiniIcon(
                  icon: Icons.refresh,
                  tooltip: '刷新',
                  onTap: _loadData),
            ],
          ),
          const SizedBox(height: 16),

          // ─── macOS-style segment control ────────────────
          GlassContainer(
            padding: const EdgeInsets.all(3),
            borderRadius: BorderRadius.circular(8),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.cardHover,
                borderRadius: BorderRadius.circular(6),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: TextStyle(
                  fontSize: AppTypography.sizeBody,
                  fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: '好友 (${_friends.length})'),
                Tab(text: '待处理 (${_pendingRequests.length})'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ─── Tab content ────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsList(),
                      _buildPendingList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return Center(
          child: Text('暂无好友', style: AppTypography.bodySecondary));
    }
    return ListView.builder(
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final f = _friends[index];
        final isOnline = f['is_online'] as bool? ?? false;
        return _FriendTile(
          avatarUrl: f['avatar_url'] as String?,
          nickname: f['nickname'] as String? ?? '',
          displayId: f['user_display_id']?.toString() ?? '',
          isOnline: isOnline,
        );
      },
    );
  }

  Widget _buildPendingList() {
    if (_pendingRequests.isEmpty) {
      return Center(
          child: Text('暂无待处理申请', style: AppTypography.bodySecondary));
    }
    return ListView.builder(
      itemCount: _pendingRequests.length,
      itemBuilder: (context, index) {
        final r = _pendingRequests[index];
        return _PendingTile(
          avatarUrl: r['requester_avatar_url'] as String?,
          nickname: r['requester_nickname'] as String? ?? '',
          displayId: r['requester_display_id']?.toString() ?? '',
          onAccept: () => _handleRequest(
              (r['requester_id'] as num).toInt(), 'accept'),
          onReject: () => _handleRequest(
              (r['requester_id'] as num).toInt(), 'reject'),
        );
      },
    );
  }
}

// ─── Private widgets ──────────────────────────────────────────

class _MiniIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniIcon(
      {required this.icon, required this.tooltip, required this.onTap});
  @override
  State<_MiniIcon> createState() => _MiniIconState();
}

class _MiniIconState extends State<_MiniIcon> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon,
                size: 16, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _FriendTile extends StatefulWidget {
  final String? avatarUrl;
  final String nickname;
  final String displayId;
  final bool isOnline;
  const _FriendTile({
    this.avatarUrl,
    required this.nickname,
    required this.displayId,
    required this.isOnline,
  });
  @override
  State<_FriendTile> createState() => _FriendTileState();
}

class _FriendTileState extends State<_FriendTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.cardActive,
              backgroundImage:
                  widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                      ? NetworkImage(widget.avatarUrl!)
                      : null,
              child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                  ? Icon(Icons.person, size: 16, color: AppColors.textMuted)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.nickname,
                      style: TextStyle(
                          fontSize: AppTypography.sizeBody,
                          color: AppColors.textPrimary)),
                  Text('ID: ${widget.displayId}',
                      style: TextStyle(
                          fontSize: AppTypography.sizeMini,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isOnline ? AppColors.success : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingTile extends StatefulWidget {
  final String? avatarUrl;
  final String nickname;
  final String displayId;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _PendingTile({
    this.avatarUrl,
    required this.nickname,
    required this.displayId,
    required this.onAccept,
    required this.onReject,
  });
  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.cardActive,
              backgroundImage:
                  widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                      ? NetworkImage(widget.avatarUrl!)
                      : null,
              child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                  ? Icon(Icons.person, size: 16, color: AppColors.textMuted)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.nickname,
                      style: TextStyle(
                          fontSize: AppTypography.sizeBody,
                          color: AppColors.textPrimary)),
                  Text('ID: ${widget.displayId}',
                      style: TextStyle(
                          fontSize: AppTypography.sizeMini,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.check, size: 18, color: AppColors.success),
              tooltip: '接受',
              onPressed: widget.onAccept,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: AppColors.error),
              tooltip: '拒绝',
              onPressed: widget.onReject,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

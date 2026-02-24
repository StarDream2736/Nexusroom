import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加好友'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '输入用户 Display ID',
            hintText: '例如: 483921',
            border: OutlineInputBorder(),
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
      ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '好友列表 (${_friends.length})'),
            Tab(text: '待处理 (${_pendingRequests.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: '添加好友',
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFriendsList(),
                _buildPendingList(),
              ],
            ),
    );
  }

  Widget _buildFriendsList() {
    if (_friends.isEmpty) {
      return const Center(child: Text('暂无好友'));
    }
    return ListView.builder(
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final f = _friends[index];
        final isOnline = f['is_online'] as bool? ?? false;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: f['avatar_url'] != null &&
                    (f['avatar_url'] as String).isNotEmpty
                ? NetworkImage(f['avatar_url'] as String)
                : null,
            child: f['avatar_url'] == null ||
                    (f['avatar_url'] as String).isEmpty
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(f['nickname'] as String? ?? ''),
          subtitle: Text('ID: ${f['user_display_id'] ?? ''}'),
          trailing: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.green : Colors.grey,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingList() {
    if (_pendingRequests.isEmpty) {
      return const Center(child: Text('暂无待处理申请'));
    }
    return ListView.builder(
      itemCount: _pendingRequests.length,
      itemBuilder: (context, index) {
        final r = _pendingRequests[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: r['requester_avatar_url'] != null &&
                    (r['requester_avatar_url'] as String).isNotEmpty
                ? NetworkImage(r['requester_avatar_url'] as String)
                : null,
            child: r['requester_avatar_url'] == null ||
                    (r['requester_avatar_url'] as String).isEmpty
                ? const Icon(Icons.person)
                : null,
          ),
          title: Text(r['requester_nickname'] as String? ?? ''),
          subtitle: Text('ID: ${r['requester_display_id'] ?? ''}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                tooltip: '接受',
                onPressed: () => _handleRequest(
                  (r['requester_id'] as num).toInt(),
                  'accept',
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: '拒绝',
                onPressed: () => _handleRequest(
                  (r['requester_id'] as num).toInt(),
                  'reject',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

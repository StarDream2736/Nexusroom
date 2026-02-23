import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';
import '../providers/rooms_provider.dart';

class RoomListPage extends ConsumerWidget {
  const RoomListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的房间'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              // TODO: 打开用户设置
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 加入房间按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showJoinRoomDialog(context, ref),
                    icon: const Icon(Icons.login),
                    label: const Text('加入房间'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/rooms/create'),
                    icon: const Icon(Icons.add),
                    label: const Text('创建房间'),
                  ),
                ),
              ],
            ),
          ),
          
          // 房间列表
          Expanded(
            child: roomsAsync.when(
              data: (rooms) {
                if (rooms.isEmpty) {
                  return const Center(child: Text('暂无房间'));
                }
                return ListView.builder(
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return ListTile(
                      title: Text(room.name),
                      subtitle: Text('邀请码: ${room.inviteCode}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/rooms/${room.id}'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('加载失败: $error')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/rooms/create'),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showJoinRoomDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('加入房间'),
        content: TextField(
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
      ),
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
        context.push('/rooms/${room.id}');
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

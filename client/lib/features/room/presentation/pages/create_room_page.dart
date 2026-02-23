import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';

class CreateRoomPage extends ConsumerStatefulWidget {
  const CreateRoomPage({super.key});

  @override
  ConsumerState<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends ConsumerState<CreateRoomPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();

      final room = await ref.read(roomRepositoryProvider).createRoom(name);

      // 创建成功，返回到房间列表（会自动刷新）
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建房间'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '创建新房间',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '创建一个房间，邀请好友加入',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              
              // 房间名称输入
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '房间名称',
                  hintText: '例如：游戏开黑房间',
                  prefixIcon: Icon(Icons.meeting_room),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入房间名称';
                  }
                  if (value.length > 128) {
                    return '房间名称不能超过128个字符';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              
              // 创建按钮
              ElevatedButton(
                onPressed: _isLoading ? null : _createRoom,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('创建房间'),
              ),
              const SizedBox(height: 16),
              
              // 取消按钮
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

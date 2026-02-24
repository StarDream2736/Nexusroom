import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../core/providers/app_providers.dart';
import '../providers/rooms_provider.dart';

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
      await ref.read(roomRepositoryProvider).createRoom(name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
        setState(() => _isLoading = false);
      }
      return;
    }

    // 创建成功 — 刷新列表并返回主页
    if (mounted) {
      ref.invalidate(roomsProvider);
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('创建新房间', style: AppTypography.h1),
              const SizedBox(height: 6),
              Text('创建一个房间，邀请好友加入',
                  style: AppTypography.bodySecondary),
              const SizedBox(height: 28),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '房间名称',
                  hintText: '例如：游戏开黑房间',
                  prefixIcon: Icon(Icons.meeting_room),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return '请输入房间名称';
                  if (value.length > 128) return '房间名称不能超过128个字符';
                  return null;
                },
              ),
              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: _isLoading ? null : _createRoom,
                child: _isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('创建房间'),
              ),
              const SizedBox(height: 10),

              OutlinedButton(
                onPressed: () => context.go('/home'),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

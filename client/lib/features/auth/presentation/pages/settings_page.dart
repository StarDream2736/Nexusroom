import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/app_providers.dart';

/// 客户端设置页：头像上传、昵称修改、更换服务器、退出登录
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _nicknameController = TextEditingController();
  bool _isLoading = false;
  String? _avatarUrl;
  String? _userDisplayId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final me = await userRepo.getMe();
      final baseUrl = ref.read(appSettingsProvider).valueOrNull?.serverUrl;
      if (!mounted) return;
      setState(() {
        _nicknameController.text = me['nickname'] ?? '';
        _avatarUrl = _resolveUrl(baseUrl, me['avatar_url'] as String?);
        _userDisplayId = me['user_display_id'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _updateNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final userRepo = ref.read(userRepositoryProvider);
      await userRepo.updateProfile(nickname: nickname);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('昵称已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isLoading = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(image.path),
      });
      final data = await apiClient.postForm('/api/v1/users/me/avatar', formData);
      final baseUrl = ref.read(appSettingsProvider).valueOrNull?.serverUrl;
      final avatarUrl = _resolveUrl(
        baseUrl,
        (data as Map<String, dynamic>)['avatar_url'] as String?,
      );
      if (avatarUrl == null || avatarUrl.isEmpty) {
        throw Exception('头像地址无效');
      }
      if (!mounted) return;
      setState(() => _avatarUrl = avatarUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更换服务器'),
        content: const Text('更换服务器将清除本地登录状态，确认继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(appSettingsProvider.notifier).clearAll();
    if (!mounted) return;
    context.go('/setup');
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认退出当前账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(appSettingsProvider.notifier).clearAuth();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  String? _resolveUrl(String? baseUrl, String? value) {
    if (value == null || value.isEmpty) return value;
    if (value.startsWith('/') && baseUrl != null && baseUrl.isNotEmpty) {
      return '$baseUrl$value';
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 头像
                Center(
                  child: GestureDetector(
                    onTap: _uploadAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: _avatarUrl != null &&
                                  _avatarUrl!.isNotEmpty
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child:
                              _avatarUrl == null || _avatarUrl!.isEmpty
                                  ? const Icon(Icons.person, size: 48)
                                  : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_userDisplayId != null)
                  Center(
                    child: Text(
                      'ID: $_userDisplayId',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 24),

                // 昵称修改
                TextField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    labelText: '昵称',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: _updateNickname,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 当前服务器
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('当前服务器'),
                  subtitle: Text(settings?.serverUrl ?? '未配置'),
                ),
                const Divider(),

                // 更换服务器
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('更换服务器'),
                  onTap: _changeServer,
                ),

                // 退出登录
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    '退出登录',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _logout,
                ),
              ],
            ),
    );
  }
}

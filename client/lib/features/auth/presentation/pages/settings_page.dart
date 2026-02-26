import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' show Hardware, MediaDevice;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../app/widgets/mac_dialog.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../room/presentation/providers/rooms_provider.dart';

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

  // 音频设备
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _audioOutputs = [];
  String? _selectedAudioInputId;
  String? _selectedAudioOutputId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAudioDevices();
  }

  Future<void> _loadAudioDevices() async {
    try {
      final inputs = await Hardware.instance.enumerateDevices(type: 'audioinput');
      final outputs = await Hardware.instance.enumerateDevices(type: 'audiooutput');
      if (!mounted) return;

      // 从持久化设置中恢复上次选择
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final savedInputId = settings?.audioInputDeviceId;
      final savedOutputId = settings?.audioOutputDeviceId;

      setState(() {
        _audioInputs = inputs;
        _audioOutputs = outputs;
        // 优先使用已保存的设备 ID，若该设备不存在则回退到第一个
        if (_audioInputs.isNotEmpty) {
          final hasMatch = savedInputId != null &&
              _audioInputs.any((d) => d.deviceId == savedInputId);
          _selectedAudioInputId = hasMatch
              ? savedInputId
              : _audioInputs.first.deviceId;
        }
        if (_audioOutputs.isNotEmpty) {
          final hasMatch = savedOutputId != null &&
              _audioOutputs.any((d) => d.deviceId == savedOutputId);
          _selectedAudioOutputId = hasMatch
              ? savedOutputId
              : _audioOutputs.first.deviceId;
        }
      });

      // 应用已保存的设备选择
      if (_selectedAudioInputId != null) {
        final device = _audioInputs.firstWhere(
          (d) => d.deviceId == _selectedAudioInputId,
        );
        Hardware.instance.selectAudioInput(device);
      }
      if (_selectedAudioOutputId != null) {
        final device = _audioOutputs.firstWhere(
          (d) => d.deviceId == _selectedAudioOutputId,
        );
        Hardware.instance.selectAudioOutput(device);
      }
    } catch (_) {}
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
      // 同步到本地设置
      ref.read(appSettingsProvider.notifier).setNickname(nickname);
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
      // 同步到本地设置，供侧边栏使用
      final rawUrl = data['avatar_url'] as String?;
      if (rawUrl != null) {
        ref.read(appSettingsProvider.notifier).setAvatarUrl(rawUrl);
      }
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
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '更换服务器',
      content: '更换服务器将清除本地登录状态和缓存数据，确认继续？',
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
    );
    if (confirmed != true || !mounted) return;

    // 断开 LiveKit 语音连接
    ref.read(livekitServiceProvider).disconnect();
    // 清除所有本地消息缓存（跳服务器了，全清）
    await ref.read(appDatabaseProvider).messagesDao.clearAll();
    // 清除房间列表缓存
    ref.invalidate(roomsProvider);
    // 清状态，GoRouter redirect 会自动导航到 /setup
    await ref.read(appSettingsProvider.notifier).clearAll();
  }

  Future<void> _logout() async {
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '退出登录',
      content: '确认退出当前账号？',
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
    );
    if (confirmed != true || !mounted) return;

    // 断开 LiveKit 语音连接
    ref.read(livekitServiceProvider).disconnect();
    // 清除当前服务器的本地消息缓存
    final serverUrl = ref.read(appSettingsProvider).valueOrNull?.serverUrl;
    if (serverUrl != null && serverUrl.isNotEmpty) {
      await ref.read(appDatabaseProvider).messagesDao.clearByServerUrl(serverUrl);
    }
    // 清状态，GoRouter redirect 会自动导航到 /login
    await ref.read(appSettingsProvider.notifier).clearAuth();
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '清除本地数据',
      content: '将删除本地数据库和图片缓存，应用会自动重启。确认继续？',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('确认清除', style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    try {
      // 1. 关闭数据库连接
      final db = ref.read(appDatabaseProvider);
      await db.close();

      // 2. 删除 SQLite 数据库文件
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File('${dir.path}/nexusroom.sqlite');
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      // 3. 清除图片缓存
      await DefaultCacheManager().emptyCache();

      // 4. 退出应用，下次启动时会重建数据库
      exit(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除失败: $e')),
      );
    }
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
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text('设置', style: AppTypography.h1),
        const SizedBox(height: 24),

        // ─── Profile card ──────────────────────────────────
        GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              GestureDetector(
                onTap: _uploadAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.cardActive,
                      backgroundImage:
                          _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(_avatarUrl!)
                              : null,
                      child: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? Icon(Icons.person,
                              size: 36, color: AppColors.textMuted)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_userDisplayId != null)
                Text('ID: $_userDisplayId',
                    style: TextStyle(
                        fontSize: AppTypography.sizeCaption,
                        color: AppColors.textMuted)),
              const SizedBox(height: 16),

              TextField(
                controller: _nicknameController,
                decoration: InputDecoration(
                  labelText: '昵称',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _updateNickname,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ─── Audio device settings ───────────────────────
        GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.headset, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text('音频设置', style: TextStyle(
                    fontSize: AppTypography.sizeBody,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
                ],
              ),
              const SizedBox(height: 16),
              // 麦克风
              Text('麦克风', style: TextStyle(
                fontSize: AppTypography.sizeCaption,
                color: AppColors.textMuted,
              )),
              const SizedBox(height: 4),
              _buildAudioDropdown(
                devices: _audioInputs,
                selectedId: _selectedAudioInputId,
                onChanged: (deviceId) {
                  setState(() => _selectedAudioInputId = deviceId);
                  final device = _audioInputs.firstWhere(
                    (d) => d.deviceId == deviceId,
                    orElse: () => _audioInputs.first,
                  );
                  Hardware.instance.selectAudioInput(device);
                  if (deviceId != null) {
                    ref.read(appSettingsProvider.notifier)
                        .setAudioInputDeviceId(deviceId);
                  }
                },
              ),
              const SizedBox(height: 12),
              // 扬声器
              Text('扬声器', style: TextStyle(
                fontSize: AppTypography.sizeCaption,
                color: AppColors.textMuted,
              )),
              const SizedBox(height: 4),
              _buildAudioDropdown(
                devices: _audioOutputs,
                selectedId: _selectedAudioOutputId,
                onChanged: (deviceId) {
                  setState(() => _selectedAudioOutputId = deviceId);
                  final device = _audioOutputs.firstWhere(
                    (d) => d.deviceId == deviceId,
                    orElse: () => _audioOutputs.first,
                  );
                  Hardware.instance.selectAudioOutput(device);
                  if (deviceId != null) {
                    ref.read(appSettingsProvider.notifier)
                        .setAudioOutputDeviceId(deviceId);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ─── Server info ───────────────────────────────────
        GlassContainer(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.dns_outlined,
                label: '当前服务器',
                subtitle: settings?.serverUrl ?? '未配置',
              ),
              Divider(height: 1, color: AppColors.border),
              _SettingsTile(
                icon: Icons.swap_horiz,
                label: '更换服务器',
                onTap: _changeServer,
              ),
              Divider(height: 1, color: AppColors.border),
              _SettingsTile(
                icon: Icons.logout,
                label: '退出登录',
                iconColor: AppColors.error,
                labelColor: AppColors.error,
                onTap: _logout,
              ),
              Divider(height: 1, color: AppColors.border),
              _SettingsTile(
                icon: Icons.delete_forever,
                label: '清除本地数据',
                iconColor: AppColors.error,
                labelColor: AppColors.error,
                onTap: _clearLocalData,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudioDropdown({
    required List<MediaDevice> devices,
    required String? selectedId,
    required ValueChanged<String?> onChanged,
  }) {
    if (devices.isEmpty) {
      return Text('未检测到设备', style: TextStyle(
        fontSize: AppTypography.sizeCaption,
        color: AppColors.textMuted,
      ));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<String>(
        value: selectedId,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.sidebar,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textPrimary,
        ),
        items: devices.map((d) {
          return DropdownMenuItem<String>(
            value: d.deviceId,
            child: Text(
              d.label.isNotEmpty ? d.label : d.deviceId,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    this.labelColor,
    this.onTap,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
        child: ListTile(
          dense: true,
          leading: Icon(widget.icon,
              size: 18, color: widget.iconColor ?? AppColors.textSecondary),
          title: Text(widget.label,
              style: TextStyle(
                  fontSize: AppTypography.sizeBody,
                  color: widget.labelColor ?? AppColors.textPrimary)),
          subtitle: widget.subtitle != null
              ? Text(widget.subtitle!,
                  style: TextStyle(
                      fontSize: AppTypography.sizeCaption,
                      color: AppColors.textMuted))
              : null,
          trailing: widget.onTap != null
              ? Icon(Icons.chevron_right,
                  size: 16, color: AppColors.textMuted)
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

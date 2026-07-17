import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../app/widgets/mac_dialog.dart';
import '../../../../core/models/app_settings.dart';
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
  List<MediaDeviceInfo> _audioInputs = [];
  List<MediaDeviceInfo> _audioOutputs = [];
  String? _selectedAudioInputId;
  String? _selectedAudioOutputId;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAudioDevices();
  }

  Future<void> _loadAudioDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final inputs =
          devices.where((device) => device.kind == 'audioinput').toList();
      final outputs =
          devices.where((device) => device.kind == 'audiooutput').toList();
      if (!mounted) return;

      // 从持久化设置中恢复上次选择
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final savedInputId = settings?.audioInputDeviceId;
      final savedOutputId = settings?.audioOutputDeviceId;

      setState(() {
        _audioInputs = inputs;
        _audioOutputs = outputs;
        _audioError = inputs.isEmpty ? '未检测到麦克风，请检查系统权限和设备连接' : null;
        // 优先使用已保存的设备 ID，若该设备不存在则回退到第一个
        if (_audioInputs.isNotEmpty) {
          final hasMatch = savedInputId != null &&
              _audioInputs.any((d) => d.deviceId == savedInputId);
          _selectedAudioInputId =
              hasMatch ? savedInputId : _audioInputs.first.deviceId;
        }
        if (_audioOutputs.isNotEmpty) {
          final hasMatch = savedOutputId != null &&
              _audioOutputs.any((d) => d.deviceId == savedOutputId);
          _selectedAudioOutputId =
              hasMatch ? savedOutputId : _audioOutputs.first.deviceId;
        }
      });

      // 应用已保存的设备选择
      if (_selectedAudioInputId != null) {
        await Helper.selectAudioInput(_selectedAudioInputId!);
      }
      if (_selectedAudioOutputId != null) {
        await Helper.selectAudioOutput(_selectedAudioOutputId!);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _audioError = '音频设备读取失败: $error');
      }
    }
  }

  Future<void> _selectAudioInput(String? deviceId) async {
    if (deviceId == null || deviceId == _selectedAudioInputId) return;
    final previous = _selectedAudioInputId;
    setState(() {
      _selectedAudioInputId = deviceId;
      _audioError = null;
    });
    try {
      await Helper.selectAudioInput(deviceId);
      await ref
          .read(appSettingsProvider.notifier)
          .setAudioInputDeviceId(deviceId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selectedAudioInputId = previous;
        _audioError = '麦克风切换失败: $error';
      });
    }
  }

  Future<void> _selectAudioOutput(String? deviceId) async {
    if (deviceId == null || deviceId == _selectedAudioOutputId) return;
    final previous = _selectedAudioOutputId;
    setState(() {
      _selectedAudioOutputId = deviceId;
      _audioError = null;
    });
    try {
      await Helper.selectAudioOutput(deviceId);
      await ref
          .read(appSettingsProvider.notifier)
          .setAudioOutputDeviceId(deviceId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selectedAudioOutputId = previous;
        _audioError = '扬声器切换失败: $error';
      });
    }
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
      final data =
          await apiClient.postForm('/api/v1/users/me/avatar', formData);
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

    // 断开 NexusRoom RTC 语音连接
    ref.read(rtcServiceProvider).disconnect();
    final currentSettings = ref.read(appSettingsProvider).valueOrNull;
    if (currentSettings?.serverUrl != null && currentSettings?.userId != null) {
      await ref.read(appDatabaseProvider).messagesDao.clearAccount(
            currentSettings!.serverUrl!,
            currentSettings.userId!,
          );
    }
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

    // 断开 NexusRoom RTC 语音连接
    ref.read(rtcServiceProvider).disconnect();
    // 清除当前服务器的本地消息缓存
    final currentSettings = ref.read(appSettingsProvider).valueOrNull;
    if (currentSettings?.serverUrl != null && currentSettings?.userId != null) {
      await ref.read(appDatabaseProvider).messagesDao.clearAccount(
            currentSettings!.serverUrl!,
            currentSettings.userId!,
          );
    }
    // 清状态，GoRouter redirect 会自动导航到 /login
    await ref.read(appSettingsProvider.notifier).clearAuth();
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showMacDialog<bool>(
      context: context,
      title: '清除本地数据',
      content: '将清除全部账号设置、登录状态和房间消息缓存，并返回服务器设置页。确认继续？',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('确认清除', style: TextStyle(color: context.colors.error)),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    try {
      // Keep the live database connection available to Riverpod services.
      ref.read(rtcServiceProvider).disconnect();
      ref.read(wsServiceProvider).disconnect();
      final db = ref.read(appDatabaseProvider);
      await db.clearLocalData();
      await ref.read(appSettingsProvider.notifier).reload();
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
        Text('设置', style: AppTypography.h1(context)),
        const SizedBox(height: 24),

        GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.contrast_outlined,
                      size: 18, color: context.colors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    '外观',
                    style: TextStyle(
                      fontSize: AppTypography.sizeBody,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppColorMode>(
                  segments: const [
                    ButtonSegment(
                      value: AppColorMode.dark,
                      label: Text('暗色'),
                      icon: Icon(Icons.dark_mode_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: AppColorMode.light,
                      label: Text('亮色'),
                      icon: Icon(Icons.light_mode_outlined, size: 16),
                    ),
                  ],
                  selected: {settings?.colorMode ?? AppColorMode.dark},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setColorMode(selection.first);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

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
                      backgroundColor: context.colors.cardActive,
                      backgroundImage:
                          _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? NetworkImage(_avatarUrl!)
                              : null,
                      child: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? Icon(Icons.person,
                              size: 36, color: context.colors.textMuted)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: context.colors.accent,
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
                        color: context.colors.textMuted)),
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
                  Icon(Icons.headset,
                      size: 18, color: context.colors.textSecondary),
                  const SizedBox(width: 8),
                  Text('音频设置',
                      style: TextStyle(
                        fontSize: AppTypography.sizeBody,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      )),
                ],
              ),
              const SizedBox(height: 16),
              if (_audioError != null) ...[
                Text(
                  _audioError!,
                  style: TextStyle(
                    fontSize: AppTypography.sizeCaption,
                    color: context.colors.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // 麦克风
              Text('麦克风',
                  style: TextStyle(
                    fontSize: AppTypography.sizeCaption,
                    color: context.colors.textMuted,
                  )),
              const SizedBox(height: 4),
              _buildAudioDropdown(
                devices: _audioInputs,
                selectedId: _selectedAudioInputId,
                onChanged: _selectAudioInput,
              ),
              const SizedBox(height: 12),
              // 扬声器
              Text('扬声器',
                  style: TextStyle(
                    fontSize: AppTypography.sizeCaption,
                    color: context.colors.textMuted,
                  )),
              const SizedBox(height: 4),
              _buildAudioDropdown(
                devices: _audioOutputs,
                selectedId: _selectedAudioOutputId,
                onChanged: _selectAudioOutput,
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
              Divider(height: 1, color: context.colors.border),
              _SettingsTile(
                icon: Icons.swap_horiz,
                label: '更换服务器',
                onTap: _changeServer,
              ),
              Divider(height: 1, color: context.colors.border),
              _SettingsTile(
                icon: Icons.logout,
                label: '退出登录',
                iconColor: context.colors.error,
                labelColor: context.colors.error,
                onTap: _logout,
              ),
              Divider(height: 1, color: context.colors.border),
              _SettingsTile(
                icon: Icons.delete_forever,
                label: '清除本地数据',
                iconColor: context.colors.error,
                labelColor: context.colors.error,
                onTap: _clearLocalData,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAudioDropdown({
    required List<MediaDeviceInfo> devices,
    required String? selectedId,
    required ValueChanged<String?> onChanged,
  }) {
    if (devices.isEmpty) {
      return Text('未检测到设备',
          style: TextStyle(
            fontSize: AppTypography.sizeCaption,
            color: context.colors.textMuted,
          ));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<String>(
        value: selectedId,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: context.colors.sidebar,
        style: TextStyle(
          fontSize: 12,
          color: context.colors.textPrimary,
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
        color: _hovered ? context.colors.hoverOverlay : Colors.transparent,
        child: ListTile(
          dense: true,
          leading: Icon(widget.icon,
              size: 18,
              color: widget.iconColor ?? context.colors.textSecondary),
          title: Text(widget.label,
              style: TextStyle(
                  fontSize: AppTypography.sizeBody,
                  color: widget.labelColor ?? context.colors.textPrimary)),
          subtitle: widget.subtitle != null
              ? Text(widget.subtitle!,
                  style: TextStyle(
                      fontSize: AppTypography.sizeCaption,
                      color: context.colors.textMuted))
              : null,
          trailing: widget.onTap != null
              ? Icon(Icons.chevron_right,
                  size: 16, color: context.colors.textMuted)
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

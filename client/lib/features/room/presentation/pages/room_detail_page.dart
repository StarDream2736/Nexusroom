import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/models/livekit_models.dart';
import '../../../../core/network/livekit_service.dart';
import '../../../../core/network/stream_player.dart';
import '../../../../core/network/ws_service.dart';
import '../../../../core/providers/app_providers.dart';
import '../providers/messages_provider.dart';
import '../providers/room_detail_provider.dart';
import '../providers/room_stream_provider.dart';
import '../providers/voice_state_provider.dart';

class RoomDetailPage extends ConsumerStatefulWidget {
  final String roomId;

  const RoomDetailPage({super.key, required this.roomId});

  @override
  ConsumerState<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends ConsumerState<RoomDetailPage> {
  final _messageController = TextEditingController();
  bool _isMuted = true;
  bool _livekitConnected = false;
  String? _livekitError;

  // 直播流（独立于语音房间）
  final StreamPlayer _streamPlayer = StreamPlayer();
  StreamSubscription? _videoTrackSub;
  StreamSubscription? _streamStatusSub;
  lk.VideoTrack? _streamVideoTrack;
  StreamPlayerStatus _streamStatus = StreamPlayerStatus.idle;

  StreamSubscription? _participantsSub;
  StreamSubscription? _connectionStateSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _kickedSub;
  StreamSubscription? _memberJoinSub;
  StreamSubscription? _memberLeaveSub;
  StreamSubscription? _voiceStateSub;
  StreamSubscription? _ingressRefreshSub;
  StreamSubscription? _ingressUpdateSub;
  WsService? _wsService;
  LiveKitService? _livekitService;
  int _lastIngressCount = -1;

  int get _roomId => int.parse(widget.roomId);

  @override
  void initState() {
    super.initState();
    _wsService = ref.read(wsServiceProvider);
    _livekitService = ref.read(livekitServiceProvider);

    // 切换房间时清理上一个房间的全局状态（延迟到第一帧构建完成后）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedIngressProvider.notifier).state = null;
      ref.read(streamMutedProvider.notifier).state = false;
      ref.read(voiceActiveUsersProvider.notifier).clear();
    });

    // 房间 join/leave 由 AppShell 统一管理，此处不再冗余 join
    final serverUrl = ref.read(appSettingsProvider).valueOrNull?.serverUrl ?? '';
    ref.read(messageRepositoryProvider).syncLatest(_roomId, serverUrl: serverUrl);

    // 监听被踢出事件
    _kickedSub = _wsService!.on('room.kicked').listen((payload) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('你已被踢出房间: ${payload['reason'] ?? ''}')),
        );
        context.go('/home');
      }
    });

    // 成员加入/离开时刷新房间详情
    _memberJoinSub = _wsService!.on('room.member_join').listen((_) {
      ref.invalidate(roomDetailProvider(_roomId));
    });
    _memberLeaveSub = _wsService!.on('room.member_leave').listen((_) {
      ref.invalidate(roomDetailProvider(_roomId));
    });

    // 语音状态更新 → 呼吸灯指示器
    _voiceStateSub = _wsService!.on('voice.state_update').listen((payload) {
      final userId = payload['user_id'] as int?;
      final muted = payload['muted'] as bool? ?? true;
      if (userId != null) {
        ref
            .read(voiceActiveUsersProvider.notifier)
            .setActive(userId, active: !muted);
      }
    });

    _connectLiveKit();

    // 监听 LiveKit 参与者变化 → 自动刷新直播列表
    _ingressRefreshSub = _livekitService!.participantsStream.listen((_) {
      final count = _livekitService!.ingressParticipants.length;
      if (count != _lastIngressCount) {
        _lastIngressCount = count;
        ref.invalidate(roomIngressesProvider(_roomId));
      }
    });

    // 监听 WS ingress 更新事件 → 实时刷新直播列表
    _ingressUpdateSub = _wsService!.on('room.ingress_update').listen((_) {
      ref.invalidate(roomIngressesProvider(_roomId));
    });

    // StreamPlayer listeners
    _videoTrackSub = _streamPlayer.videoTrackStream.listen((track) {
      if (mounted) setState(() => _streamVideoTrack = track);
    });
    _streamStatusSub = _streamPlayer.statusStream.listen((status) {
      if (mounted) setState(() => _streamStatus = status);
    });
  }

  Future<void> _connectLiveKit() async {
    // 如果 LiveKit 已经连接到同一个房间（从设置页返回），跳过重连
    if (_livekitService!.connectedRoomId == _roomId) {
      debugPrint('[LiveKit] Already connected to room $_roomId, reusing connection');
      setState(() {
        _livekitConnected = _livekitService!.isConnected;
        _isMuted = !_livekitService!.isMicrophoneEnabled;
      });
      return;
    }

    // 监听连接状态变化（每次 initState 都要绑定，因为旧 subscription 在 dispose 中已 cancel）
    _connectionStateSub = _livekitService!.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          if (state == lk.ConnectionState.connected) {
            _livekitConnected = true;
            _livekitError = null;
          } else if (state == lk.ConnectionState.disconnected) {
            _livekitConnected = false;
          }
        });
      }
    });

    // 监听错误
    _errorSub = _livekitService!.errorStream.listen((error) {
      if (mounted) {
        setState(() => _livekitError = error);
      }
    });

    try {
      // 获取 LiveKit Token 和动态 URL
      final tokenResult =
          await ref.read(roomRepositoryProvider).getLiveKitToken(_roomId);
      
      // 获取房间详情以获取动态 LiveKit URL
      final roomDetail = await ref.read(roomDetailProvider(_roomId).future);
      
      // 使用房间返回的 LiveKit URL，如果为空则 fallback 到 token 中的 URL
      final liveKitUrl = roomDetail.liveKitUrl.isNotEmpty 
          ? roomDetail.liveKitUrl 
          : tokenResult.url;
      
      debugPrint('[LiveKit] Voice room URL: $liveKitUrl');

      // 连接语音房间
      await _livekitService!.connect(liveKitUrl, tokenResult.token, roomId: _roomId);

      // 默认静音
      await _livekitService!.setMicrophoneEnabled(false);
    } catch (e) {
      // LiveKit 连接失败不阻塞聊天，但在 UI 上显示
      debugPrint('[LiveKit] Connection failed: $e');
      if (mounted) {
        setState(() => _livekitError = '$e');
      }
    }
  }

  @override
  void dispose() {
    // Clear video track reference FIRST — prevents Duplicate GlobalKey
    // during route transition when old & new pages briefly coexist.
    _streamVideoTrack = null;

    _videoTrackSub?.cancel();
    _streamStatusSub?.cancel();
    _streamPlayer.dispose();
    _participantsSub?.cancel();
    _connectionStateSub?.cancel();
    _errorSub?.cancel();
    _kickedSub?.cancel();
    _memberJoinSub?.cancel();
    _memberLeaveSub?.cancel();
    _voiceStateSub?.cancel();
    _ingressRefreshSub?.cancel();
    _ingressUpdateSub?.cancel();
    // 房间 join/leave 由 AppShell 统一管理
    // LiveKit 语音连接也由 AppShell 在切换房间时统一断开
    // 此处只清理 StreamPlayer（直播流进入设置页时可中断，返回后重选）
    _messageController.dispose();
    super.dispose();
  }

  void _toggleMute() async {
    if (!_livekitConnected || _livekitService == null) return;
    final newMuted = !_isMuted;
    try {
      await _livekitService!.setMicrophoneEnabled(!newMuted);
      _wsService?.sendVoiceMute(
        roomId: _roomId,
        muted: newMuted,
      );
      setState(() => _isMuted = newMuted);
    } catch (e) {
      debugPrint('[RoomDetail] toggleMute failed: $e');
    }
  }

  /// 打开直播流（连接独立的直播 LiveKit 房间）
  Future<void> _selectStream(IngressModel ingress) async {
    // 断开之前的直播连接
    await _streamPlayer.disconnect();

    setState(() {
      _streamVideoTrack = null;
    });

    try {
      // 获取直播房间 Token
      final tokenResult =
          await ref.read(roomRepositoryProvider).getStreamToken(_roomId);
      debugPrint('[StreamPlayer] Connecting to ${tokenResult.url}');

      await _streamPlayer.connect(tokenResult.url, tokenResult.token);
    } catch (e) {
      debugPrint('[StreamPlayer] Failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('直播连接失败: $e')),
        );
      }
    }
  }

  /// 关闭直播流
  Future<void> _closeStream() async {
    await _streamPlayer.disconnect();
    setState(() {
      _streamVideoTrack = null;
    });
  }

  /// 全屏播放直播流
  void _showFullscreen() {
    if (_streamVideoTrack == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            lk.VideoTrackRenderer(_streamVideoTrack!),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomDetailProvider(_roomId));
    final serverUrl = ref.watch(appSettingsProvider).value?.serverUrl ?? '';
    final messagesAsync = ref.watch(messagesStreamProvider(
      (roomId: _roomId, serverUrl: serverUrl),
    ));
    final baseUrl = ref.watch(appSettingsProvider).value?.serverUrl;
    final authToken = ref.watch(appSettingsProvider).value?.token;
    final selectedIngress = ref.watch(selectedIngressProvider);
    final streamMuted = ref.watch(streamMutedProvider);

    // React to stream selection from right panel
    ref.listen<IngressModel?>(selectedIngressProvider, (prev, next) {
      if (next != null && prev?.id != next.id) {
        _selectStream(next);
      } else if (next == null && prev != null) {
        _closeStream();
      }
    });

    // The Shell provides TitleBar, Sidebar, and RightPanel.
    // This page only renders the center content area.
    return Column(
      children: [
        // ─── Top bar (room name + controls) ──────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              _MiniControl(
                icon: Icons.arrow_back,
                tooltip: '退出房间',
                onTap: () => context.go('/home'),
              ),
              const SizedBox(width: 8),
              Text(
                roomAsync.value?.name ?? '房间',
                style: AppTypography.h3,
              ),
              const Spacer(),
              _MiniControl(
                icon: Icons.settings_outlined,
                tooltip: '房间设置',
                onTap: () =>
                    context.go('/rooms/${widget.roomId}/settings'),
              ),
            ],
          ),
        ),

        // ─── Main content ────────────────────────────────
        Expanded(
          child: Column(
            children: [
              // Video area — animated expand / collapse (16:9)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: selectedIngress != null
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.cardActive,
                              borderRadius: AppTheme.radiusStandard,
                              border: Border.all(
                                  color: AppColors.border, width: 1),
                            ),
                            child: ClipRRect(
                              borderRadius: AppTheme.radiusStandard,
                              child: _buildMainVideoView(
                                selectedIngress,
                                streamMuted,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // Chat area — fills remaining space
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      // Messages
                      Expanded(
                        child: messagesAsync.when(
                          data: (messages) {
                            if (messages.isEmpty) {
                              return Center(
                                child: Text('暂无消息',
                                    style: AppTypography.bodySecondary),
                              );
                            }
                            return ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              physics: const BouncingScrollPhysics(),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final message = messages[messages.length - 1 - index];
                                final sender = message.senderNickname ??
                                    '用户${message.senderId}';
                                final avatarUrl = message.senderAvatarUrl != null
                                    ? _resolveUrl(baseUrl, message.senderAvatarUrl!)
                                    : null;
                                final rawImageUrl = message.type == 'image'
                                    ? _resolveUrl(baseUrl, message.content)
                                    : null;
                                final imageUrlWithToken = rawImageUrl != null && authToken != null
                                    ? '$rawImageUrl?token=$authToken'
                                    : rawImageUrl;
                                return _ChatBubble(
                                  sender: sender,
                                  senderAvatarUrl: avatarUrl,
                                  content: message.type == 'image'
                                      ? null
                                      : message.content,
                                  imageUrl: imageUrlWithToken,
                                );
                              },
                            );
                          },
                          loading: () => const Center(
                              child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                              child: Text('消息加载失败: $error',
                                  style: AppTypography.bodySecondary)),
                        ),
                      ),

                      // Input bar
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                                color: AppColors.border, width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Voice mic toggle (moved from top bar)
                            _VoiceControlButton(
                              isMuted: _isMuted,
                              isConnected: _livekitConnected,
                              error: _livekitError,
                              onToggle:
                                  _livekitConnected ? _toggleMute : null,
                            ),
                            const SizedBox(width: 6),
                            _MiniControl(
                              icon: Icons.image_outlined,
                              tooltip: '发送图片',
                              onTap: _sendImage,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary),
                                decoration: InputDecoration(
                                  hintText: '输入消息...',
                                  filled: true,
                                  fillColor: AppColors.background,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        AppTheme.radiusBubble,
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius:
                                        AppTheme.radiusBubble,
                                    borderSide: BorderSide(
                                        color: AppColors.border,
                                        width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        AppTheme.radiusBubble,
                                    borderSide: BorderSide(
                                        color: AppColors.primary,
                                        width: 1),
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MiniControl(
                              icon: Icons.send,
                              tooltip: '发送',
                              onTap: _sendMessage,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainVideoView(
    IngressModel selectedIngress,
    bool streamMuted,
  ) {
    // 正在连接或等待推流
    if (_streamVideoTrack == null) {
      String statusText;
      switch (_streamStatus) {
        case StreamPlayerStatus.connecting:
          statusText = '正在连接直播房间...';
          break;
        case StreamPlayerStatus.connected:
        case StreamPlayerStatus.waitingForStream:
          statusText = '已连接，等待推流...';
          break;
        case StreamPlayerStatus.error:
          statusText = '直播连接失败';
          break;
        default:
          statusText = '正在加载视频...';
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_streamStatus != StreamPlayerStatus.error)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
            if (_streamStatus == StreamPlayerStatus.error)
              Icon(Icons.error_outline, size: 40, color: AppColors.error),
            const SizedBox(height: 10),
            Text(statusText, style: AppTypography.bodySecondary),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  ref.read(selectedIngressProvider.notifier).state = null,
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        lk.VideoTrackRenderer(_streamVideoTrack!),
        // ─── Label ──────────────────
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Text(
              selectedIngress.label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        // ─── Controls (bottom-right) ────
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniControl(
                  icon: Icons.refresh,
                  tooltip: '刷新直播',
                  onTap: () => _selectStream(selectedIngress),
                  color: Colors.white,
                ),
                _MiniControl(
                  icon: Icons.fullscreen,
                  tooltip: '全屏',
                  onTap: _showFullscreen,
                  color: Colors.white,
                ),
                _MiniControl(
                  icon: streamMuted ? Icons.volume_off : Icons.volume_up,
                  tooltip: streamMuted ? '取消静音' : '静音',
                  onTap: () {
                    final newMuted = !streamMuted;
                    ref.read(streamMutedProvider.notifier).state = newMuted;
                    _streamPlayer.setAudioMuted(newMuted);
                  },
                  color: Colors.white,
                ),
                _MiniControl(
                  icon: Icons.close,
                  tooltip: '关闭直播',
                  onTap: () =>
                      ref.read(selectedIngressProvider.notifier).state = null,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    debugPrint('[RoomDetail] _sendMessage roomId=$_roomId content="$content"');
    ref.read(wsServiceProvider).sendChat(roomId: _roomId, content: content);
    _messageController.clear();
  }

  String _resolveUrl(String? baseUrl, String value) {
    if (value.startsWith('/') && baseUrl != null) {
      return '$baseUrl$value';
    }
    return value;
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    try {
      final uploaded =
          await ref.read(fileRepositoryProvider).uploadFile(
                file.path,
                roomId: _roomId,
              );
      ref.read(wsServiceProvider).sendChat(
            roomId: _roomId,
            type: 'image',
            content: uploaded.url,
            meta: {
              'file_id': uploaded.fileId,
              'file_name': File(file.path).uri.pathSegments.last,
              'mime_type': uploaded.mimeType,
              'size_bytes': uploaded.sizeBytes,
            },
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片发送失败: $e')),
        );
      }
    }
  }
}

// ─── Private helper widgets ───────────────────────────────────

/// A tiny circular icon button used in the room toolbar.
class _MiniControl extends StatefulWidget {
  const _MiniControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  State<_MiniControl> createState() => _MiniControlState();
}

class _MiniControlState extends State<_MiniControl> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTheme.durationHover,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
              borderRadius: AppTheme.radiusSmall,
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.color ?? AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Voice mic button with connection status indicator.
class _VoiceControlButton extends StatelessWidget {
  const _VoiceControlButton({
    required this.isMuted,
    required this.isConnected,
    this.error,
    this.onToggle,
  });

  final bool isMuted;
  final bool isConnected;
  final String? error;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: error ?? (isMuted ? '取消静音' : '静音'),
      child: GestureDetector(
        onTap: onToggle,
        child: MouseRegion(
          cursor: onToggle != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.cardActive,
              borderRadius: AppTheme.radiusSmall,
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Icon(
              isMuted ? Icons.mic_off : Icons.mic,
              size: 14,
              color: error != null
                  ? AppColors.error
                  : (isMuted ? AppColors.error : AppColors.success),
            ),
          ),
        ),
      ),
    );
  }
}

/// A styled chat message bubble.
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.sender,
    this.senderAvatarUrl,
    this.content,
    this.imageUrl,
  });

  final String sender;
  final String? senderAvatarUrl;
  final String? content;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            backgroundImage: senderAvatarUrl != null && senderAvatarUrl!.isNotEmpty
                ? CachedNetworkImageProvider(senderAvatarUrl!)
                : null,
            child: senderAvatarUrl == null || senderAvatarUrl!.isEmpty
                ? Text(
                    sender.isNotEmpty ? sender[0] : '?',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sender,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    )),
                const SizedBox(height: 2),
                if (content != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.cardHover,
                      borderRadius: AppTheme.radiusBubble,
                    ),
                    child: Text(content!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        )),
                  ),
                if (imageUrl != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 300,
                      maxHeight: 200,
                    ),
                    child: ClipRRect(
                      borderRadius: AppTheme.radiusStandard,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl!,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const SizedBox(
                          width: 120,
                          height: 80,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (context, url, error) => SizedBox(
                          width: 120,
                          height: 80,
                          child: Center(child: Icon(Icons.broken_image, color: AppColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

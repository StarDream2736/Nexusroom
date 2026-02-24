import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../../core/models/livekit_models.dart';
import '../../../../core/network/livekit_service.dart';
import '../../../../core/network/stream_player.dart';
import '../../../../core/network/ws_service.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../vlan/presentation/widgets/vlan_panel.dart';
import '../providers/messages_provider.dart';
import '../providers/room_detail_provider.dart';

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
  List<IngressModel> _ingresses = [];
  IngressModel? _selectedIngress;
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
  WsService? _wsService;
  LiveKitService? _livekitService;

  int get _roomId => int.parse(widget.roomId);

  @override
  void initState() {
    super.initState();
    _wsService = ref.read(wsServiceProvider);
    _livekitService = ref.read(livekitServiceProvider);
    _wsService!.joinRoom(_roomId);
    ref.read(messageRepositoryProvider).syncLatest(_roomId);

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

    // 语音状态更新（可用于更新成员静音状态 UI）
    _voiceStateSub = _wsService!.on('voice.state_update').listen((payload) {
      // TODO: 更新成员列表中的静音状态图标
      // payload: { user_id, room_id, muted }
    });

    _connectLiveKit();
    _loadIngresses();

    // StreamPlayer listeners
    _videoTrackSub = _streamPlayer.videoTrackStream.listen((track) {
      if (mounted) setState(() => _streamVideoTrack = track);
    });
    _streamStatusSub = _streamPlayer.statusStream.listen((status) {
      if (mounted) setState(() => _streamStatus = status);
    });
  }

  Future<void> _loadIngresses() async {
    try {
      final list =
          await ref.read(roomRepositoryProvider).listIngresses(_roomId);
      if (mounted) setState(() => _ingresses = list);
    } catch (_) {}
  }

  Future<void> _connectLiveKit() async {
    try {
      final tokenResult =
          await ref.read(roomRepositoryProvider).getLiveKitToken(_roomId);
      debugPrint('[LiveKit] Voice room URL: ${tokenResult.url}');

      // 监听连接状态变化
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

      // 连接语音房间（不再监听 ingress 参与者）
      await _livekitService!.connect(tokenResult.url, tokenResult.token);

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
    _wsService?.leaveRoom(_roomId);
    _livekitService?.disconnect();
    _messageController.dispose();
    super.dispose();
  }

  void _toggleMute() async {
    final newMuted = !_isMuted;
    await _livekitService?.setMicrophoneEnabled(!newMuted);
    _wsService?.sendVoiceMute(
      roomId: _roomId,
      muted: newMuted,
    );
    setState(() => _isMuted = newMuted);
  }

  /// 打开直播流（连接独立的直播 LiveKit 房间）
  Future<void> _selectStream(IngressModel ingress) async {
    if (_selectedIngress?.id == ingress.id) return;

    // 断开之前的直播连接
    await _streamPlayer.disconnect();

    setState(() {
      _selectedIngress = ingress;
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
      _selectedIngress = null;
      _streamVideoTrack = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomDetailProvider(_roomId));
    final messagesAsync = ref.watch(messagesStreamProvider(_roomId));
    final baseUrl = ref.watch(appSettingsProvider).value?.serverUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(roomAsync.value?.name ?? '房间'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              context.push('/rooms/${widget.roomId}/settings');
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧边栏 - 直播列表
          Container(
            width: 220,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade800),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '直播列表',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Ingress 推流列表（来自 API）
                if (_ingresses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('暂无直播', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  ...(_ingresses.map((ingress) => ListTile(
                        leading: Icon(
                          Icons.videocam,
                          color: _selectedIngress?.id == ingress.id
                              ? Colors.red
                              : Colors.grey,
                        ),
                        title: Text(
                          ingress.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        dense: true,
                        selected: _selectedIngress?.id == ingress.id,
                        onTap: () => _selectStream(ingress),
                      ))),

                // 刷新按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextButton.icon(
                    onPressed: _loadIngresses,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('刷新', style: TextStyle(fontSize: 12)),
                  ),
                ),

                const Divider(),

                // 房间设置入口
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('房间设置'),
                  dense: true,
                  onTap: () {
                    context.push('/rooms/${widget.roomId}/settings');
                  },
                ),

                const Spacer(),

                // 底部控制栏
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade800),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                        color: _isMuted ? Colors.red : Colors.green,
                        tooltip: _isMuted ? '取消静音' : '静音',
                        onPressed: _livekitConnected ? _toggleMute : null,
                      ),
                      if (_livekitConnected)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.circle, color: Colors.green, size: 8),
                        )
                      else if (_livekitError != null)
                        Flexible(
                          child: Tooltip(
                            message: _livekitError!,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.circle, color: Colors.red, size: 8),
                            ),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: SizedBox(
                            width: 10, height: 10,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 主内容区
          Expanded(
            child: Column(
              children: [
                // 主视窗
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildMainVideoView(),
                  ),
                ),

                // 消息区域
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade800),
                      ),
                    ),
                    child: Column(
                      children: [
                        // 消息列表
                        Expanded(
                          child: messagesAsync.when(
                            data: (messages) {
                              if (messages.isEmpty) {
                                return const Center(child: Text('暂无消息'));
                              }
                              return ListView.builder(
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final sender = message.senderNickname ??
                                      '用户${message.senderId}';
                                  return ListTile(
                                    dense: true,
                                    title: Text(sender),
                                    subtitle: message.type == 'image'
                                        ? Image.network(
                                            _resolveUrl(baseUrl, message.content),
                                            height: 120,
                                            fit: BoxFit.cover,
                                          )
                                        : Text(message.content),
                                  );
                                },
                              );
                            },
                            loading: () =>
                                const Center(child: CircularProgressIndicator()),
                            error: (error, _) =>
                                Center(child: Text('消息加载失败: $error')),
                          ),
                        ),

                        // 输入框
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.image),
                                onPressed: _sendImage,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  decoration: InputDecoration(
                                    hintText: '输入消息...',
                                    filled: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: _sendMessage,
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

          // 右侧栏 - 在线成员
          Container(
            width: 200,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.grey.shade800),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '在线成员',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                roomAsync.when(
                  data: (room) {
                    if (room.members.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('暂无成员'),
                      );
                    }
                    return Expanded(
                      child: ListView.builder(
                        itemCount: room.members.length,
                        itemBuilder: (context, index) {
                          final member = room.members[index];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              child: Text(
                                member.nickname.isNotEmpty
                                    ? member.nickname[0]
                                    : '?',
                              ),
                            ),
                            title: Text(member.nickname,
                                style: const TextStyle(fontSize: 14)),
                            trailing: const Icon(Icons.mic, size: 16, color: Colors.green),
                            dense: true,
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('成员加载失败: $error'),
                  ),
                ),

                const Divider(),

                // VLAN 面板
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: VlanPanel(roomId: widget.roomId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainVideoView() {
    if (_selectedIngress == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.live_tv, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('点击左侧直播流开始观看',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

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
              const CircularProgressIndicator(),
            if (_streamStatus == StreamPlayerStatus.error)
              const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(statusText, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            TextButton(onPressed: _closeStream, child: const Text('关闭')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: lk.VideoTrackRenderer(_streamVideoTrack!),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            onPressed: _closeStream,
          ),
        ),
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _selectedIngress!.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/app_providers.dart';
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
  bool _vlanEnabled = false;

  int get _roomId => int.parse(widget.roomId);

  @override
  void initState() {
    super.initState();
    // 直接在 initState 中加入房间（无需 addPostFrameCallback）
    ref.read(wsServiceProvider).joinRoom(_roomId);
    ref.read(messageRepositoryProvider).syncLatest(_roomId);
  }

  @override
  void dispose() {
    ref.read(wsServiceProvider).leaveRoom(_roomId);
    _messageController.dispose();
    super.dispose();
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
              // TODO: 打开房间设置
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.videocam, color: Colors.red),
                  title: Text('OBS主流'),
                  dense: true,
                ),
                const Divider(),

                // 房间设置入口
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('房间设置'),
                  dense: true,
                  onTap: () {
                    // TODO: 打开房间设置
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
                        onPressed: () {
                          setState(() => _isMuted = !_isMuted);
                          // TODO: 切换麦克风状态
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                            _vlanEnabled ? Icons.vpn_lock : Icons.vpn_key_outlined),
                        color: _vlanEnabled ? Colors.green : null,
                        onPressed: () {
                          setState(() => _vlanEnabled = !_vlanEnabled);
                          // TODO: 切换 VLAN
                        },
                      ),
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
                    child: const Center(
                      child: Text('点击直播流开始观看'),
                    ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
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

                // VLAN 状态
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VLAN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _vlanEnabled ? Icons.check_circle : Icons.cancel,
                            color: _vlanEnabled ? Colors.green : Colors.grey,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _vlanEnabled ? '已开启' : '未开启',
                            style: TextStyle(
                              color: _vlanEnabled ? Colors.green : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (_vlanEnabled) ...[
                        const SizedBox(height: 4),
                        const Text(
                          '10.0.8.5',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
          await ref.read(fileRepositoryProvider).uploadFile(file.path);
      ref.read(wsServiceProvider).sendChat(
            roomId: _roomId,
            type: 'image',
            content: uploaded.url,
            meta: {
              'file_id': uploaded.fileId,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/livekit_models.dart';
import '../../../../core/providers/app_providers.dart';

class RoomSettingsPage extends ConsumerStatefulWidget {
  final String roomId;

  const RoomSettingsPage({super.key, required this.roomId});

  @override
  ConsumerState<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends ConsumerState<RoomSettingsPage> {
  int get _roomId => int.parse(widget.roomId);
  List<IngressModel> _ingresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIngresses();
  }

  Future<void> _loadIngresses() async {
    try {
      final list =
          await ref.read(roomRepositoryProvider).listIngresses(_roomId);
      if (mounted) {
        setState(() {
          _ingresses = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createIngress() async {
    final labelController = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建推流入口'),
        content: TextField(
          controller: labelController,
          decoration: const InputDecoration(
            labelText: '推流标签',
            hintText: '例如: OBS主推流',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, labelController.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (label == null || label.trim().isEmpty) return;

    try {
      await ref
          .read(roomRepositoryProvider)
          .createIngress(_roomId, label.trim());
      _loadIngresses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteIngress(IngressModel ingress) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除推流入口 "${ingress.label}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(roomRepositoryProvider)
          .deleteIngress(_roomId, ingress.id);
      _loadIngresses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('房间设置'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 推流管理
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '推流管理',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ElevatedButton.icon(
                        onPressed: _createIngress,
                        icon: const Icon(Icons.add),
                        label: const Text('创建推流入口'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_ingresses.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('暂无推流入口，点击上方按钮创建'),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: _ingresses.length,
                        itemBuilder: (context, index) {
                          final ingress = _ingresses[index];
                          return _IngressCard(
                            ingress: ingress,
                            onDelete: () => _deleteIngress(ingress),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _IngressCard extends StatelessWidget {
  final IngressModel ingress;
  final VoidCallback onDelete;

  const _IngressCard({required this.ingress, required this.onDelete});

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      ingress.isActive ? Icons.circle : Icons.circle_outlined,
                      size: 12,
                      color: ingress.isActive ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ingress.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CopyableField(
              label: '推流服务器 (Server)',
              value: ingress.rtmpUrl,
              onCopy: () =>
                  _copyToClipboard(context, ingress.rtmpUrl, '推流地址'),
            ),
            const SizedBox(height: 8),
            _CopyableField(
              label: '推流密钥 (Stream Key)',
              value: ingress.streamKey,
              onCopy: () =>
                  _copyToClipboard(context, ingress.streamKey, '推流密钥'),
              obscure: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyableField extends StatefulWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool obscure;

  const _CopyableField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.obscure = false,
  });

  @override
  State<_CopyableField> createState() => _CopyableFieldState();
}

class _CopyableFieldState extends State<_CopyableField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final displayValue =
        widget.obscure && !_revealed ? '••••••••••••' : widget.value;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                displayValue,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (widget.obscure)
          IconButton(
            icon: Icon(
                _revealed ? Icons.visibility_off : Icons.visibility,
                size: 18),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: widget.onCopy,
        ),
      ],
    );
  }
}

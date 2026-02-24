import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/native/wireguard_service.dart';
import '../../../../core/providers/app_providers.dart';

/// VLAN 面板 — 嵌入房间右侧边栏
class VlanPanel extends ConsumerStatefulWidget {
  const VlanPanel({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<VlanPanel> createState() => _VlanPanelState();
}

class _VlanPanelState extends ConsumerState<VlanPanel> {
  bool _isEnabled = false;
  bool _isLoading = false;
  String? _assignedIP;
  List<Map<String, dynamic>> _peers = [];
  StreamSubscription? _peerUpdateSub;

  @override
  void initState() {
    super.initState();
    _listenPeerUpdates();
  }

  void _listenPeerUpdates() {
    final ws = ref.read(wsServiceProvider);
    _peerUpdateSub = ws.on('vlan.peer_update').listen((event) {
      _loadPeers();
    });
  }

  Future<void> _toggleVlan() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      if (_isEnabled) {
        await _leaveVlan();
      } else {
        await _joinVlan();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('VLAN 操作失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinVlan() async {
    final wgService = ref.read(wireguardServiceProvider);
    final vlanRepo = ref.read(vlanRepositoryProvider);

    // 1. 生成 WireGuard 密钥对
    final keyPair = await wgService.generateKeyPair();

    // 2. 调用 API 注册 Peer
    final result = await vlanRepo.join(widget.roomId, keyPair.publicKey);

    final assignedIP = result['assigned_ip'] as String;
    final serverPublicKey = result['server_public_key'] as String? ?? '';
    final serverEndpoint = result['server_endpoint'] as String? ?? '';
    final dns = result['dns'] as String? ?? '';

    // 3. 启动 WireGuard 隧道（通过 Platform Channel）
    // 注意：如果 native 层未实现，这里会抛出异常
    // 在实际部署中需要编译 wireguard-go native 模块
    try {
      await wgService.startTunnel(
        _buildWgConfig(
          assignedIP: assignedIP,
          privateKey: keyPair.privateKey,
          serverPublicKey: serverPublicKey,
          serverEndpoint: serverEndpoint,
          dns: dns,
        ),
      );
    } catch (_) {
      // 即使隧道启动失败，也记录 IP（API 已成功注册）
    }

    setState(() {
      _isEnabled = true;
      _assignedIP = assignedIP;
    });

    await _loadPeers();
  }

  Future<void> _leaveVlan() async {
    final wgService = ref.read(wireguardServiceProvider);
    final vlanRepo = ref.read(vlanRepositoryProvider);

    await wgService.stopTunnel();
    await vlanRepo.leave(widget.roomId);

    setState(() {
      _isEnabled = false;
      _assignedIP = null;
      _peers = [];
    });
  }

  Future<void> _loadPeers() async {
    try {
      final vlanRepo = ref.read(vlanRepositoryProvider);
      final peers = await vlanRepo.getPeers(widget.roomId);
      if (!mounted) return;
      setState(() => _peers = peers);
    } catch (_) {}
  }

  WgConfig _buildWgConfig({
    required String assignedIP,
    required String privateKey,
    required String serverPublicKey,
    required String serverEndpoint,
    required String dns,
  }) {
    return WgConfig(
      assignedIP: assignedIP,
      privateKey: privateKey,
      serverPublicKey: serverPublicKey,
      serverEndpoint: serverEndpoint,
      dns: dns,
    );
  }

  @override
  void dispose() {
    _peerUpdateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VLAN 开关
        Row(
          children: [
            const Icon(Icons.lan, size: 16),
            const SizedBox(width: 4),
            const Text('VLAN', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: _isEnabled,
                onChanged: (_) => _toggleVlan(),
              ),
          ],
        ),

        if (_isEnabled && _assignedIP != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _assignedIP!.split('/').first));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('虚拟 IP 已复制')),
              );
            },
            child: Text(
              '虚拟 IP: ${_assignedIP!.split('/').first}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Peer 列表
          if (_peers.isNotEmpty) ...[
            Text('成员', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            ..._peers.map((p) {
              final ip = (p['assigned_ip'] as String? ?? '').split('/').first;
              final nickname = p['nickname'] as String? ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.computer, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$nickname ($ip)',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}

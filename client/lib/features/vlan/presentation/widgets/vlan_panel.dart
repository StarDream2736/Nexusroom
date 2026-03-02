import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
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

  @override
  void didUpdateWidget(covariant VlanPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId && _isEnabled) {
      // 房间切换时自动离开旧房间的 VLAN（使用旧 roomId）
      debugPrint('[VLAN] Room changed ${oldWidget.roomId} -> ${widget.roomId}, auto-leaving');
      _leaveVlan(roomIdOverride: oldWidget.roomId);
    }
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
    } on WgHelperNotFoundException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WireGuard 组件缺失，请确认 nexusroom-wg.exe 和 wintun.dll 已部署'),
          duration: Duration(seconds: 5),
        ),
      );
    } on WgException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('VLAN 操作失败: ${e.message}')),
      );
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

    final keyPair = await wgService.generateKeyPair();
    final result = await vlanRepo.join(widget.roomId, keyPair.publicKey);

    final assignedIP = result['assigned_ip'] as String;
    final serverPublicKey = result['server_public_key'] as String? ?? '';
    final serverEndpoint = result['server_endpoint'] as String? ?? '';
    final dns = result['dns'] as String? ?? '';

    // Start the tunnel — let errors propagate to _toggleVlan for user display
    await wgService.startTunnel(
      _buildWgConfig(
        assignedIP: assignedIP,
        privateKey: keyPair.privateKey,
        serverPublicKey: serverPublicKey,
        serverEndpoint: serverEndpoint,
        dns: dns,
      ),
    );

    // Only set enabled state if tunnel started successfully
    setState(() {
      _isEnabled = true;
      _assignedIP = assignedIP;
    });

    // Peer list load is best-effort — don't let it fail the VLAN join
    unawaited(_loadPeers());
  }

  Future<void> _leaveVlan({String? roomIdOverride}) async {
    final leaveRoomId = roomIdOverride ?? widget.roomId;
    final wgService = ref.read(wireguardServiceProvider);
    final vlanRepo = ref.read(vlanRepositoryProvider);

    // Always stop the local tunnel and reset UI, even if the server call fails
    await wgService.stopTunnel();
    setState(() {
      _isEnabled = false;
      _assignedIP = null;
      _peers = [];
    });

    // Best-effort server-side unregister — report but don't block
    try {
      await vlanRepo.leave(leaveRoomId);
    } catch (e) {
      debugPrint('[VLAN] Leave API failed (local tunnel already stopped): $e');
    }
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
      address: assignedIP,
      privateKey: privateKey,
      serverPublicKey: serverPublicKey,
      serverEndpoint: serverEndpoint,
      dns: dns,
    );
  }

  @override
  void dispose() {
    _peerUpdateSub?.cancel();
    // 面板卸载时自动离开 VLAN（兜底，主逻辑在 AppShell._syncRoom）
    if (_isEnabled) {
      _leaveVlan();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── VLAN toggle row ──────────────────────────────
        Row(
          children: [
            Icon(Icons.lan, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('VLAN',
                style: TextStyle(
                    fontSize: AppTypography.sizeBody,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const Spacer(),
            if (_isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              CupertinoSwitch(
                value: _isEnabled,
                activeColor: AppColors.accent,
                onChanged: (_) => _toggleVlan(),
              ),
          ],
        ),

        if (_isEnabled && _assignedIP != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: _assignedIP!.split('/').first));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('虚拟 IP 已复制')),
              );
            },
            child: Text(
              '虚拟 IP: ${_assignedIP!.split('/').first}',
              style: TextStyle(
                  fontSize: AppTypography.sizeCaption,
                  color: AppColors.success),
            ),
          ),
          const SizedBox(height: 8),

          // ─── Peer list ──────────────────────────────────
          if (_peers.isNotEmpty) ...[
            Text('成员',
                style: TextStyle(
                    fontSize: AppTypography.sizeMini,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted)),
            const SizedBox(height: 4),
            ..._peers.map((p) {
              final ip =
                  (p['assigned_ip'] as String? ?? '').split('/').first;
              final nickname = p['nickname'] as String? ?? '';
              return _PeerRow(nickname: nickname, ip: ip);
            }),
          ],
        ],
      ],
    );
  }
}

class _PeerRow extends StatefulWidget {
  final String nickname;
  final String ip;
  const _PeerRow({required this.nickname, required this.ip});
  @override
  State<_PeerRow> createState() => _PeerRowState();
}

class _PeerRowState extends State<_PeerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.hoverOverlay : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(Icons.computer, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${widget.nickname} (${widget.ip})',
                style: TextStyle(
                    fontSize: AppTypography.sizeMini,
                    color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

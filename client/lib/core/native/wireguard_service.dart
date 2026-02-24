import 'package:flutter/services.dart';

/// WireGuard 集成 — Platform Channel 方式调用 native wireguard-go
class WireGuardService {
  static const _channel = MethodChannel('nexusroom/wireguard');

  bool _isConnected = false;
  String? _assignedIP;

  bool get isConnected => _isConnected;
  String? get assignedIP => _assignedIP;

  /// 生成 WireGuard 密钥对（由 native 层完成）
  Future<WgKeyPair> generateKeyPair() async {
    try {
      final result = await _channel.invokeMethod<Map>('generateKeyPair');
      if (result != null) {
        return WgKeyPair(
          publicKey: result['public_key'] as String,
          privateKey: result['private_key'] as String,
        );
      }
    } on PlatformException {
      // Platform Channel 未实现时的 fallback
    }
    // Fallback: 使用 Dart 端生成（需要额外库）
    // 这里先抛异常提示未实现
    throw UnimplementedError(
      'WireGuard native 层未实现。请确保安装了 wintun 驱动并编译了 native 模块。',
    );
  }

  /// 启动 WireGuard 隧道
  Future<void> startTunnel(WgConfig config) async {
    try {
      await _channel.invokeMethod('startTunnel', config.toMap());
      _isConnected = true;
      _assignedIP = config.assignedIP;
    } on PlatformException catch (e) {
      throw Exception('启动 WireGuard 隧道失败: ${e.message}');
    }
  }

  /// 停止 WireGuard 隧道
  Future<void> stopTunnel() async {
    try {
      await _channel.invokeMethod('stopTunnel');
    } on PlatformException {
      // ignore
    }
    _isConnected = false;
    _assignedIP = null;
  }

  void dispose() {
    if (_isConnected) {
      stopTunnel();
    }
  }
}

class WgKeyPair {
  const WgKeyPair({required this.publicKey, required this.privateKey});
  final String publicKey;
  final String privateKey;
}

class WgConfig {
  const WgConfig({
    required this.assignedIP,
    required this.privateKey,
    required this.serverPublicKey,
    required this.serverEndpoint,
    required this.dns,
    this.peers = const [],
  });

  final String assignedIP;
  final String privateKey;
  final String serverPublicKey;
  final String serverEndpoint;
  final String dns;
  final List<WgPeerConfig> peers;

  Map<String, dynamic> toMap() => {
        'assigned_ip': assignedIP,
        'private_key': privateKey,
        'server_public_key': serverPublicKey,
        'server_endpoint': serverEndpoint,
        'dns': dns,
        'peers': peers.map((p) => p.toMap()).toList(),
      };
}

class WgPeerConfig {
  const WgPeerConfig({
    required this.publicKey,
    required this.allowedIPs,
  });

  final String publicKey;
  final String allowedIPs;

  Map<String, dynamic> toMap() => {
        'public_key': publicKey,
        'allowed_ips': allowedIPs,
      };
}

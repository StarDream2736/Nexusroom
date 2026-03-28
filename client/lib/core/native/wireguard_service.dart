import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// WireGuard integration via external helper process (nexusroom-wg.exe).
///
/// The helper binary lives next to the main Flutter executable and requires
/// Administrator privileges.
///
/// Communication:
///   genkey → Process.run, JSON on stdout (no elevation needed)
///   up     → Elevated via PowerShell Start-Process -Verb RunAs.
///            IPC over TCP 127.0.0.1 (stdin/stdout cannot cross UAC boundary).
class WireGuardService {
  Socket? _helperSocket;
  ServerSocket? _ipcServer;
  StreamSubscription? _helperSub;
  bool _isConnected = false;
  String? _assignedIP;

  bool get isConnected => _isConnected;
  String? get assignedIP => _assignedIP;

  /// Locate the helper binary next to the running Flutter exe.
  String get _helperPath {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(exeDir, 'nexusroom-wg.exe');
  }

  // ─── Key generation ──────────────────────────────────────────────────────

  /// Generate a WireGuard key pair by calling `nexusroom-wg.exe genkey`.
  Future<WgKeyPair> generateKeyPair() async {
    final helper = _helperPath;
    if (!File(helper).existsSync()) {
      throw WgHelperNotFoundException(helper);
    }

    final result = await Process.run(helper, ['genkey']);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw WgException(
          'Key generation failed (exit ${result.exitCode}): $stderr');
    }

    final stdout = (result.stdout as String).trim();
    // May contain multiple lines; take the last valid JSON line.
    final lines = stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty);
    for (final line in lines.toList().reversed) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        if (msg['action'] == 'genkey' && msg['data'] != null) {
          final data = msg['data'] as Map<String, dynamic>;
          return WgKeyPair(
            publicKey: data['public_key'] as String,
            privateKey: data['private_key'] as String,
          );
        }
        if (msg['action'] == 'error') {
          throw WgException(msg['error'] as String? ?? 'unknown error');
        }
      } catch (e) {
        if (e is WgException) rethrow;
        // skip non-JSON lines (log output)
      }
    }
    throw WgException('Unexpected helper output: $stdout');
  }

  // ─── Tunnel lifecycle ────────────────────────────────────────────────────

  /// Start a WireGuard tunnel.  Launches the helper with UAC elevation
  /// via PowerShell, communicating over a local TCP socket.
  Future<void> startTunnel(WgConfig config) async {
    // If already connected, tear down first
    if (_helperSocket != null) {
      await stopTunnel();
    }

    final helper = _helperPath;
    if (!File(helper).existsSync()) {
      throw WgHelperNotFoundException(helper);
    }

    // 1. Start a local TCP server for IPC with the elevated helper
    _ipcServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = _ipcServer!.port;
    debugPrint('[WG] IPC server on 127.0.0.1:$port');

    // 2. Launch helper elevated via PowerShell Start-Process -Verb RunAs
    final escapedPath = helper.replaceAll("'", "''");
    try {
      await Process.start('powershell', [
        '-WindowStyle', 'Hidden',
        '-Command',
        "Start-Process -FilePath '$escapedPath' -ArgumentList 'up --port $port' -Verb RunAs -WindowStyle Hidden",
      ]);
    } catch (e) {
      await _ipcServer?.close();
      _ipcServer = null;
      throw WgException('Failed to launch helper: $e');
    }

    // 3. Wait for the elevated helper to connect (includes UAC prompt time)
    Socket socket;
    try {
      socket = await _ipcServer!.first.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      await _ipcServer?.close();
      _ipcServer = null;
      throw WgException('Helper did not connect (UAC denied or timeout)');
    } catch (e) {
      await _ipcServer?.close();
      _ipcServer = null;
      throw WgException('IPC accept failed: $e');
    }
    _helperSocket = socket;
    debugPrint('[WG] Helper connected via TCP');

    // 4. Send the tunnel config
    final configMap = config.toMap();
    debugPrint('[WG] -> config: address=${config.address} '
        'endpoint=${config.serverEndpoint} '
        'peers=${(configMap['peers'] as List).length}');
    socket.writeln(jsonEncode(configMap));
    await socket.flush();

    // 5. Wait for "up" confirmation
    final completer = Completer<void>();
    _helperSub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        debugPrint('[WG] <- $line');
        try {
          final msg = jsonDecode(line) as Map<String, dynamic>;
          if (msg['action'] == 'up' && !completer.isCompleted) {
            completer.complete();
          } else if (msg['action'] == 'error' && !completer.isCompleted) {
            completer.completeError(
                WgException(msg['error'] as String? ?? 'tunnel up failed'));
          }
        } catch (_) {
          // skip non-JSON log lines
        }
      },
      onDone: () {
        debugPrint('[WG] Helper disconnected');
        if (!completer.isCompleted) {
          completer.completeError(
              WgException('Helper disconnected before tunnel was up'));
        }
        _cleanup();
      },
      onError: (e) {
        debugPrint('[WG] Socket error: $e');
        if (!completer.isCompleted) {
          completer.completeError(WgException('IPC error: $e'));
        }
        _cleanup();
      },
    );

    try {
      await completer.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await stopTunnel();
      throw WgException('Tunnel startup timed out (no response from helper)');
    } on WgException {
      await stopTunnel();
      rethrow;
    } catch (e) {
      await stopTunnel();
      throw WgException('Tunnel startup error: $e');
    }

    _isConnected = true;
    _assignedIP = config.address;
  }

  /// Stop the tunnel by sending {"action":"down"} over TCP.
  Future<void> stopTunnel() async {
    final socket = _helperSocket;
    _helperSocket = null;
    _isConnected = false;
    _assignedIP = null;

    if (socket != null) {
      try {
        socket.writeln(jsonEncode({'action': 'down'}));
        await socket.flush();
        // Give helper a moment to clean up
        await Future.delayed(const Duration(milliseconds: 500));
        await socket.close();
      } catch (e) {
        debugPrint('[WG] Error sending down: $e');
        try {
          socket.destroy();
        } catch (_) {}
      }
    }

    await _helperSub?.cancel();
    _helperSub = null;

    await _ipcServer?.close();
    _ipcServer = null;
  }

  void _cleanup() {
    _helperSocket = null;
    _isConnected = false;
    _assignedIP = null;
    _helperSub?.cancel();
    _helperSub = null;
    _ipcServer?.close();
    _ipcServer = null;
  }

  void dispose() {
    if (_isConnected) {
      stopTunnel();
    }
  }
}

// ─── Data classes ──────────────────────────────────────────────────────────

class WgKeyPair {
  const WgKeyPair({required this.publicKey, required this.privateKey});
  final String publicKey;
  final String privateKey;
}

class WgConfig {
  const WgConfig({
    required this.address,
    required this.privateKey,
    required this.serverPublicKey,
    required this.serverEndpoint,
    this.dns = '',
    this.peers = const [],
  });

  /// CIDR, e.g. "10.0.8.2/24"
  final String address;
  final String privateKey;
  final String serverPublicKey;
  final String serverEndpoint;
  final String dns;
  final List<WgPeerConfig> peers;

  Map<String, dynamic> toMap() {
    // Build the peer list: always include the server as the first peer
    final allPeers = <Map<String, dynamic>>[];

    if (serverPublicKey.isNotEmpty && serverEndpoint.isNotEmpty) {
      // Server peer: route the entire VLAN subnet through it
      final subnet = _subnetFromAddress(address);
      allPeers.add({
        'public_key': serverPublicKey,
        'endpoint': serverEndpoint,
        'allowed_ips': subnet,
        'persistent_keepalive': 25,
      });
    }

    // Additional peers (other room members — future P2P)
    for (final p in peers) {
      allPeers.add(p.toMap());
    }

    return {
      'interface_name': 'NexusRoom0',
      'private_key': privateKey,
      'address': address,
      'dns': dns,
      'peers': allPeers,
    };
  }

  /// Derive subnet CIDR from assigned address, e.g. "10.0.8.2/24" → "10.0.8.0/24"
  static String _subnetFromAddress(String addr) {
    final parts = addr.split('/');
    if (parts.length != 2) return addr;
    final mask = int.tryParse(parts[1]) ?? 24;
    final octets = parts[0].split('.');
    if (octets.length != 4) return addr;
    if (mask == 24) {
      return '${octets[0]}.${octets[1]}.${octets[2]}.0/$mask';
    }
    return addr;
  }
}

class WgPeerConfig {
  const WgPeerConfig({
    required this.publicKey,
    required this.allowedIPs,
    this.endpoint,
  });

  final String publicKey;
  final String allowedIPs;
  final String? endpoint;

  Map<String, dynamic> toMap() => {
        'public_key': publicKey,
        'allowed_ips': allowedIPs,
        if (endpoint != null) 'endpoint': endpoint,
      };
}

// ─── Exceptions ────────────────────────────────────────────────────────────

class WgException implements Exception {
  WgException(this.message);
  final String message;
  @override
  String toString() => 'WgException: $message';
}

class WgHelperNotFoundException extends WgException {
  WgHelperNotFoundException(String path)
      : super('WireGuard helper not found at: $path');
}

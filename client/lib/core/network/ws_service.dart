import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../db/app_database.dart';
import '../models/message_models.dart';

/// WebSocket 事件类型
class WsEvent {
  const WsEvent({required this.event, this.payload});
  final String event;
  final Map<String, dynamic>? payload;
}

/// 连接状态
enum WsConnectionState { disconnected, connecting, connected }

class WsService {
  WsService({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer; // 连接超时看门狗
  String? _serverUrl;
  String? _token;
  bool _shouldReconnect = false;

  int _reconnectAttempts = 0;
  WsConnectionState _state = WsConnectionState.disconnected;

  /// 客户端当前加入的房间集合，用于断线重连后自动重新 join
  final Set<int> _joinedRooms = {};

  /// 事件总线：UI 层可订阅不同事件
  final _eventController = StreamController<WsEvent>.broadcast();
  Stream<WsEvent> get eventStream => _eventController.stream;

  /// 连接状态流
  final _stateController = StreamController<WsConnectionState>.broadcast();
  Stream<WsConnectionState> get stateStream => _stateController.stream;
  WsConnectionState get connectionState => _state;

  /// 便捷方法：监听指定事件
  Stream<Map<String, dynamic>> on(String eventName) {
    return _eventController.stream
        .where((e) => e.event == eventName)
        .map((e) => e.payload ?? {});
  }

  void _setState(WsConnectionState newState) {
    if (_state != newState) {
      debugPrint('[WsService] state: $_state → $newState');
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  void connect(String serverUrl, String token) {
    debugPrint('[WsService] connect() called  serverUrl=${serverUrl.length > 30 ? '${serverUrl.substring(0, 30)}...' : serverUrl}  token=${token.length > 15 ? '${token.substring(0, 15)}...' : token}  _channel=${_channel != null}  _state=$_state');

    if (_serverUrl == serverUrl && _token == token && _state == WsConnectionState.connected) {
      debugPrint('[WsService] connect() — already connected with same config, skip');
      return;
    }

    disconnect();
    _serverUrl = serverUrl;
    _token = token;
    _shouldReconnect = true;
    _open();
  }

  void _open() {
    if (_serverUrl == null || _token == null) {
      debugPrint('[WsService] _open() aborted — serverUrl or token is null');
      return;
    }

    // 释放旧资源
    _subscription?.cancel();
    _subscription = null;
    _connectTimeoutTimer?.cancel();

    final url = _buildWsUrl(_serverUrl!, _token!);
    debugPrint('[WsService] _open() connecting to $url');
    _setState(WsConnectionState.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      // 监听 stream（数据/错误/关闭）
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _handleDone,
        onError: _handleError,
      );

      // 关键：显式监控 ready future，检测握手失败
      channel.ready.then((_) {
        debugPrint('[WsService] WebSocket handshake complete (ready resolved)');
      }).catchError((error) {
        debugPrint('[WsService] WebSocket handshake FAILED (ready error): $error');
        // stream 的 onDone 应该也会触发，但作为安全网:
        _cleanupAndReconnect();
      });

      // 连接超时看门狗：10 秒内必须收到 connected 事件，否则强制重连
      _connectTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (_state == WsConnectionState.connecting) {
          debugPrint('[WsService] CONNECT TIMEOUT — no "connected" event in 10s, forcing reconnect');
          _cleanupAndReconnect();
        }
      });
    } catch (e, st) {
      debugPrint('[WsService] _open() SYNC EXCEPTION: $e\n$st');
      _channel = null;
      _setState(WsConnectionState.disconnected);
      if (_shouldReconnect) {
        _scheduleReconnect();
      }
    }
  }

  /// 清理当前连接并触发重连
  void _cleanupAndReconnect() {
    _connectTimeoutTimer?.cancel();
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _setState(WsConnectionState.disconnected);
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _handleDone() {
    debugPrint('[WsService] connection closed (onDone)  state=$_state');
    _connectTimeoutTimer?.cancel();
    _stopHeartbeat();
    _channel = null;
    _setState(WsConnectionState.disconnected);
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _handleError(Object error) {
    debugPrint('[WsService] connection error (onError): $error  state=$_state');
    _connectTimeoutTimer?.cancel();
    _stopHeartbeat();
    _channel = null;
    _setState(WsConnectionState.disconnected);
    // 同样调度重连作为安全网（_scheduleReconnect 内部有去重）
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    // 去重：如果重连定时器已在运行，不重复调度
    if (_reconnectTimer?.isActive ?? false) {
      debugPrint('[WsService] _scheduleReconnect() skipped — timer already active');
      return;
    }
    final delaySec = min(30, _reconnectAttempts < 5 ? (1 << _reconnectAttempts) : 30);
    _reconnectAttempts++;
    debugPrint('[WsService] scheduling reconnect in ${delaySec}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (_shouldReconnect && _serverUrl != null && _token != null) {
        _open();
      }
    });
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _reconnectAttempts = 0;
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    try { _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _joinedRooms.clear();
    _setState(WsConnectionState.disconnected);
    debugPrint('[WsService] disconnected');
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _stateController.close();
  }

  void joinRoom(int roomId) {
    _joinedRooms.add(roomId);
    debugPrint('[WsService] joinRoom($roomId)  state=$_state');
    sendEvent('room.join', roomId: roomId, payload: {});
  }

  void leaveRoom(int roomId) {
    _joinedRooms.remove(roomId);
    debugPrint('[WsService] leaveRoom($roomId)  state=$_state');
    sendEvent('room.leave', roomId: roomId, payload: {});
  }

  void sendChat({
    required int roomId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? meta,
  }) {
    debugPrint('[WsService] sendChat roomId=$roomId content="$content" state=$_state');
    sendEvent('chat.send', roomId: roomId, payload: {
      'type': type,
      'content': content,
      if (meta != null) 'meta': meta,
    });
  }

  void sendVoiceMute({required int roomId, required bool muted}) {
    sendEvent('voice.mute', roomId: roomId, payload: {
      'muted': muted,
    });
  }

  void sendEvent(String event, {int? roomId, Map<String, dynamic> payload = const {}}) {
    if (_channel == null || _state != WsConnectionState.connected) {
      debugPrint('[WsService] sendEvent($event) DROPPED — state=$_state channel=${_channel != null}');
      return;
    }
    final envelope = <String, dynamic>{
      'event': event,
      if (roomId != null) 'room_id': roomId,
      'payload': payload,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      _channel!.sink.add(jsonEncode(envelope));
    } catch (e) {
      debugPrint('[WsService] sendEvent($event) sink.add ERROR: $e');
    }
  }

  String _buildWsUrl(String serverUrl, String token) {
    // 移除尾部斜杠
    var base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    if (base.startsWith('https://')) {
      base = base.replaceFirst('https://', 'wss://');
    } else if (base.startsWith('http://')) {
      base = base.replaceFirst('http://', 'ws://');
    }
    return '$base/ws?token=$token';
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      sendEvent('heartbeat');
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _handleMessage(dynamic data) {
    if (data is! String) return;
    final decoded = jsonDecode(data) as Map<String, dynamic>;
    final event = decoded['event'] as String?;
    final payload = decoded['payload'] as Map<String, dynamic>?;

    if (event == null) return;

    debugPrint('[WsService] recv event=$event');

    // 收到 connected 事件后，标记为已连接，启动心跳
    if (event == 'connected') {
      _connectTimeoutTimer?.cancel();
      _reconnectAttempts = 0;
      _setState(WsConnectionState.connected);
      _startHeartbeat();

      debugPrint('[WsService] CONNECTED! Rejoining ${_joinedRooms.length} rooms: $_joinedRooms');
      // 断线重连后自动重新加入之前的房间
      for (final roomId in _joinedRooms) {
        sendEvent('room.join', roomId: roomId, payload: {});
      }
    }

    // 服务端返回 chat.error（通常因为 not_in_room），自动重新加入并提示
    if (event == 'chat.error' && payload != null) {
      debugPrint('[WsService] chat.error: $payload');
      final roomId = payload['room_id'] as int?;
      if (roomId != null && _joinedRooms.contains(roomId)) {
        sendEvent('room.join', roomId: roomId, payload: {});
      }
    }

    // 推送到事件总线
    if (!_eventController.isClosed) {
      _eventController.add(WsEvent(event: event, payload: payload));
    }

    // 处理 chat.message 写入本地数据库
    if (event == 'chat.message' && payload != null) {
      try {
        debugPrint('[WsService] chat.message payload=$payload');
        final message = MessageModel.fromWs(payload, serverUrl: _serverUrl ?? '');
        _db.messagesDao.upsertMessages([message.toCompanion()]);
        debugPrint('[WsService] chat.message written to DB, id=${message.id} roomId=${message.roomId}');
      } catch (e, st) {
        debugPrint('[WsService] chat.message PARSE/DB ERROR: $e\n$st');
      }
    }
  }
}

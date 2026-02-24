import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../db/app_database.dart';
import '../models/message_models.dart';

/// WebSocket 事件类型
class WsEvent {
  const WsEvent({required this.event, this.payload});
  final String event;
  final Map<String, dynamic>? payload;
}

class WsService {
  WsService({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  String? _serverUrl;
  String? _token;
  bool _shouldReconnect = false;

  int _reconnectAttempts = 0;

  /// 事件总线：UI 层可订阅不同事件
  final _eventController = StreamController<WsEvent>.broadcast();
  Stream<WsEvent> get eventStream => _eventController.stream;

  /// 便捷方法：监听指定事件
  Stream<Map<String, dynamic>> on(String eventName) {
    return _eventController.stream
        .where((e) => e.event == eventName)
        .map((e) => e.payload ?? {});
  }

  void connect(String serverUrl, String token) {
    if (_serverUrl == serverUrl && _token == token && _channel != null) {
      return;
    }

    disconnect();
    _serverUrl = serverUrl;
    _token = token;
    _shouldReconnect = true;
    _open();
  }

  void _open() {
    final url = _buildWsUrl(_serverUrl!, _token!);
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onDone: _handleDone,
      onError: _handleError,
    );
    // 心跳在收到 connected 事件后启动（见 _handleMessage）
  }

  void _handleDone() {
    _stopHeartbeat();
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _handleError(Object _) {
    _stopHeartbeat();
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // 指数退避重连：1s → 2s → 4s → 8s → … → 最大 30s
    final delaySec = _reconnectAttempts < 5
        ? (1 << _reconnectAttempts) // 1, 2, 4, 8, 16
        : 30;
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (_shouldReconnect && _serverUrl != null && _token != null) {
        _open();
      }
    });
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }

  void joinRoom(int roomId) {
    sendEvent('room.join', roomId: roomId, payload: {});
  }

  void leaveRoom(int roomId) {
    sendEvent('room.leave', roomId: roomId, payload: {});
  }

  void sendChat({
    required int roomId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? meta,
  }) {
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
    if (_channel == null) return;
    final envelope = <String, dynamic>{
      'event': event,
      if (roomId != null) 'room_id': roomId,
      'payload': payload,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    _channel!.sink.add(jsonEncode(envelope));
  }

  String _buildWsUrl(String serverUrl, String token) {
    var wsBase = serverUrl;
    if (wsBase.startsWith('https://')) {
      wsBase = wsBase.replaceFirst('https://', 'wss://');
    } else if (wsBase.startsWith('http://')) {
      wsBase = wsBase.replaceFirst('http://', 'ws://');
    }
    return '$wsBase/ws?token=$token';
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

    // 收到 connected 事件后启动心跳并重置重连计数器
    if (event == 'connected') {
      _reconnectAttempts = 0;
      _startHeartbeat();
    }

    // 推送到事件总线
    if (!_eventController.isClosed) {
      _eventController.add(WsEvent(event: event, payload: payload));
    }

    // 处理 chat.message 写入本地数据库
    if (event == 'chat.message' && payload != null) {
      final message = MessageModel.fromWs(payload);
      _db.messagesDao.upsertMessages([message.toCompanion()]);
    }
  }
}

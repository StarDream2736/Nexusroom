import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../db/app_database.dart';
import '../models/message_models.dart';

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
    _startHeartbeat();
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
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
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
  }

  void joinRoom(int roomId) {
    sendEvent('room.join', {'room_id': roomId});
  }

  void leaveRoom(int roomId) {
    sendEvent('room.leave', {'room_id': roomId});
  }

  void sendChat({
    required int roomId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? meta,
  }) {
    sendEvent('chat.send', {
      'room_id': roomId,
      'type': type,
      'content': content,
      if (meta != null) 'meta': meta,
    });
  }

  void sendEvent(String event, Map<String, dynamic> payload) {
    if (_channel == null) return;
    final envelope = {
      'event': event,
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
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      sendEvent('heartbeat', {});
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
    if (event == 'chat.message' && payload != null) {
      final message = MessageModel.fromWs(payload);
      _db.messagesDao.upsertMessages([message.toCompanion()]);
    }
  }
}

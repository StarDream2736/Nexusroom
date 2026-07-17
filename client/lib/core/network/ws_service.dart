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

class WsUnavailableException implements Exception {
  const WsUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatSendException implements Exception {
  const ChatSendException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

abstract interface class WsChannel {
  Stream<dynamic> get stream;
  StreamSink<dynamic> get sink;
  Future<void> get ready;
}

typedef WsChannelConnector = WsChannel Function(Uri uri);

class _WebSocketChannelAdapter implements WsChannel {
  _WebSocketChannelAdapter(Uri uri) : _channel = WebSocketChannel.connect(uri);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  StreamSink<dynamic> get sink => _channel.sink;
}

class WsService {
  WsService({required AppDatabase db, WsChannelConnector? connector})
      : _db = db,
        _connector = connector ?? _WebSocketChannelAdapter.new;

  final AppDatabase _db;
  final WsChannelConnector _connector;
  WsChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer; // 连接超时看门狗
  String? _serverUrl;
  String? _token;
  int? _accountUserId;
  List<Map<String, dynamic>> _rtcIceServers = const [];
  bool _shouldReconnect = false;
  int _connectionGeneration = 0;

  final Set<int> _confirmedRooms = {};
  final Map<int, Completer<void>> _roomJoinCompleters = {};
  final Map<String, Completer<void>> _pendingChatCompleters = {};
  int _messageSequence = 0;

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
  String? get serverUrl => _serverUrl;
  List<Map<String, dynamic>> get rtcIceServers =>
      List.unmodifiable(_rtcIceServers);

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

  void connect(String serverUrl, String token, {required int accountUserId}) {
    debugPrint(
        '[WsService] connect() called serverUrl=$serverUrl authenticated=${token.isNotEmpty} state=$_state');

    if (_serverUrl == serverUrl &&
        _token == token &&
        _accountUserId == accountUserId &&
        (_state == WsConnectionState.connected ||
            _state == WsConnectionState.connecting)) {
      debugPrint(
          '[WsService] connect() — same config & already connected/connecting, skip');
      return;
    }

    disconnect();
    _serverUrl = serverUrl;
    _token = token;
    _accountUserId = accountUserId;
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

    final generation = ++_connectionGeneration;
    try {
      final channel = _connector(Uri.parse(url));
      _channel = channel;

      // 监听 stream（数据/错误/关闭）
      _subscription = channel.stream.listen(
        (data) => _handleMessage(data, generation),
        onDone: () => _handleDone(generation),
        onError: (Object error) => _handleError(error, generation),
      );

      // 关键：显式监控 ready future，检测握手失败
      channel.ready.then((_) {
        if (generation != _connectionGeneration ||
            !identical(_channel, channel)) {
          return;
        }
        debugPrint('[WsService] WebSocket handshake complete (ready resolved)');
      }).catchError((error) {
        if (generation != _connectionGeneration ||
            !identical(_channel, channel)) {
          return;
        }
        debugPrint(
            '[WsService] WebSocket handshake FAILED (ready error): $error');
        // stream 的 onDone 应该也会触发，但作为安全网:
        _cleanupAndReconnect(generation);
      });

      // 连接超时看门狗：10 秒内必须收到 connected 事件，否则强制重连
      _connectTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (generation == _connectionGeneration &&
            _state == WsConnectionState.connecting) {
          debugPrint(
              '[WsService] CONNECT TIMEOUT — no "connected" event in 10s, forcing reconnect');
          _cleanupAndReconnect(generation);
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
  void _cleanupAndReconnect(int generation) {
    if (generation != _connectionGeneration) return;
    _connectTimeoutTimer?.cancel();
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _confirmedRooms.clear();
    _failPendingChats(const WsUnavailableException('连接已断开，请重试'));
    _setState(WsConnectionState.disconnected);
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _handleDone(int generation) {
    if (generation != _connectionGeneration) return;
    debugPrint('[WsService] connection closed (onDone)  state=$_state');
    _connectTimeoutTimer?.cancel();
    _stopHeartbeat();
    _channel = null;
    _confirmedRooms.clear();
    _failPendingChats(const WsUnavailableException('连接已断开，请重试'));
    _setState(WsConnectionState.disconnected);
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _handleError(Object error, int generation) {
    if (generation != _connectionGeneration) return;
    debugPrint('[WsService] connection error (onError): $error  state=$_state');
    _connectTimeoutTimer?.cancel();
    _stopHeartbeat();
    _channel = null;
    _confirmedRooms.clear();
    _failPendingChats(const WsUnavailableException('连接异常，请重试'));
    _setState(WsConnectionState.disconnected);
    // 同样调度重连作为安全网（_scheduleReconnect 内部有去重）
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    // 去重：如果重连定时器已在运行，不重复调度
    if (_reconnectTimer?.isActive ?? false) {
      debugPrint(
          '[WsService] _scheduleReconnect() skipped — timer already active');
      return;
    }
    final delaySec =
        min(30, _reconnectAttempts < 5 ? (1 << _reconnectAttempts) : 30);
    _reconnectAttempts++;
    debugPrint(
        '[WsService] scheduling reconnect in ${delaySec}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (_shouldReconnect && _serverUrl != null && _token != null) {
        _open();
      }
    });
  }

  void disconnect() {
    _connectionGeneration++;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _connectTimeoutTimer?.cancel();
    _reconnectAttempts = 0;
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _joinedRooms.clear();
    _confirmedRooms.clear();
    _failPendingChats(const WsUnavailableException('连接已关闭'));
    _failRoomJoins(const WsUnavailableException('连接已关闭'));
    _rtcIceServers = const [];
    _setState(WsConnectionState.disconnected);
    debugPrint('[WsService] disconnected');
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _stateController.close();
  }

  Future<void> joinRoom(int roomId) {
    _joinedRooms.add(roomId);
    debugPrint('[WsService] joinRoom($roomId)  state=$_state');
    return ensureRoomJoined(roomId);
  }

  Future<void> ensureRoomJoined(
    int roomId, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _joinedRooms.add(roomId);
    await _waitUntilConnected(timeout);
    if (_confirmedRooms.contains(roomId)) return;

    final completer =
        _roomJoinCompleters.putIfAbsent(roomId, Completer<void>.new);
    _requestRoomJoin(roomId);
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_roomJoinCompleters[roomId], completer)) {
        _roomJoinCompleters.remove(roomId);
      }
      throw const WsUnavailableException('加入房间超时，请检查网络后重试');
    }
  }

  void leaveRoom(int roomId) {
    _joinedRooms.remove(roomId);
    _confirmedRooms.remove(roomId);
    final pending = _roomJoinCompleters.remove(roomId);
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const WsUnavailableException('已离开房间'));
    }
    debugPrint('[WsService] leaveRoom($roomId)  state=$_state');
    sendEvent('room.leave', roomId: roomId, payload: {});
  }

  Future<void> sendChat({
    required int roomId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? meta,
  }) async {
    debugPrint(
        '[WsService] sendChat roomId=$roomId type=$type length=${content.length} state=$_state');
    for (var attempt = 0; attempt < 2; attempt++) {
      await ensureRoomJoined(roomId);
      try {
        await _sendChatOnce(
          roomId: roomId,
          content: content,
          type: type,
          meta: meta,
        );
        return;
      } on ChatSendException catch (error) {
        if (error.reason != 'not_in_room' || attempt > 0) rethrow;
        _confirmedRooms.remove(roomId);
      }
    }
  }

  bool sendVoiceMute({required int roomId, required bool muted}) {
    return sendEvent('voice.mute', roomId: roomId, payload: {
      'muted': muted,
    });
  }

  bool sendEvent(String event,
      {int? roomId, Map<String, dynamic> payload = const {}}) {
    if (_channel == null || _state != WsConnectionState.connected) {
      debugPrint(
          '[WsService] sendEvent($event) DROPPED — state=$_state channel=${_channel != null}');
      return false;
    }
    final envelope = <String, dynamic>{
      'event': event,
      if (roomId != null) 'room_id': roomId,
      'payload': payload,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      _channel!.sink.add(jsonEncode(envelope));
      return true;
    } catch (e) {
      debugPrint('[WsService] sendEvent($event) sink.add ERROR: $e');
      return false;
    }
  }

  Future<void> _sendChatOnce({
    required int roomId,
    required String content,
    required String type,
    Map<String, dynamic>? meta,
  }) async {
    final clientMessageId = _nextClientMessageId();
    final completer = Completer<void>();
    _pendingChatCompleters[clientMessageId] = completer;
    final sent = sendEvent('chat.send', roomId: roomId, payload: {
      'type': type,
      'content': content,
      'client_message_id': clientMessageId,
      if (meta != null) 'meta': meta,
    });
    if (!sent) {
      _pendingChatCompleters.remove(clientMessageId);
      throw const WsUnavailableException('当前未连接，消息未发送');
    }
    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const WsUnavailableException('消息发送超时，请重试');
    } finally {
      _pendingChatCompleters.remove(clientMessageId);
    }
  }

  String _nextClientMessageId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(1 << 32);
    return '$now-${_messageSequence++}-$random';
  }

  Future<void> _waitUntilConnected(Duration timeout) async {
    if (_state == WsConnectionState.connected && _channel != null) return;
    if (!_shouldReconnect || _serverUrl == null || _token == null) {
      throw const WsUnavailableException('WebSocket 尚未连接');
    }
    try {
      await stateStream
          .firstWhere((state) => state == WsConnectionState.connected)
          .timeout(timeout);
    } on TimeoutException {
      throw const WsUnavailableException('连接服务器超时');
    }
  }

  void _requestRoomJoin(int roomId) {
    if (_confirmedRooms.contains(roomId) ||
        _state != WsConnectionState.connected) {
      return;
    }
    sendEvent('room.join', roomId: roomId, payload: {});
  }

  void _failPendingChats(Object error) {
    final completers = _pendingChatCompleters.values.toList(growable: false);
    _pendingChatCompleters.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  void _failRoomJoins(Object error) {
    final completers = _roomJoinCompleters.values.toList(growable: false);
    _roomJoinCompleters.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  String _buildWsUrl(String serverUrl, String token) {
    // 移除尾部斜杠
    var base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
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

  void _handleMessage(dynamic data, int generation) {
    if (generation != _connectionGeneration) return;
    if (data is! String) return;
    final Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(data);
      if (value is! Map) return;
      decoded = Map<String, dynamic>.from(value);
    } catch (error) {
      debugPrint('[WsService] invalid message ignored: $error');
      return;
    }
    final event = decoded['event'] as String?;
    final rawPayload = decoded['payload'];
    final payload =
        rawPayload is Map ? Map<String, dynamic>.from(rawPayload) : null;

    if (event == null) return;

    debugPrint('[WsService] recv event=$event');

    // 收到 connected 事件后，标记为已连接，启动心跳
    if (event == 'connected') {
      final rtc = payload?['rtc'];
      final rawIceServers = rtc is Map ? rtc['ice_servers'] : null;
      if (rawIceServers is List) {
        _rtcIceServers = rawIceServers
            .whereType<Map>()
            .map((server) => Map<String, dynamic>.from(server))
            .toList(growable: false);
      }
      _connectTimeoutTimer?.cancel();
      _reconnectAttempts = 0;
      _setState(WsConnectionState.connected);
      _startHeartbeat();

      debugPrint(
          '[WsService] CONNECTED! Rejoining ${_joinedRooms.length} rooms: $_joinedRooms');
      _confirmedRooms.clear();
      // 断线重连后自动重新加入之前的房间
      for (final roomId in _joinedRooms) {
        _requestRoomJoin(roomId);
      }
    }

    if (event == 'room.joined' && payload != null) {
      final roomId = _readInt(payload['room_id'] ?? decoded['room_id']);
      if (roomId != null) {
        _confirmedRooms.add(roomId);
        final completer = _roomJoinCompleters.remove(roomId);
        if (completer != null && !completer.isCompleted) completer.complete();
      }
    }

    if (event == 'room.join_error' && payload != null) {
      final roomId = _readInt(payload['room_id'] ?? decoded['room_id']);
      if (roomId != null) {
        _confirmedRooms.remove(roomId);
        final completer = _roomJoinCompleters.remove(roomId);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            WsUnavailableException(payload['reason']?.toString() ?? '无法加入房间'),
          );
        }
      }
    }

    // 服务端返回 chat.error（通常因为 not_in_room），自动重新加入并提示
    if (event == 'chat.error' && payload != null) {
      debugPrint('[WsService] chat.error: $payload');
      final clientMessageId = payload['client_message_id']?.toString();
      if (clientMessageId != null) {
        final completer = _pendingChatCompleters[clientMessageId];
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            ChatSendException(payload['reason']?.toString() ?? 'send_failed'),
          );
        }
      }
      final roomId = _readInt(payload['room_id']);
      if (roomId != null && _joinedRooms.contains(roomId)) {
        _confirmedRooms.remove(roomId);
      }
    }

    // 推送到事件总线（将信封顶层的 room_id 合并到 payload 中）
    if (!_eventController.isClosed) {
      final mergedPayload = <String, dynamic>{...?payload};
      final envelopeRoomId = decoded['room_id'];
      if (envelopeRoomId != null && envelopeRoomId != 0) {
        mergedPayload['room_id'] ??= envelopeRoomId;
      }
      _eventController.add(WsEvent(event: event, payload: mergedPayload));
    }

    // 处理 chat.message 写入本地数据库
    if (event == 'chat.message' && payload != null) {
      try {
        debugPrint('[WsService] chat.message payload=$payload');
        final accountUserId = _accountUserId;
        if (accountUserId == null) return;
        final message =
            MessageModel.fromWs(payload, serverUrl: _serverUrl ?? '');
        unawaited(
          _db.messagesDao.upsertMessages([
            message.toCompanion(accountUserId: accountUserId),
          ]).catchError((Object error) {
            debugPrint('[WsService] message cache write failed: $error');
          }),
        );
        final clientMessageId = payload['client_message_id']?.toString();
        if (clientMessageId != null) {
          final completer = _pendingChatCompleters[clientMessageId];
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
        debugPrint(
            '[WsService] chat.message written to DB, id=${message.id} roomId=${message.roomId}');
      } catch (e, st) {
        debugPrint('[WsService] chat.message PARSE/DB ERROR: $e\n$st');
      }
    }
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

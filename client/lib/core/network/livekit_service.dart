import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// LiveKit 服务层，封装 livekit_client SDK
class LiveKitService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  /// 当前已连接的房间 ID（用于幂等检查，避免从设置页返回时重复连接）
  int? _connectedRoomId;
  int? get connectedRoomId => _connectedRoomId;

  /// 连接代数计数器，用于防止旧 connect() 的悬空 Future 覆盖新连接
  int _connectGeneration = 0;

  /// 上一次 disconnect() 的 Future，用于让 connect() 等待其完成
  Future<void>? _pendingDisconnect;

  final _participantsController =
      StreamController<List<RemoteParticipant>>.broadcast();
  final _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// 当前正在说话的用户 ID 集合（通过 LiveKit ActiveSpeakers 检测）
  final _speakingUsersController = StreamController<Set<int>>.broadcast();
  Stream<Set<int>> get speakingUsersStream => _speakingUsersController.stream;
  Set<int> _currentSpeakers = {};
  Set<int> get currentSpeakers => _currentSpeakers;

  String? _lastError;

  Room? get room => _room;
  LocalParticipant? get localParticipant => _room?.localParticipant;

  Stream<List<RemoteParticipant>> get participantsStream =>
      _participantsController.stream;

  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  Stream<String> get errorStream => _errorController.stream;
  String? get lastError => _lastError;

  bool get isConnected =>
      _room?.connectionState == ConnectionState.connected;

  /// 连接到 LiveKit 房间
  /// [roomId] 用于幂等检查，不传给 LiveKit SDK
  Future<void> connect(String url, String token, {int? roomId}) async {
    final myGeneration = ++_connectGeneration;
    debugPrint('[LiveKit] connect() generation=$myGeneration roomId=$roomId');

    // 等待上一次正在进行的 disconnect 完成
    await _pendingDisconnect;
    await disconnect();

    // 如果在 disconnect 期间有新的 connect() 被调用，放弃当前操作
    if (myGeneration != _connectGeneration) {
      debugPrint('[LiveKit] connect() generation=$myGeneration STALE after disconnect (current=$_connectGeneration), aborting');
      return;
    }

    _room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(
          dtx: true,
        ),
        defaultCameraCaptureOptions: CameraCaptureOptions(
          maxFrameRate: 30,
        ),
      ),
    );

    _listener = _room!.createListener();
    _setupListeners();

    _lastError = null;
    debugPrint('[LiveKit] Connecting to $url');
    try {
      await _room!.connect(url, token).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('LiveKit 连接超时 (15s)');
        },
      );

      // 连接成功后再次检查代数，防止被更新的 connect() 覆盖
      if (myGeneration != _connectGeneration) {
        debugPrint('[LiveKit] connect() generation=$myGeneration STALE after connect (current=$_connectGeneration), cleaning up');
        _listener?.dispose();
        _listener = null;
        await _room?.disconnect();
        await _room?.dispose();
        _room = null;
        return;
      }

      debugPrint('[LiveKit] Connected successfully, participants: ${_room!.remoteParticipants.length}');
      _connectedRoomId = roomId;
      _notifyParticipants();
    } catch (e) {
      // 如果已经被更新的 connect() 取代，忽略错误
      if (myGeneration != _connectGeneration) {
        debugPrint('[LiveKit] connect() generation=$myGeneration STALE error ignored');
        return;
      }
      final msg = 'LiveKit 连接失败: $e';
      debugPrint('[LiveKit] $msg');
      _lastError = msg;
      _errorController.add(msg);
      rethrow;
    }
  }

  /// 获取当前在线的用户 ID 集合（远端参与者，排除 ingress）
  Set<int> get onlineUserIds {
    if (_room == null) return {};
    final ids = <int>{};
    for (final p in _room!.remoteParticipants.values) {
      if (p.identity.startsWith('ingress_')) continue;
      final uid = int.tryParse(p.identity);
      if (uid != null) ids.add(uid);
    }
    return ids;
  }

  /// 断开连接（并发安全：立即清除字段，异步清理旧对象）
  Future<void> disconnect() async {
    _connectedRoomId = null;
    _currentSpeakers = {};
    if (!_speakingUsersController.isClosed) {
      _speakingUsersController.add({});
    }

    final oldRoom = _room;
    final oldListener = _listener;
    _room = null;
    _listener = null;

    if (oldRoom == null && oldListener == null) return;

    _pendingDisconnect = _cleanupRoom(oldRoom, oldListener);
    await _pendingDisconnect;
    _pendingDisconnect = null;
  }

  /// 安全清理旧的 Room / Listener（内部 try-catch 防止异常泄漏）
  Future<void> _cleanupRoom(Room? room, EventsListener<RoomEvent>? listener) async {
    try {
      listener?.dispose();
      await room?.disconnect();
      await room?.dispose();
    } catch (e) {
      debugPrint('[LiveKit] _cleanupRoom error (ignored): $e');
    }
  }

  /// 设置麦克风开关
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  /// 获取麦克风状态
  bool get isMicrophoneEnabled {
    final publications =
        _room?.localParticipant?.audioTrackPublications ?? [];
    for (final pub in publications) {
      if (pub.track != null && !pub.muted) return true;
    }
    return false;
  }

  /// 获取当前远端参与者列表
  List<RemoteParticipant> get remoteParticipants {
    return _room?.remoteParticipants.values.toList() ?? [];
  }

  /// 获取 Ingress 参与者（identity 以 ingress_ 开头）
  List<RemoteParticipant> get ingressParticipants {
    return remoteParticipants
        .where((p) => p.identity.startsWith('ingress_'))
        .toList();
  }

  /// 获取普通参与者（非 ingress）
  List<RemoteParticipant> get normalParticipants {
    return remoteParticipants
        .where((p) => !p.identity.startsWith('ingress_'))
        .toList();
  }

  /// 订阅远端 participant 的视频轨道
  Future<void> subscribeVideo(RemoteParticipant participant) async {
    for (final pub in participant.videoTrackPublications) {
      if (!pub.subscribed) {
        await pub.subscribe();
      }
      pub.enable();
    }
  }

  /// 取消订阅远端 participant 的视频轨道
  Future<void> unsubscribeVideo(RemoteParticipant participant) async {
    for (final pub in participant.videoTrackPublications) {
      if (pub.subscribed) {
        await pub.unsubscribe();
      }
    }
  }

  /// 设置视频质量（用于 Simulcast 切换）
  void setVideoQuality(
      RemoteTrackPublication pub, VideoQuality quality) {
    pub.setVideoQuality(quality);
  }

  /// 暂停所有视频轨道解码（窗口最小化时调用）
  void disableAllVideoTracks() {
    if (_room == null) return;
    for (final participant in _room!.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.subscribed) {
          pub.disable();
        }
      }
    }
  }

  /// 恢复所有视频轨道解码（窗口恢复时调用）
  void enableAllVideoTracks() {
    if (_room == null) return;
    for (final participant in _room!.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.subscribed) {
          pub.enable();
        }
      }
    }
  }

  void _setupListeners() {
    _listener
      ?..on<ParticipantConnectedEvent>((e) {
        debugPrint('[LiveKit] Participant connected: ${e.participant.identity}');
        _notifyParticipants();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        debugPrint('[LiveKit] Participant disconnected: ${e.participant.identity}');
        _notifyParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        debugPrint('[LiveKit] Track published: ${e.participant.identity} ${e.publication.sid}');
        _notifyParticipants();
      })
      ..on<TrackUnpublishedEvent>((_) => _notifyParticipants())
      ..on<TrackSubscribedEvent>((e) {
        debugPrint('[LiveKit] Track subscribed: ${e.participant.identity} kind=${e.track.kind}');
        _notifyParticipants();
      })
      ..on<TrackUnsubscribedEvent>((_) => _notifyParticipants())
      ..on<RoomConnectedEvent>((_) {
        _connectionStateController.add(ConnectionState.connected);
        debugPrint('[LiveKit] Room connected, remote participants: ${_room?.remoteParticipants.length}');
      })
      ..on<RoomReconnectingEvent>((_) {
        _connectionStateController.add(ConnectionState.reconnecting);
        debugPrint('[LiveKit] Reconnecting...');
      })
      ..on<RoomDisconnectedEvent>((e) {
        _connectionStateController.add(ConnectionState.disconnected);
        // 意外断线时清除 connectedRoomId，避免后续「跳过重连」误判
        _connectedRoomId = null;
        debugPrint('[LiveKit] Disconnected: ${e.reason}, connectedRoomId cleared');
      })
      ..on<ActiveSpeakersChangedEvent>((e) {
        // 通过 LiveKit 的 ActiveSpeakers 检测谁在说话
        final speakers = <int>{};
        for (final p in e.speakers) {
          final uid = int.tryParse(p.identity);
          if (uid != null) speakers.add(uid);
        }
        _currentSpeakers = speakers;
        if (!_speakingUsersController.isClosed) {
          _speakingUsersController.add(speakers);
        }
      });
  }

  void _notifyParticipants() {
    if (!_participantsController.isClosed) {
      _participantsController.add(remoteParticipants);
    }
  }

  void dispose() {
    disconnect();
    _participantsController.close();
    _connectionStateController.close();
    _errorController.close();
    _speakingUsersController.close();
  }
}

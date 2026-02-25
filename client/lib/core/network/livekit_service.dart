import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

/// LiveKit 服务层，封装 livekit_client SDK
class LiveKitService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  /// 当前已连接的房间 ID（用于幂等检查，避免从设置页返回时重复连接）
  int? _connectedRoomId;
  int? get connectedRoomId => _connectedRoomId;

  final _participantsController =
      StreamController<List<RemoteParticipant>>.broadcast();
  final _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
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
    await disconnect();

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
    print('[LiveKit] Connecting to $url');
    try {
      await _room!.connect(url, token).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('LiveKit 连接超时 (15s)');
        },
      );
      print('[LiveKit] Connected successfully, participants: ${_room!.remoteParticipants.length}');
      _connectedRoomId = roomId;
      _notifyParticipants();
    } catch (e) {
      final msg = 'LiveKit 连接失败: $e';
      print('[LiveKit] $msg');
      _lastError = msg;
      _errorController.add(msg);
      rethrow;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _connectedRoomId = null;
    _listener?.dispose();
    _listener = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
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
        print('[LiveKit] Participant connected: ${e.participant.identity}');
        _notifyParticipants();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        print('[LiveKit] Participant disconnected: ${e.participant.identity}');
        _notifyParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        print('[LiveKit] Track published: ${e.participant.identity} ${e.publication.sid}');
        _notifyParticipants();
      })
      ..on<TrackUnpublishedEvent>((_) => _notifyParticipants())
      ..on<TrackSubscribedEvent>((e) {
        print('[LiveKit] Track subscribed: ${e.participant.identity} kind=${e.track.kind}');
        _notifyParticipants();
      })
      ..on<TrackUnsubscribedEvent>((_) => _notifyParticipants())
      ..on<RoomConnectedEvent>((_) {
        _connectionStateController.add(ConnectionState.connected);
        print('[LiveKit] \u2705 Room connected, remote participants: ${_room?.remoteParticipants.length}');
      })
      ..on<RoomReconnectingEvent>((_) {
        _connectionStateController.add(ConnectionState.reconnecting);
        print('[LiveKit] Reconnecting...');
      })
      ..on<RoomDisconnectedEvent>((e) {
        _connectionStateController.add(ConnectionState.disconnected);
        print('[LiveKit] Disconnected: ${e.reason}');
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
  }
}

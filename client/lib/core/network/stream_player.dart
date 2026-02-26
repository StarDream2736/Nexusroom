import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// 独立的直播流播放器，连接到专用的直播 LiveKit 房间。
/// 与语音房间的 LiveKitService 完全隔离。
class StreamPlayer {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  final _videoTrackController = StreamController<VideoTrack?>.broadcast();
  final _statusController = StreamController<StreamPlayerStatus>.broadcast();

  VideoTrack? _currentVideoTrack;
  StreamPlayerStatus _status = StreamPlayerStatus.idle;
  String? _lastUrl;
  String? _lastToken;

  Stream<VideoTrack?> get videoTrackStream => _videoTrackController.stream;
  Stream<StreamPlayerStatus> get statusStream => _statusController.stream;
  VideoTrack? get currentVideoTrack => _currentVideoTrack;
  StreamPlayerStatus get status => _status;
  bool _audioMuted = false;
  bool get audioMuted => _audioMuted;

  /// Mute / unmute the stream audio (viewer-side).
  void setAudioMuted(bool muted) {
    _audioMuted = muted;
    final participants = _room?.remoteParticipants.values ?? [];
    for (final p in participants) {
      for (final pub in p.audioTrackPublications) {
        if (muted) {
          pub.disable();
        } else {
          pub.enable();
        }
      }
    }
  }

  /// 连接到直播房间并自动订阅 ingress 视频+音频
  Future<void> connect(String url, String token) async {
    await disconnect();
    _lastUrl = url;
    _lastToken = token;

    _setStatus(StreamPlayerStatus.connecting);

    _room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: false,
        dynacast: false,
        // 直播观看者不发布任何轨道
        defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
      ),
    );

    _listener = _room!.createListener();
    _setupListeners();

    try {
      await _room!.connect(url, token).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('直播房间连接超时');
        },
      );
      debugPrint('[StreamPlayer] Connected to stream room');
      _setStatus(StreamPlayerStatus.connected);

      // 连接成功后，订阅已在房间内的 ingress 参与者
      _subscribeAllTracks();
    } catch (e) {
      debugPrint('[StreamPlayer] Connection failed: $e');
      _setStatus(StreamPlayerStatus.error);
      rethrow;
    }
  }

  /// 断开直播房间连接
  Future<void> disconnect() async {
    _lastUrl = null;
    _lastToken = null;
    _listener?.dispose();
    _listener = null;
    _currentVideoTrack = null;
    if (!_videoTrackController.isClosed) {
      _videoTrackController.add(null);
    }
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
    _setStatus(StreamPlayerStatus.idle);
  }

  void _setupListeners() {
    _listener
      ?..on<ParticipantConnectedEvent>((e) {
        debugPrint('[StreamPlayer] Participant joined: ${e.participant.identity}');
        _subscribeAllTracks();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        debugPrint('[StreamPlayer] Participant left: ${e.participant.identity}');
        // 如果 ingress 断开，清空视频
        if (_room?.remoteParticipants.isEmpty ?? true) {
          _currentVideoTrack = null;
          _videoTrackController.add(null);
          _setStatus(StreamPlayerStatus.waitingForStream);
        }
      })
      ..on<TrackPublishedEvent>((_) => _subscribeAllTracks())
      ..on<TrackSubscribedEvent>((e) {
        debugPrint('[StreamPlayer] Track subscribed: kind=${e.track.kind}');
        if (e.track is VideoTrack) {
          _currentVideoTrack = e.track as VideoTrack;
          _videoTrackController.add(_currentVideoTrack);
          _setStatus(StreamPlayerStatus.playing);
        }
      })
      ..on<TrackUnsubscribedEvent>((e) {
        if (e.track is VideoTrack) {
          _currentVideoTrack = null;
          _videoTrackController.add(null);
        }
      })
      ..on<RoomDisconnectedEvent>((_) {
        debugPrint('[StreamPlayer] Room disconnected');
        _setStatus(StreamPlayerStatus.idle);
        // 自动重连：如果非主动断开（_lastUrl 仍有值），延迟 2 秒重连
        final url = _lastUrl;
        final token = _lastToken;
        if (url != null && token != null) {
          Future.delayed(const Duration(seconds: 2), () {
            if (_lastUrl == null) return; // 已主动断开或已 dispose
            debugPrint('[StreamPlayer] Auto-reconnecting...');
            connect(url, token);
          });
        }
      });
  }

  /// 订阅房间内所有远端参与者的音视频轨道
  void _subscribeAllTracks() {
    final participants = _room?.remoteParticipants.values ?? [];
    for (final p in participants) {
      for (final pub in p.videoTrackPublications) {
        if (!pub.subscribed) {
          pub.subscribe();
        }
        pub.enable();
      }
      for (final pub in p.audioTrackPublications) {
        if (!pub.subscribed) {
          pub.subscribe();
        }
        pub.enable();
      }
    }

    if (participants.isEmpty && _status == StreamPlayerStatus.connected) {
      _setStatus(StreamPlayerStatus.waitingForStream);
    }
  }

  void _setStatus(StreamPlayerStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  void dispose() {
    // Synchronously detach listener and clear track reference first,
    // so no callbacks can fire into closed controllers.
    _lastUrl = null;
    _lastToken = null;
    _listener?.dispose();
    _listener = null;
    _currentVideoTrack = null;

    // Fire-and-forget the async room cleanup.
    final room = _room;
    _room = null;
    if (room != null) {
      room.disconnect().then((_) => room.dispose()).ignore();
    }

    // Now safe to close the stream controllers.
    _videoTrackController.close();
    _statusController.close();
  }
}

enum StreamPlayerStatus {
  idle,
  connecting,
  connected,
  waitingForStream,
  playing,
  error,
}

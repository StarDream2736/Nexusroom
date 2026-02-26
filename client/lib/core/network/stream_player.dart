import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 独立的直播流播放器，通过 HTTP-FLV 从 SRS 拉流。
/// 与语音房间的 LiveKitService 完全隔离。
class StreamPlayer {
  Player? _player;
  VideoController? _videoController;

  final _videoControllerStream = StreamController<VideoController?>.broadcast();
  final _statusController = StreamController<StreamPlayerStatus>.broadcast();

  StreamPlayerStatus _status = StreamPlayerStatus.idle;
  String? _lastUrl;

  Stream<VideoController?> get videoControllerStream =>
      _videoControllerStream.stream;
  Stream<StreamPlayerStatus> get statusStream => _statusController.stream;
  VideoController? get currentVideoController => _videoController;
  StreamPlayerStatus get status => _status;
  bool _audioMuted = false;
  bool get audioMuted => _audioMuted;

  /// Mute / unmute the stream audio (viewer-side).
  void setAudioMuted(bool muted) {
    _audioMuted = muted;
    _player?.setVolume(muted ? 0.0 : 100.0);
  }

  /// 连接到 HTTP-FLV 直播流
  /// [url] 为 HTTP-FLV 地址，如 http://host:8085/live/streamKey.flv
  Future<void> connect(String url) async {
    await disconnect();
    _lastUrl = url;

    _setStatus(StreamPlayerStatus.connecting);

    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 2 * 1024 * 1024, // 2 MB — 直播低延迟
        ),
      );

      // MPV 直播优化参数：低延迟、无缓存、实时模式
      final mpv = _player!.platform;
      if (mpv is NativePlayer) {
        await mpv.setProperty('cache', 'no');
        await mpv.setProperty('demuxer-max-bytes', '500KiB');
        await mpv.setProperty('demuxer-readahead-secs', '0.2');
        await mpv.setProperty('untimed', 'yes');
        await mpv.setProperty('profile', 'low-latency');
      }

      _videoController = VideoController(_player!);

      // 监听播放状态
      _player!.stream.playing.listen((playing) {
        if (playing && _status != StreamPlayerStatus.playing) {
          _setStatus(StreamPlayerStatus.playing);
          _videoControllerStream.add(_videoController);
        }
      });

      _player!.stream.buffering.listen((buffering) {
        if (buffering && _status == StreamPlayerStatus.connected) {
          _setStatus(StreamPlayerStatus.waitingForStream);
        }
      });

      _player!.stream.error.listen((error) {
        debugPrint('[StreamPlayer] Error: $error');
        if (error.isNotEmpty) {
          _setStatus(StreamPlayerStatus.error);
        }
      });

      // 监听 completed 以实现自动重连
      _player!.stream.completed.listen((completed) {
        if (completed && _lastUrl != null) {
          debugPrint('[StreamPlayer] Stream ended, auto-reconnecting...');
          Future.delayed(const Duration(seconds: 2), () {
            if (_lastUrl == null) return;
            connect(_lastUrl!);
          });
        }
      });

      // 设置初始音量
      _player!.setVolume(_audioMuted ? 0.0 : 100.0);

      // 开始播放 HTTP-FLV 流
      await _player!.open(Media(url), play: true);
      _setStatus(StreamPlayerStatus.connected);
      _videoControllerStream.add(_videoController);

      debugPrint('[StreamPlayer] Connected to $url');
    } catch (e) {
      debugPrint('[StreamPlayer] Connection failed: $e');
      _setStatus(StreamPlayerStatus.error);
      rethrow;
    }
  }

  /// 断开直播流
  Future<void> disconnect() async {
    _lastUrl = null;
    final player = _player;
    _player = null;
    _videoController = null;
    if (!_videoControllerStream.isClosed) {
      _videoControllerStream.add(null);
    }
    await player?.stop();
    await player?.dispose();
    _setStatus(StreamPlayerStatus.idle);
  }

  void _setStatus(StreamPlayerStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  void dispose() {
    _lastUrl = null;

    final player = _player;
    _player = null;
    _videoController = null;

    if (player != null) {
      player.stop().then((_) => player.dispose()).ignore();
    }

    _videoControllerStream.close();
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

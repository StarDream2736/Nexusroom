import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ws_service.dart';

enum RtcConnectionState { disconnected, connecting, connected, reconnecting }

/// Applies threshold hysteresis and a short silence hold to raw microphone
/// levels so natural pauses do not repeatedly restart the speaking indicator.
class VoiceActivityDetector {
  VoiceActivityDetector({
    this.startThreshold = 0.018,
    this.stopThreshold = 0.008,
    this.silenceSamplesToStop = 5,
  });

  final double startThreshold;
  final double stopThreshold;
  final int silenceSamplesToStop;
  bool _speaking = false;
  int _silentSamples = 0;

  bool get speaking => _speaking;

  bool update(double level) {
    if (level > startThreshold) {
      _speaking = true;
      _silentSamples = 0;
    } else if (_speaking && level < stopThreshold) {
      _silentSamples++;
      if (_silentSamples >= silenceSamplesToStop) {
        _speaking = false;
        _silentSamples = 0;
      }
    } else if (_speaking) {
      _silentSamples = 0;
    }
    return _speaking;
  }

  void reset() {
    _speaking = false;
    _silentSamples = 0;
  }
}

class RtcParticipant {
  const RtcParticipant({
    required this.userId,
    required this.muted,
    required this.speaking,
  });

  final int userId;
  final bool muted;
  final bool speaking;

  factory RtcParticipant.fromJson(Map<String, dynamic> json) {
    return RtcParticipant(
      userId: (json['user_id'] as num).toInt(),
      muted: json['muted'] as bool? ?? true,
      speaking: json['speaking'] as bool? ?? false,
    );
  }
}

/// NexusRoom's own WebRTC voice client.
///
/// Signaling is transported by the authenticated application WebSocket; only
/// ICE, DTLS, SRTP and device access are delegated to flutter_webrtc.
class RtcService {
  RtcService(
    this._ws, {
    String? Function()? audioInputDeviceId,
    String? Function()? audioOutputDeviceId,
  })  : _audioInputDeviceId = audioInputDeviceId,
        _audioOutputDeviceId = audioOutputDeviceId {
    _subscriptions.add(_ws.on('rtc.answer').listen(_handleAnswer));
    _subscriptions.add(_ws.on('rtc.offer').listen(_handleOffer));
    _subscriptions.add(_ws.on('rtc.ice').listen(_handleCandidate));
    _subscriptions.add(_ws.on('rtc.participants').listen(_handleParticipants));
    _subscriptions.add(_ws.on('rtc.state').listen(_handleServerState));
    _subscriptions.add(_ws.on('rtc.error').listen((payload) {
      _emitError(payload['message']?.toString() ?? 'RTC connection failed');
    }));
    _subscriptions.add(_ws.stateStream.listen((state) {
      if (state == WsConnectionState.connected &&
          _connectedRoomId != null &&
          _pc == null) {
        unawaited(connect(roomId: _connectedRoomId!));
      } else if (state == WsConnectionState.disconnected && _pc != null) {
        _setState(RtcConnectionState.reconnecting);
        unawaited(_closePeer(sendLeave: false));
      }
    }));
  }

  final WsService _ws;
  final String? Function()? _audioInputDeviceId;
  final String? Function()? _audioOutputDeviceId;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Timer? _speakerTimer;
  Future<void>? _connectOperation;
  int? _connectingRoomId;
  bool _negotiating = false;
  int _generation = 0;
  int? _connectedRoomId;
  final VoiceActivityDetector _voiceActivity = VoiceActivityDetector();
  bool _speakerSampleInProgress = false;
  bool _microphoneEnabled = false;
  double? _previousAudioEnergy;
  double? _previousAudioDuration;
  bool _localDescriptionSignaled = false;
  bool _remoteDescriptionSet = false;
  Map<String, dynamic>? _queuedRemoteOffer;
  final List<Map<String, dynamic>> _pendingLocalCandidates = [];
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  final _participantsController =
      StreamController<List<RtcParticipant>>.broadcast();
  final _connectionStateController =
      StreamController<RtcConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _speakingUsersController = StreamController<Set<int>>.broadcast();

  RtcConnectionState _state = RtcConnectionState.disconnected;
  List<RtcParticipant> _participants = const [];
  String? _lastError;

  int? get connectedRoomId => _connectedRoomId;
  bool get isConnected => _state == RtcConnectionState.connected;
  bool get isMicrophoneEnabled => _microphoneEnabled;
  String? get lastError => _lastError;
  List<RtcParticipant> get participants => List.unmodifiable(_participants);
  Set<int> get currentSpeakers => _participants
      .where((participant) => participant.speaking)
      .map((participant) => participant.userId)
      .toSet();

  Stream<List<RtcParticipant>> get participantsStream =>
      _participantsController.stream;
  Stream<RtcConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Set<int>> get speakingUsersStream => _speakingUsersController.stream;

  Future<void> connect({required int roomId}) {
    final existing = _connectOperation;
    if (_connectingRoomId == roomId && existing != null) return existing;

    final operation = _connect(roomId);
    _connectingRoomId = roomId;
    _connectOperation = operation;
    unawaited(operation.then<void>(
      (_) => _clearConnectOperation(operation),
      onError: (_, __) => _clearConnectOperation(operation),
    ));
    return operation;
  }

  void _clearConnectOperation(Future<void> operation) {
    if (!identical(_connectOperation, operation)) return;
    _connectOperation = null;
    _connectingRoomId = null;
  }

  Future<void> _connect(int roomId) async {
    if (_connectedRoomId == roomId && _pc != null && isConnected) return;
    final generation = ++_generation;
    await _closePeer(sendLeave: _connectedRoomId != null);
    if (generation != _generation) return;

    _connectedRoomId = roomId;
    _lastError = null;
    _setState(RtcConnectionState.connecting);

    try {
      await _waitForWebSocket();
      if (generation != _generation) return;

      // The server processes messages from one WebSocket in order. Sending
      // room.join before rtc.offer guarantees that the RTC membership check
      // sees this client as joined, including after reconnects.
      await _ws.ensureRoomJoined(roomId);

      final uri = Uri.parse(_ws.serverUrl ?? 'http://127.0.0.1:8080');
      final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
      final iceServers = _ws.rtcIceServers.isNotEmpty
          ? _ws.rtcIceServers
          : [
              {
                'urls': ['stun:$host:3478']
              },
            ];
      final configuration = <String, dynamic>{
        'sdpSemantics': 'unified-plan',
        'iceServers': iceServers,
      };
      final pc = await createPeerConnection(configuration, {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      });
      if (generation != _generation) {
        await pc.close();
        return;
      }
      _pc = pc;
      _localDescriptionSignaled = false;
      _remoteDescriptionSet = false;
      _pendingLocalCandidates.clear();
      _pendingRemoteCandidates.clear();

      pc.onIceCandidate = (candidate) {
        final activeRoom = _connectedRoomId;
        if (activeRoom == null || candidate.candidate == null) return;
        final payload = <String, dynamic>{
          'candidate': candidate.candidate,
          if (candidate.sdpMid != null) 'sdp_mid': candidate.sdpMid,
          if (candidate.sdpMLineIndex != null)
            'sdp_mline_index': candidate.sdpMLineIndex,
        };
        if (!_localDescriptionSignaled) {
          _pendingLocalCandidates.add(payload);
          return;
        }
        _ws.sendEvent('rtc.ice', roomId: activeRoom, payload: payload);
      };
      pc.onConnectionState = (state) {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _setState(RtcConnectionState.connected);
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _setState(RtcConnectionState.reconnecting);
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _setState(RtcConnectionState.disconnected);
            break;
          default:
            break;
        }
      };
      pc.onIceConnectionState = (state) {
        switch (state) {
          case RTCIceConnectionState.RTCIceConnectionStateConnected:
          case RTCIceConnectionState.RTCIceConnectionStateCompleted:
            _setState(RtcConnectionState.connected);
            break;
          case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          case RTCIceConnectionState.RTCIceConnectionStateFailed:
            _setState(RtcConnectionState.reconnecting);
            break;
          case RTCIceConnectionState.RTCIceConnectionStateClosed:
            _setState(RtcConnectionState.disconnected);
            break;
          default:
            break;
        }
      };
      pc.onTrack = (event) {
        if (event.track.kind == 'audio') {
          event.track.enabled = true;
        }
      };

      final inputDeviceId = _audioInputDeviceId?.call();
      final outputDeviceId = _audioOutputDeviceId?.call();
      if (inputDeviceId != null && inputDeviceId.isNotEmpty) {
        try {
          await Helper.selectAudioInput(inputDeviceId);
        } catch (_) {
          // The persisted device may have disappeared; getUserMedia will use
          // the current system default instead.
        }
      }
      if (outputDeviceId != null && outputDeviceId.isNotEmpty) {
        try {
          await Helper.selectAudioOutput(outputDeviceId);
        } catch (_) {
          // Fall back to the current system output device.
        }
      }

      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      if (generation != _generation) {
        await stream.dispose();
        await pc.close();
        return;
      }
      _localStream = stream;
      for (final track in stream.getAudioTracks()) {
        track.enabled = false;
        await pc.addTrack(track, stream);
      }
      _microphoneEnabled = false;

      // Reserve receive-only audio slots so a group call can add several
      // remote speakers without depending on fragile back-to-back renegotiation.
      for (var index = 0; index < 7; index++) {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.RecvOnly,
          ),
        );
      }

      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      if (!_ws.sendEvent('rtc.offer', roomId: roomId, payload: {
        'type': offer.type,
        'sdp': offer.sdp,
      })) {
        throw const WsUnavailableException('RTC 协商请求发送失败');
      }
      _localDescriptionSignaled = true;
      for (final candidate in _pendingLocalCandidates) {
        _ws.sendEvent('rtc.ice', roomId: roomId, payload: candidate);
      }
      _pendingLocalCandidates.clear();
      _startSpeakerMonitor();
      await waitUntilConnected();
    } catch (error) {
      if (generation == _generation) {
        _emitError('RTC connection failed: $error');
        await _closePeer(sendLeave: true);
      }
      rethrow;
    }
  }

  Future<void> waitUntilConnected({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (isConnected) return;
    await connectionStateStream
        .firstWhere((state) => state == RtcConnectionState.connected)
        .timeout(timeout, onTimeout: () {
      throw TimeoutException('语音连接超时，请检查 UDP 端口与网络设置');
    });
  }

  Future<void> _waitForWebSocket() async {
    if (_ws.connectionState == WsConnectionState.connected) return;
    await _ws.stateStream
        .firstWhere((state) => state == WsConnectionState.connected)
        .timeout(const Duration(seconds: 10));
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (!isConnected) {
      throw StateError('语音尚未连接');
    }
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) {
      throw StateError('未检测到可用的麦克风');
    }
    final previous = _microphoneEnabled;
    for (final track in tracks) {
      track.enabled = enabled;
    }
    _microphoneEnabled = enabled;
    final roomId = _connectedRoomId;
    if (roomId != null) {
      if (!_ws.sendVoiceMute(roomId: roomId, muted: !enabled)) {
        for (final track in tracks) {
          track.enabled = previous;
        }
        _microphoneEnabled = previous;
        throw const WsUnavailableException('麦克风状态同步失败，请重试');
      }
      if (!enabled && _voiceActivity.speaking) {
        _voiceActivity.reset();
        _ws.sendEvent('rtc.speaking',
            roomId: roomId, payload: {'speaking': false});
      }
    }
  }

  Future<void> disconnect() async {
    _generation++;
    final roomId = _connectedRoomId;
    _connectedRoomId = null;
    _participants = const [];
    if (!_participantsController.isClosed) {
      _participantsController.add(const []);
    }
    if (!_speakingUsersController.isClosed) {
      _speakingUsersController.add(const {});
    }
    _setState(RtcConnectionState.disconnected);
    await _closePeer(sendLeave: roomId != null, roomIdOverride: roomId);
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final pc = _pc;
    final sdp = payload['sdp'] as String?;
    if (pc == null || sdp == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _remoteDescriptionSet = true;
    await _flushRemoteCandidates(pc);
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    if (_negotiating) {
      _queuedRemoteOffer = payload;
      return;
    }
    _negotiating = true;
    try {
      Map<String, dynamic>? current = payload;
      while (current != null) {
        _queuedRemoteOffer = null;
        final pc = _pc;
        final roomId = _connectedRoomId;
        final sdp = current['sdp'] as String?;
        if (pc == null || roomId == null || sdp == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        _remoteDescriptionSet = true;
        await _flushRemoteCandidates(pc);
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        if (!_ws.sendEvent('rtc.answer', roomId: roomId, payload: {
          'type': answer.type,
          'sdp': answer.sdp,
        })) {
          throw const WsUnavailableException('RTC 应答发送失败');
        }
        current = _queuedRemoteOffer;
      }
    } catch (error) {
      _emitError('RTC 重协商失败: $error');
    } finally {
      _negotiating = false;
      _queuedRemoteOffer = null;
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> payload) async {
    final pc = _pc;
    final candidate = payload['candidate'] as String?;
    if (pc == null || candidate == null) return;
    final iceCandidate = RTCIceCandidate(
      candidate,
      payload['sdp_mid'] as String?,
      (payload['sdp_mline_index'] as num?)?.toInt(),
    );
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(iceCandidate);
      return;
    }
    await pc.addCandidate(iceCandidate);
  }

  Future<void> _flushRemoteCandidates(RTCPeerConnection pc) async {
    for (final candidate in _pendingRemoteCandidates) {
      await pc.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  void _handleParticipants(Map<String, dynamic> payload) {
    final raw = payload['participants'] as List<dynamic>? ?? const [];
    _participants = raw
        .map((entry) => RtcParticipant.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
    if (!_speakingUsersController.isClosed) {
      _speakingUsersController.add(currentSpeakers);
    }
  }

  void _handleServerState(Map<String, dynamic> payload) {
    final state = payload['state']?.toString();
    if (state == 'connected') {
      _setState(RtcConnectionState.connected);
    } else if (state == 'failed' || state == 'disconnected') {
      _setState(RtcConnectionState.reconnecting);
    }
  }

  void _startSpeakerMonitor() {
    _speakerTimer?.cancel();
    _previousAudioEnergy = null;
    _previousAudioDuration = null;
    _speakerTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) async {
      final pc = _pc;
      final roomId = _connectedRoomId;
      if (pc == null ||
          roomId == null ||
          !isMicrophoneEnabled ||
          _speakerSampleInProgress) {
        return;
      }
      _speakerSampleInProgress = true;
      try {
        final reports = await pc.getStats();
        double level = 0;
        double totalEnergy = 0;
        double totalDuration = 0;
        for (final report in reports) {
          final values = report.values;
          if (!_isLocalAudioReport(values, report.type)) continue;

          final standardLevel = _readStatNumber(values['audioLevel']);
          if (standardLevel != null) {
            level = math.max(level, standardLevel.clamp(0.0, 1.0));
          }

          final legacyLevel = _readStatNumber(values['googAudioInputLevel']);
          if (legacyLevel != null) {
            level = math.max(level, (legacyLevel / 32767).clamp(0.0, 1.0));
          }

          final energy = _readStatNumber(values['totalAudioEnergy']);
          final duration = _readStatNumber(values['totalSamplesDuration']);
          if (energy != null && duration != null) {
            totalEnergy += energy;
            totalDuration += duration;
          }
        }

        final previousEnergy = _previousAudioEnergy;
        final previousDuration = _previousAudioDuration;
        if (totalDuration > 0) {
          _previousAudioEnergy = totalEnergy;
          _previousAudioDuration = totalDuration;
          if (previousEnergy != null && previousDuration != null) {
            final energyDelta = totalEnergy - previousEnergy;
            final durationDelta = totalDuration - previousDuration;
            if (energyDelta >= 0 && durationDelta > 0) {
              level = math.max(level, math.sqrt(energyDelta / durationDelta));
            }
          }
        }
        final wasSpeaking = _voiceActivity.speaking;
        final speaking = _voiceActivity.update(level);
        if (speaking != wasSpeaking) {
          _ws.sendEvent('rtc.speaking',
              roomId: roomId, payload: {'speaking': speaking});
        }
      } catch (_) {
        // Audio level is optional on some desktop WebRTC backends.
      } finally {
        _speakerSampleInProgress = false;
      }
    });
  }

  double? _readStatNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool _isLocalAudioReport(Map<dynamic, dynamic> values, String reportType) {
    final kind = (values['kind'] ?? values['mediaType'])?.toString();
    if (kind != null && kind != 'audio') return false;

    final type =
        reportType.isNotEmpty ? reportType : values['type']?.toString();
    if (type == 'inbound-rtp' || values['remoteSource'] == true) return false;
    return type == null ||
        type == 'media-source' ||
        type == 'outbound-rtp' ||
        type == 'sender' ||
        type == 'track';
  }

  Future<void> _closePeer({
    required bool sendLeave,
    int? roomIdOverride,
  }) async {
    _speakerTimer?.cancel();
    _speakerTimer = null;
    final roomId = roomIdOverride ?? _connectedRoomId;
    if (sendLeave && roomId != null) {
      _ws.sendEvent('rtc.leave', roomId: roomId);
    }
    final pc = _pc;
    final stream = _localStream;
    _pc = null;
    _localStream = null;
    _voiceActivity.reset();
    _speakerSampleInProgress = false;
    _microphoneEnabled = false;
    _previousAudioEnergy = null;
    _previousAudioDuration = null;
    _localDescriptionSignaled = false;
    _remoteDescriptionSet = false;
    _pendingLocalCandidates.clear();
    _pendingRemoteCandidates.clear();
    _queuedRemoteOffer = null;
    if (pc != null) {
      pc.onConnectionState = null;
      pc.onIceConnectionState = null;
      pc.onIceCandidate = null;
      pc.onTrack = null;
    }
    for (final track in stream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await track.stop();
    }
    await stream?.dispose();
    await pc?.close();
  }

  void _setState(RtcConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void _emitError(String message) {
    _lastError = message;
    if (!_errorController.isClosed) _errorController.add(message);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_disposeResources());
  }

  Future<void> _disposeResources() async {
    await disconnect();
    await _participantsController.close();
    await _connectionStateController.close();
    await _errorController.close();
    await _speakingUsersController.close();
  }
}

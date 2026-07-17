import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ws_service.dart';

enum RtcConnectionState { disconnected, connecting, connected, reconnecting }

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
  RtcService(this._ws) {
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
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Timer? _speakerTimer;
  bool _negotiating = false;
  int _generation = 0;
  int? _connectedRoomId;
  bool _lastSpeaking = false;
  bool _localDescriptionSignaled = false;
  bool _remoteDescriptionSet = false;
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
  bool get isMicrophoneEnabled =>
      _localStream?.getAudioTracks().any((track) => track.enabled) ?? false;
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

  Future<void> connect({required int roomId}) async {
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
      _ws.joinRoom(roomId);

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
      pc.onTrack = (event) {
        if (event.track.kind == 'audio') {
          event.track.enabled = true;
        }
      };

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

      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription(offer);
      _ws.sendEvent('rtc.offer', roomId: roomId, payload: {
        'type': offer.type,
        'sdp': offer.sdp,
      });
      _localDescriptionSignaled = true;
      for (final candidate in _pendingLocalCandidates) {
        _ws.sendEvent('rtc.ice', roomId: roomId, payload: candidate);
      }
      _pendingLocalCandidates.clear();
      _startSpeakerMonitor();
    } catch (error) {
      if (generation == _generation) {
        _emitError('RTC connection failed: $error');
        await _closePeer(sendLeave: true);
      }
      rethrow;
    }
  }

  Future<void> _waitForWebSocket() async {
    if (_ws.connectionState == WsConnectionState.connected) return;
    await _ws.stateStream
        .firstWhere((state) => state == WsConnectionState.connected)
        .timeout(const Duration(seconds: 10));
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    for (final track
        in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
    final roomId = _connectedRoomId;
    if (roomId != null) {
      _ws.sendVoiceMute(roomId: roomId, muted: !enabled);
      if (!enabled && _lastSpeaking) {
        _lastSpeaking = false;
        _ws.sendEvent('rtc.speaking',
            roomId: roomId, payload: {'speaking': false});
      }
    }
  }

  Future<void> disconnect() async {
    _generation++;
    await _closePeer(sendLeave: true);
    _connectedRoomId = null;
    _participants = const [];
    _participantsController.add(const []);
    _speakingUsersController.add(const {});
    _setState(RtcConnectionState.disconnected);
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
    final pc = _pc;
    final roomId = _connectedRoomId;
    final sdp = payload['sdp'] as String?;
    if (pc == null || roomId == null || sdp == null || _negotiating) return;
    _negotiating = true;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteDescriptionSet = true;
      await _flushRemoteCandidates(pc);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _ws.sendEvent('rtc.answer', roomId: roomId, payload: {
        'type': answer.type,
        'sdp': answer.sdp,
      });
    } finally {
      _negotiating = false;
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
    if (state == 'failed') {
      _setState(RtcConnectionState.reconnecting);
    }
  }

  void _startSpeakerMonitor() {
    _speakerTimer?.cancel();
    _speakerTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) async {
      final pc = _pc;
      final roomId = _connectedRoomId;
      if (pc == null || roomId == null || !isMicrophoneEnabled) return;
      try {
        final reports = await pc.getStats();
        double level = 0;
        for (final report in reports) {
          final value = report.values['audioLevel'];
          if (value is num && value.toDouble() > level) {
            level = value.toDouble();
          }
        }
        final speaking = level > 0.015;
        if (speaking != _lastSpeaking) {
          _lastSpeaking = speaking;
          _ws.sendEvent('rtc.speaking',
              roomId: roomId, payload: {'speaking': speaking});
        }
      } catch (_) {
        // Audio level is optional on some desktop WebRTC backends.
      }
    });
  }

  Future<void> _closePeer({required bool sendLeave}) async {
    _speakerTimer?.cancel();
    _speakerTimer = null;
    final roomId = _connectedRoomId;
    if (sendLeave && roomId != null) {
      _ws.sendEvent('rtc.leave', roomId: roomId);
    }
    final pc = _pc;
    final stream = _localStream;
    _pc = null;
    _localStream = null;
    _localDescriptionSignaled = false;
    _remoteDescriptionSet = false;
    _pendingLocalCandidates.clear();
    _pendingRemoteCandidates.clear();
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

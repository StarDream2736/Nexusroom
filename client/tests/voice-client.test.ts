import { describe, expect, it, vi } from 'vitest';
import type {
  RtcIceServer,
  VoiceClientEvent,
  VoiceEventName,
} from '../src/renderer/nexusroom-client';
import type {
  VoiceAudioElement,
  VoiceMediaDevices,
  VoiceMediaStream,
  VoiceMediaTrack,
  VoicePeerConnection,
  VoicePeerConnectionFactory,
  VoiceSessionDescription,
  VoiceSignaling,
} from '../src/renderer/voice-client';
import {
  fallbackVoiceIceServers,
  parseVoiceIceServers,
  VoiceActivityDetector,
  WebRtcVoiceClient,
} from '../src/renderer/voice-client';
import type {
  WsConnectionState,
  WsMessage,
  WsMessageListener,
} from '../src/main/ws-client';

class FakeSignaling implements VoiceSignaling {
  readonly sent: Array<{ event: VoiceClientEvent; roomId: number; payload: unknown }> = [];
  readonly iceServers: readonly RtcIceServer[] = [];
  private readonly listeners = new Map<VoiceEventName, Set<WsMessageListener>>();
  private readonly stateListeners = new Set<(state: WsConnectionState) => void>();
  private currentState: WsConnectionState = 'connecting';

  constructor(readonly serverUrl = 'https://voice.test:8443') {}

  get connectionState(): WsConnectionState {
    return this.currentState;
  }

  get rtcIceServers(): readonly RtcIceServer[] {
    return this.iceServers;
  }

  onRtcEvent(eventName: VoiceEventName, listener: WsMessageListener): () => void {
    const listeners = this.listeners.get(eventName) ?? new Set<WsMessageListener>();
    listeners.add(listener);
    this.listeners.set(eventName, listeners);
    return () => listeners.delete(listener);
  }

  onConnectionStateChange(listener: (state: WsConnectionState) => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  sendRtc(eventName: VoiceClientEvent, roomId: number, payload?: unknown): void {
    if (this.currentState !== 'connected') throw new Error('socket is disconnected');
    this.sent.push({ event: eventName, roomId, payload });
  }

  setState(state: WsConnectionState): void {
    this.currentState = state;
    for (const listener of [...this.stateListeners]) listener(state);
  }

  connected(payload: unknown = {
    rtc: { ice_servers: [{ urls: 'stun:configured.test:3478' }] },
  }): void {
    this.setState('connected');
    this.emit('connected', payload);
  }

  emit(eventName: VoiceEventName, payload: unknown, roomId?: number): void {
    const message: WsMessage = {
      event: eventName,
      ...(roomId === undefined ? {} : { room_id: roomId }),
      payload,
    };
    for (const listener of [...(this.listeners.get(eventName) ?? [])]) listener(message);
  }
}

class FakeTrack implements VoiceMediaTrack {
  enabled = false;
  stopped = false;
  constructor(readonly kind = 'audio', readonly id = `track-${Math.random()}`) {}
  stop(): void {
    this.stopped = true;
  }
}

class FakeStream implements VoiceMediaStream {
  constructor(readonly tracks: readonly FakeTrack[]) {}
  readonly id = 'stream-1';
  getAudioTracks(): readonly VoiceMediaTrack[] {
    return this.tracks.filter((track) => track.kind === 'audio');
  }
  getTracks(): readonly VoiceMediaTrack[] {
    return this.tracks;
  }
}

class FakeAudioElement implements VoiceAudioElement {
  autoplay = false;
  muted = true;
  playsInline = false;
  srcObject: VoiceMediaStream | null = null;
  removed = false;
  paused = false;
  play = vi.fn(async () => undefined);
  setAttribute(): void {}
  pause(): void {
    this.paused = true;
  }
  remove(): void {
    this.removed = true;
  }
}

class FakePeer implements VoicePeerConnection {
  connectionState = 'connected';
  iceConnectionState = 'connected';
  signalingState = 'stable';
  onicecandidate: VoicePeerConnection['onicecandidate'] = null;
  onconnectionstatechange: VoicePeerConnection['onconnectionstatechange'] = null;
  oniceconnectionstatechange: VoicePeerConnection['oniceconnectionstatechange'] = null;
  ontrack: VoicePeerConnection['ontrack'] = null;
  readonly localDescriptions: VoiceSessionDescription[] = [];
  readonly remoteDescriptions: VoiceSessionDescription[] = [];
  readonly candidates: unknown[] = [];
  readonly transceivers: string[] = [];
  readonly tracks: VoiceMediaTrack[] = [];
  closed = false;
  emitCandidateOnLocalDescription = false;
  private offerNumber = 0;

  async createOffer(): Promise<VoiceSessionDescription> {
    this.offerNumber += 1;
    return { type: 'offer', sdp: `offer-${this.offerNumber}` };
  }

  async createAnswer(): Promise<VoiceSessionDescription> {
    return { type: 'answer', sdp: `answer-${this.remoteDescriptions.length + 1}` };
  }

  async setLocalDescription(description: VoiceSessionDescription): Promise<void> {
    this.localDescriptions.push(description);
    this.signalingState = description.type === 'offer' ? 'have-local-offer' : 'stable';
    if (this.emitCandidateOnLocalDescription && description.type === 'offer') {
      this.onicecandidate?.({ candidate: { candidate: 'local-candidate', sdpMid: '0', sdpMLineIndex: 0 } });
    }
  }

  async setRemoteDescription(description: VoiceSessionDescription): Promise<void> {
    this.remoteDescriptions.push(description);
    this.signalingState = description.type === 'offer' ? 'have-remote-offer' : 'stable';
  }

  async addIceCandidate(candidate: unknown): Promise<void> {
    this.candidates.push(candidate);
  }

  addTrack(track: VoiceMediaTrack): void {
    this.tracks.push(track);
  }

  addTransceiver(): void {
    this.transceivers.push('audio');
  }

  async getStats(): Promise<unknown> {
    return new Map();
  }

  close(): void {
    this.closed = true;
    this.signalingState = 'closed';
  }
}

function settle(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function createVoice(options: {
  readonly mediaDevices?: VoiceMediaDevices;
  readonly audioElement?: FakeAudioElement;
  readonly peerFactory?: VoicePeerConnectionFactory;
} = {}): Promise<{
  readonly voice: WebRtcVoiceClient;
  readonly signaling: FakeSignaling;
  readonly peers: FakePeer[];
}> {
  const signaling = new FakeSignaling();
  const peers: FakePeer[] = [];
  const peerFactory = options.peerFactory ?? (() => {
    const peer = new FakePeer();
    peers.push(peer);
    return peer;
  });
  const voice = new WebRtcVoiceClient({
    signaling,
    peerConnectionFactory: peerFactory,
    mediaDevices: options.mediaDevices,
    audioElementFactory: () => options.audioElement ?? new FakeAudioElement(),
  });
  await voice.setRoom(1);
  signaling.connected();
  await settle();
  return { voice, signaling, peers };
}

describe('WebRtcVoiceClient', () => {
  it('parses configured ICE urls as strings or arrays and falls back by server host', () => {
    expect(parseVoiceIceServers({
      rtc: {
        ice_servers: [
          { urls: 'stun:one.test:3478' },
          { urls: ['turn:two.test:3478?transport=udp'], username: 'u', credential: 'p' },
          { urls: [] },
        ],
      },
    })).toEqual([
      { urls: 'stun:one.test:3478' },
      { urls: ['turn:two.test:3478?transport=udp'], username: 'u', credential: 'p' },
    ]);
    expect(fallbackVoiceIceServers('https://voice.test:8443')).toEqual([
      { urls: 'stun:voice.test:3478' },
    ]);
  });

  it('queues local candidates until the offer is signaled and remote candidates until the answer', async () => {
    const peer = new FakePeer();
    peer.emitCandidateOnLocalDescription = true;
    const { voice, signaling } = await createVoice({ peerFactory: () => peer });

    expect(signaling.sent.slice(0, 2).map((item) => item.event)).toEqual(['rtc.offer', 'rtc.ice']);
    signaling.emit('rtc.ice', {
      candidate: 'remote-before-answer',
      sdp_mid: '0',
      sdp_mline_index: 0,
    }, 1);
    await settle();
    expect(peer.candidates).toHaveLength(0);

    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-1' }, 1);
    await settle();
    expect(peer.candidates).toHaveLength(1);
    await voice.dispose();
  });

  it('answers ordered server offers and keeps a second offer for the next stable state', async () => {
    const { voice, signaling, peers } = await createVoice();
    const peer = peers[0];
    if (peer === undefined) throw new Error('peer was not created');
    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-1' }, 1);
    await settle();
    signaling.emit('rtc.offer', { type: 'answer', sdp: 'invalid-offer' }, 1);
    signaling.emit('rtc.offer', { sdp: 'server-offer-0' }, 1);
    signaling.emit('rtc.offer', { type: 'offer', sdp: 'server-offer-1' }, 1);
    signaling.emit('rtc.offer', { type: 'offer', sdp: 'server-offer-2' }, 1);
    await settle();
    await settle();

    expect(peer.remoteDescriptions.map((item) => item.sdp)).toEqual([
      'answer-1',
      'server-offer-0',
      'server-offer-1',
      'server-offer-2',
    ]);
    expect(signaling.sent.filter((item) => item.event === 'rtc.answer')).toHaveLength(3);
    await voice.dispose();
  });

  it('cleans the old peer immediately on a fast room switch', async () => {
    const { voice, signaling, peers } = await createVoice();
    const firstPeer = peers[0];
    if (firstPeer === undefined) throw new Error('first peer was not created');
    await voice.setRoom(2);
    await settle();

    expect(firstPeer.closed).toBe(true);
    expect(signaling.sent.some((item) => item.event === 'rtc.leave' && item.roomId === 1)).toBe(true);
    expect(voice.snapshot.roomId).toBe(2);
    expect(peers).toHaveLength(2);
    await voice.dispose();
  });

  it('does not reuse a stale microphone promise after switching rooms', async () => {
    const resolvers: Array<(stream: VoiceMediaStream) => void> = [];
    const getUserMedia = vi.fn(() => new Promise<VoiceMediaStream>((resolve) => {
      resolvers.push(resolve);
    }));
    const { voice, signaling, peers } = await createVoice({
      mediaDevices: { getUserMedia },
    });

    const oldOperation = voice.setMicrophoneEnabled(true);
    await Promise.resolve();
    expect(getUserMedia).toHaveBeenCalledTimes(1);

    await voice.setRoom(2);
    const newOperation = voice.setMicrophoneEnabled(true);
    await Promise.resolve();
    expect(getUserMedia).toHaveBeenCalledTimes(2);
    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-2' }, 2);
    await settle();

    const newTrack = new FakeTrack('audio', 'new-track');
    resolvers[1]?.(new FakeStream([newTrack]));
    await newOperation;
    expect(voice.snapshot.microphone).toBe('enabled');
    const newPeer = peers[1];
    if (newPeer === undefined) throw new Error('new peer was not created');
    expect(newPeer.tracks).toHaveLength(1);

    const oldTrack = new FakeTrack('audio', 'old-track');
    resolvers[0]?.(new FakeStream([oldTrack]));
    await expect(oldOperation).rejects.toThrow('语音房间已切换');
    expect(oldTrack.stopped).toBe(true);
    expect(signaling.sent.some((item) => item.event === 'voice.mute' && item.roomId === 1)).toBe(false);

    await voice.setMicrophoneEnabled(false);
    const reopenOperation = voice.setMicrophoneEnabled(true);
    await settle();
    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-2-reopen' }, 2);
    await reopenOperation;
    expect(newPeer.tracks).toHaveLength(1);
    expect(voice.snapshot.microphone).toBe('enabled');
    await voice.dispose();
  });

  it('reconnects only the currently selected room', async () => {
    const { voice, signaling, peers } = await createVoice();
    await voice.setRoom(2);
    await settle();
    signaling.sent.splice(0);
    signaling.setState('disconnected');
    await settle();
    signaling.setState('connecting');
    signaling.connected({ rtc: { ice_servers: [] } });
    await settle();

    expect(signaling.sent.filter((item) => item.event === 'rtc.offer').map((item) => item.roomId)).toEqual([2]);
    expect(peers[0]?.closed).toBe(true);
    await voice.dispose();
  });

  it('marks the button busy immediately, requests the microphone on enable, and rolls back permission failures', async () => {
    const track = new FakeTrack();
    let resolveStream: ((stream: VoiceMediaStream) => void) | undefined;
    const getUserMedia = vi.fn(() => new Promise<VoiceMediaStream>((resolve) => {
      resolveStream = resolve;
    }));
    const mediaDevices: VoiceMediaDevices = { getUserMedia };
    const { voice, signaling } = await createVoice({ mediaDevices });
    const pending = voice.setMicrophoneEnabled(true);
    expect(voice.snapshot.microphone).toBe('enabling');
    await Promise.resolve();
    expect(getUserMedia).toHaveBeenCalledTimes(1);
    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-1' }, 1);
    await settle();
    resolveStream?.(new FakeStream([track]));
    await pending;
    expect(getUserMedia).toHaveBeenCalledTimes(1);
    expect(track.enabled).toBe(true);
    expect(voice.snapshot.microphone).toBe('enabled');
    await voice.dispose();

    const failure = new FakeSignaling();
    const failedVoice = new WebRtcVoiceClient({
      signaling: failure,
      peerConnectionFactory: () => new FakePeer(),
      mediaDevices: { getUserMedia: vi.fn(async () => { throw new Error('Permission denied'); }) },
    });
    await failedVoice.setRoom(3);
    failure.connected();
    await settle();
    failure.emit('rtc.answer', { type: 'answer', sdp: 'answer-1' }, 3);
    await settle();
    await expect(failedVoice.setMicrophoneEnabled(true)).rejects.toThrow('Permission denied');
    expect(failedVoice.snapshot.microphone).toBe('muted');
    expect(failedVoice.snapshot.error).toContain('Permission denied');
    await failedVoice.dispose();
  });

  it('sends speaking=false before mute and stops speaking sampling on mute', async () => {
    const track = new FakeTrack();
    const mediaDevices: VoiceMediaDevices = {
      getUserMedia: vi.fn(async () => new FakeStream([track])),
    };
    const { voice, signaling } = await createVoice({ mediaDevices });
    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-1' }, 1);
    await settle();
    await voice.setMicrophoneEnabled(true);
    await voice.setMicrophoneEnabled(false);

    expect(track.enabled).toBe(false);
    expect(signaling.sent.slice(-2)).toEqual([
      { event: 'rtc.speaking', roomId: 1, payload: { speaking: false } },
      { event: 'voice.mute', roomId: 1, payload: { muted: true } },
    ]);
    await voice.dispose();
  });

  it('uses rtc.participants for presence and ignores state updates for absent voice users', async () => {
    const { voice, signaling } = await createVoice();
    signaling.emit('voice.state_update', { user_id: 7, muted: false, speaking: true }, 1);
    expect(voice.snapshot.participants).toEqual([]);
    signaling.emit('rtc.participants', {
      participants: [
        { user_id: 7, muted: false, speaking: false },
        { user_id: 8, muted: true, speaking: true },
      ],
    }, 1);
    expect(voice.snapshot.participants).toEqual([
      { userId: 7, muted: false, speaking: false },
      { userId: 8, muted: true, speaking: false },
    ]);
    signaling.emit('voice.state_update', { user_id: 7, muted: false, speaking: true }, 1);
    expect(voice.snapshot.participants[0]?.speaking).toBe(true);
    await voice.dispose();
  });

  it('keeps the detector speaking through short pauses and stops after the hold', () => {
    const detector = new VoiceActivityDetector();
    expect(detector.update(0.02)).toBe(true);
    expect(detector.update(0.01)).toBe(true);
    expect(detector.update(0.007)).toBe(true);
    expect(detector.update(0.007)).toBe(true);
    expect(detector.update(0.007)).toBe(true);
    expect(detector.update(0.007)).toBe(true);
    expect(detector.update(0.007)).toBe(false);
  });

  it('plays remote audio and releases audio, microphone, peer, and signals on dispose', async () => {
    const audio = new FakeAudioElement();
    const localTrack = new FakeTrack();
    const mediaDevices: VoiceMediaDevices = {
      getUserMedia: vi.fn(async () => new FakeStream([localTrack])),
    };
    const { voice, signaling, peers } = await createVoice({ mediaDevices, audioElement: audio });
    signaling.emit('rtc.answer', { type: 'answer', sdp: 'answer-1' }, 1);
    await settle();
    const peer = peers[0];
    if (peer === undefined) throw new Error('peer was not created');
    const remoteTrack = new FakeTrack('audio', 'remote-track');
    const remoteStream = new FakeStream([remoteTrack]);
    peer.ontrack?.({ track: remoteTrack, streams: [remoteStream] });
    await voice.setMicrophoneEnabled(true);
    await voice.dispose();

    expect(audio.play).toHaveBeenCalled();
    expect(audio.srcObject).toBeNull();
    expect(audio.removed).toBe(true);
    expect(localTrack.stopped).toBe(true);
    expect(remoteTrack.stopped).toBe(true);
    expect(peer.closed).toBe(true);
    expect(signaling.sent.some((item) => item.event === 'rtc.speaking' && item.payload === undefined)).toBe(false);
    expect(signaling.sent.some((item) => item.event === 'rtc.leave' && item.roomId === 1)).toBe(true);
  });
});

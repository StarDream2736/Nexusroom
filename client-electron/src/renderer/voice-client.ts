import type {
  RtcIceServer,
  VoiceClientEvent,
  VoiceEventName,
} from './nexusroom-client';
import type {
  WsConnectionState,
  WsMessage,
  WsMessageListener,
} from '../main/ws-client';

export type VoiceConnectionState =
  | 'idle'
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'error';

export type VoiceMicrophoneState =
  | 'muted'
  | 'enabling'
  | 'enabled'
  | 'disabling';

export interface VoiceParticipant {
  readonly userId: number;
  readonly muted: boolean;
  readonly speaking: boolean;
}

export interface VoiceSnapshot {
  readonly roomId: number | null;
  readonly connection: VoiceConnectionState;
  readonly microphone: VoiceMicrophoneState;
  readonly participants: readonly VoiceParticipant[];
  readonly error: string | null;
}

export interface VoiceSignaling {
  readonly serverUrl: string;
  readonly connectionState: WsConnectionState;
  readonly rtcIceServers: readonly RtcIceServer[];
  onRtcEvent(eventName: VoiceEventName, listener: WsMessageListener): () => void;
  onConnectionStateChange(listener: (state: WsConnectionState) => void): () => void;
  sendRtc(eventName: VoiceClientEvent, roomId: number, payload?: unknown): void;
}

export interface VoiceMediaTrack {
  readonly kind: string;
  readonly id?: string;
  enabled: boolean;
  stop(): void;
}

export interface VoiceMediaStream {
  readonly id?: string;
  getAudioTracks(): readonly VoiceMediaTrack[];
  getTracks(): readonly VoiceMediaTrack[];
}

export interface VoiceMediaDevices {
  getUserMedia(constraints: unknown): Promise<VoiceMediaStream>;
}

export interface VoiceAudioElement {
  autoplay: boolean;
  muted: boolean;
  playsInline: boolean;
  srcObject: VoiceMediaStream | null;
  setAttribute(name: string, value: string): void;
  play(): Promise<void>;
  pause(): void;
  remove(): void;
}

export interface VoiceSessionDescription {
  readonly type: string;
  readonly sdp: string;
}

export interface VoiceIceCandidateInit {
  readonly candidate: string;
  readonly sdpMid?: string | null;
  readonly sdpMLineIndex?: number | null;
}

export interface VoicePeerConnection {
  readonly connectionState?: string;
  readonly iceConnectionState?: string;
  readonly signalingState?: string;
  onicecandidate: ((event: VoiceIceCandidateEvent) => void) | null;
  onconnectionstatechange: (() => void) | null;
  oniceconnectionstatechange: (() => void) | null;
  ontrack: ((event: VoiceTrackEvent) => void) | null;
  createOffer(options?: Record<string, unknown>): Promise<VoiceSessionDescription>;
  createAnswer(options?: Record<string, unknown>): Promise<VoiceSessionDescription>;
  setLocalDescription(description: VoiceSessionDescription): Promise<void>;
  setRemoteDescription(description: VoiceSessionDescription): Promise<void>;
  addIceCandidate(candidate: VoiceIceCandidateInit): Promise<void>;
  addTrack(track: VoiceMediaTrack, stream: VoiceMediaStream): unknown;
  addTransceiver(kind: 'audio', init: { readonly direction: 'recvonly' }): unknown;
  getStats(): Promise<unknown>;
  close(): Promise<void> | void;
}

export interface VoiceIceCandidateEvent {
  readonly candidate: {
    readonly candidate?: string;
    readonly sdpMid?: string | null;
    readonly sdpMLineIndex?: number | null;
  } | null;
}

export interface VoiceTrackEvent {
  readonly track: VoiceMediaTrack;
  readonly streams?: readonly VoiceMediaStream[];
}

export interface VoicePeerConnectionFactory {
  (configuration: { readonly iceServers: readonly RtcIceServer[] }): VoicePeerConnection;
}

export interface VoiceAudioElementFactory {
  (): VoiceAudioElement;
}

export interface VoiceMediaStreamFactory {
  (track: VoiceMediaTrack): VoiceMediaStream;
}

export interface VoiceClientOptions {
  readonly signaling: VoiceSignaling;
  readonly peerConnectionFactory?: VoicePeerConnectionFactory;
  readonly mediaDevices?: VoiceMediaDevices;
  readonly audioElementFactory?: VoiceAudioElementFactory;
  readonly mediaStreamFactory?: VoiceMediaStreamFactory;
  readonly appendAudioElement?: (element: VoiceAudioElement) => void;
  readonly statsIntervalMs?: number;
  readonly connectionTimeoutMs?: number;
}

export class VoiceClientError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VoiceClientError';
  }
}

export class VoiceActivityDetector {
  readonly startThreshold: number;
  readonly stopThreshold: number;
  readonly silenceSamplesToStop: number;
  private active = false;
  private silentSamples = 0;

  constructor(options: {
    readonly startThreshold?: number;
    readonly stopThreshold?: number;
    readonly silenceSamplesToStop?: number;
  } = {}) {
    this.startThreshold = options.startThreshold ?? 0.018;
    this.stopThreshold = options.stopThreshold ?? 0.008;
    this.silenceSamplesToStop = options.silenceSamplesToStop ?? 5;
  }

  get speaking(): boolean {
    return this.active;
  }

  update(level: number): boolean {
    const normalizedLevel = Number.isFinite(level) ? Math.max(0, level) : 0;
    if (normalizedLevel > this.startThreshold) {
      this.active = true;
      this.silentSamples = 0;
    } else if (this.active && normalizedLevel < this.stopThreshold) {
      this.silentSamples += 1;
      if (this.silentSamples >= this.silenceSamplesToStop) {
        this.active = false;
        this.silentSamples = 0;
      }
    } else if (this.active) {
      this.silentSamples = 0;
    }
    return this.active;
  }

  reset(): void {
    this.active = false;
    this.silentSamples = 0;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function readPayload(message: WsMessage): Record<string, unknown> {
  const payload = isRecord(message.payload) ? { ...message.payload } : {};
  if (message.room_id !== undefined && payload.room_id === undefined) {
    payload.room_id = message.room_id;
  }
  return payload;
}

function readRoomId(message: WsMessage): number | null {
  const payload = readPayload(message);
  const roomId = payload.room_id;
  return Number.isSafeInteger(roomId) && (roomId as number) > 0
    ? roomId as number
    : null;
}

function readString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function readBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function readSessionDescription(
  message: WsMessage,
  expectedType: 'offer' | 'answer',
): VoiceSessionDescription | null {
  const payload = readPayload(message);
  const sdp = readString(payload.sdp);
  if (sdp === null) return null;
  const type = payload.type === expectedType ? expectedType : expectedType;
  return { type, sdp };
}

function normalizeIceServer(value: unknown): RtcIceServer | null {
  if (!isRecord(value)) return null;
  const rawUrls = value.urls;
  const urls = typeof rawUrls === 'string'
    ? rawUrls.trim()
    : Array.isArray(rawUrls)
      ? rawUrls.filter((url): url is string => typeof url === 'string' && url.trim().length > 0)
        .map((url) => url.trim())
      : [];
  if ((typeof urls === 'string' && urls.length === 0) || (Array.isArray(urls) && urls.length === 0)) {
    return null;
  }
  const username = typeof value.username === 'string' && value.username.length > 0
    ? value.username
    : undefined;
  const credential = typeof value.credential === 'string' && value.credential.length > 0
    ? value.credential
    : undefined;
  return {
    urls,
    ...(username === undefined ? {} : { username }),
    ...(credential === undefined ? {} : { credential }),
  };
}

export function parseVoiceIceServers(value: unknown): readonly RtcIceServer[] {
  const root = isRecord(value) && isRecord(value.rtc) ? value.rtc : value;
  const rawServers = isRecord(root) ? root.ice_servers : undefined;
  if (!Array.isArray(rawServers)) return [];
  return rawServers.flatMap((server) => {
    const normalized = normalizeIceServer(server);
    return normalized === null ? [] : [normalized];
  });
}

export function fallbackVoiceIceServers(serverUrl: string): readonly RtcIceServer[] {
  let host = '127.0.0.1';
  try {
    host = new URL(serverUrl).hostname || host;
  } catch {
    // NexusRoomClient validates the URL; keep a safe local fallback for tests.
  }
  if (host.includes(':') && !host.startsWith('[')) host = `[${host}]`;
  return [{ urls: `stun:${host}:3478` }];
}

function defaultPeerConnectionFactory(
  configuration: { readonly iceServers: readonly RtcIceServer[] },
): VoicePeerConnection {
  if (typeof globalThis.RTCPeerConnection !== 'function') {
    throw new VoiceClientError('当前 Electron 运行时不支持 WebRTC');
  }
  return new globalThis.RTCPeerConnection({
    iceServers: configuration.iceServers as RTCIceServer[],
  }) as unknown as VoicePeerConnection;
}

function defaultMediaDevices(): VoiceMediaDevices | undefined {
  if (typeof navigator === 'undefined' || navigator.mediaDevices === undefined) return undefined;
  return navigator.mediaDevices as unknown as VoiceMediaDevices;
}

function defaultAudioElementFactory(): VoiceAudioElement {
  if (typeof document === 'undefined') {
    throw new VoiceClientError('当前 Electron 运行时不支持远端语音播放');
  }
  return document.createElement('audio') as unknown as VoiceAudioElement;
}

function defaultMediaStreamFactory(track: VoiceMediaTrack): VoiceMediaStream {
  if (typeof globalThis.MediaStream !== 'function') {
    throw new VoiceClientError('当前 Electron 运行时不支持远端音频轨道');
  }
  return new globalThis.MediaStream([track as unknown as MediaStreamTrack]) as unknown as VoiceMediaStream;
}

function defaultAppendAudioElement(element: VoiceAudioElement): void {
  if (typeof document === 'undefined' || document.body === null) return;
  document.body.appendChild(element as unknown as Node);
}

function readStatNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function statReports(value: unknown): readonly Record<string, unknown>[] {
  const reports: Record<string, unknown>[] = [];
  if (isRecord(value) && typeof value.forEach === 'function') {
    value.forEach((report: unknown) => {
      if (isRecord(report)) reports.push(report);
    });
    return reports;
  }
  if (isRecord(value) && Symbol.iterator in value && typeof value[Symbol.iterator] === 'function') {
    for (const entry of value as unknown as Iterable<unknown>) {
      const report = Array.isArray(entry) ? entry[1] : entry;
      if (isRecord(report)) reports.push(report);
    }
    return reports;
  }
  if (Array.isArray(value)) return value.filter(isRecord);
  return reports;
}

function isLocalAudioReport(report: Record<string, unknown>): boolean {
  const kind = report.kind ?? report.mediaType;
  if (typeof kind === 'string' && kind !== 'audio') return false;
  const type = typeof report.type === 'string' ? report.type : undefined;
  if (type === 'inbound-rtp' || report.remoteSource === true) return false;
  return type === undefined || type === 'media-source' || type === 'outbound-rtp'
    || type === 'sender' || type === 'track';
}

function reportValues(report: Record<string, unknown>): Record<string, unknown> {
  const nested = isRecord(report.values) ? report.values : {};
  return { ...nested, ...report };
}

function safeErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof VoiceClientError) return error.message;
  if (error instanceof Error && error.message.length > 0) return error.message;
  return fallback;
}

interface ReadyWaiter {
  readonly generation: number;
  readonly roomId: number;
  readonly resolve: () => void;
  readonly reject: (error: Error) => void;
  readonly timer: ReturnType<typeof setTimeout>;
}

interface LocalNegotiationWaiter {
  readonly resolve: () => void;
  readonly reject: (error: Error) => void;
}

interface RemoteAudio {
  readonly element: VoiceAudioElement;
  stream: VoiceMediaStream;
}

export class WebRtcVoiceClient {
  private readonly signaling: VoiceSignaling;
  private readonly peerConnectionFactory: VoicePeerConnectionFactory;
  private readonly mediaDevices: VoiceMediaDevices | undefined;
  private readonly audioElementFactory: VoiceAudioElementFactory;
  private readonly mediaStreamFactory: VoiceMediaStreamFactory;
  private readonly appendAudioElement: (element: VoiceAudioElement) => void;
  private readonly statsIntervalMs: number;
  private readonly connectionTimeoutMs: number;
  private readonly activity = new VoiceActivityDetector();
  private readonly listeners = new Set<(snapshot: VoiceSnapshot) => void>();
  private readonly remoteAudio = new Map<string, RemoteAudio>();
  private readonly localTracksAdded = new Set<VoiceMediaTrack>();
  private readonly readyWaiters = new Set<ReadyWaiter>();
  private readonly localNegotiationWaiters: LocalNegotiationWaiter[] = [];
  private readonly offSignals: Array<() => void> = [];
  private readonly retryAudioPlayback = (): void => {
    for (const [key, audio] of this.remoteAudio) {
      void audio.element.play().then(() => {
        this.blockedAudio.delete(key);
      }).catch(() => undefined);
    }
  };
  private readonly beforeUnload = (): void => {
    void this.dispose();
  };
  private snapshotValue: VoiceSnapshot = {
    roomId: null,
    connection: 'idle',
    microphone: 'muted',
    participants: [],
    error: null,
  };
  private desiredRoomId: number | null = null;
  private activeRoomId: number | null = null;
  private generation = 0;
  private lifecycle: Promise<void> = Promise.resolve();
  private peer: VoicePeerConnection | null = null;
  private localStream: VoiceMediaStream | null = null;
  private speakerTimer: ReturnType<typeof setInterval> | null = null;
  private statsSampleInProgress = false;
  private previousAudioEnergy: number | null = null;
  private previousAudioDuration: number | null = null;
  private localDescriptionSignaled = false;
  private remoteDescriptionSet = false;
  private localOfferPending = false;
  private remoteOfferQueue: VoiceSessionDescription[] = [];
  private processingRemoteOffers = false;
  private localNegotiationPending = false;
  private readonly blockedAudio = new Set<string>();
  private audioSequence = 0;
  private microphoneOperation: Promise<void> | null = null;
  private connectedHandshake = false;
  private disposed = false;

  constructor(options: VoiceClientOptions) {
    this.signaling = options.signaling;
    this.peerConnectionFactory = options.peerConnectionFactory ?? defaultPeerConnectionFactory;
    this.mediaDevices = options.mediaDevices ?? defaultMediaDevices();
    this.audioElementFactory = options.audioElementFactory ?? defaultAudioElementFactory;
    this.mediaStreamFactory = options.mediaStreamFactory ?? defaultMediaStreamFactory;
    this.appendAudioElement = options.appendAudioElement ?? defaultAppendAudioElement;
    this.statsIntervalMs = options.statsIntervalMs ?? 200;
    this.connectionTimeoutMs = options.connectionTimeoutMs ?? 12_000;
    if (!Number.isFinite(this.statsIntervalMs) || this.statsIntervalMs <= 0) {
      throw new VoiceClientError('语音采样间隔无效');
    }
    if (!Number.isFinite(this.connectionTimeoutMs) || this.connectionTimeoutMs <= 0) {
      throw new VoiceClientError('语音连接超时无效');
    }

    this.offSignals.push(
      this.signaling.onRtcEvent('connected', (message) => this.handleConnected(message)),
      this.signaling.onRtcEvent('rtc.answer', (message) => { void this.handleAnswer(message); }),
      this.signaling.onRtcEvent('rtc.offer', (message) => { void this.handleOffer(message); }),
      this.signaling.onRtcEvent('rtc.ice', (message) => { void this.handleCandidate(message); }),
      this.signaling.onRtcEvent('rtc.participants', (message) => this.handleParticipants(message)),
      this.signaling.onRtcEvent('rtc.state', (message) => this.handleRtcState(message)),
      this.signaling.onRtcEvent('rtc.error', (message) => this.handleRtcError(message)),
      this.signaling.onRtcEvent('voice.state_update', (message) => this.handleVoiceStateUpdate(message)),
      this.signaling.onConnectionStateChange((state) => this.handleSocketState(state)),
    );
    if (typeof document !== 'undefined') {
      document.addEventListener('pointerdown', this.retryAudioPlayback);
      document.addEventListener('keydown', this.retryAudioPlayback);
    }
    if (typeof window !== 'undefined') {
      window.addEventListener('beforeunload', this.beforeUnload);
      window.addEventListener('pagehide', this.beforeUnload);
    }
  }

  get snapshot(): VoiceSnapshot {
    return this.snapshotValue;
  }

  onChange(listener: (snapshot: VoiceSnapshot) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  setRoom(roomId: number | null): Promise<void> {
    if (this.disposed) return Promise.reject(new VoiceClientError('语音服务已释放'));
    if (roomId !== null && (!Number.isSafeInteger(roomId) || roomId < 1)) {
      return Promise.reject(new VoiceClientError('语音房间号无效'));
    }
    this.desiredRoomId = roomId;
    const generation = ++this.generation;
    const cleanup = this.cleanupPeer(true);
    const previous = this.lifecycle.catch(() => undefined);
    const operation = previous
      .then(() => cleanup)
      .then(async () => {
        if (!this.isCurrent(generation, roomId)) return;
        if (roomId === null) {
          this.setSnapshot({ roomId: null, connection: 'idle', error: null });
          return;
        }
        this.setSnapshot({ roomId, connection: 'connecting', error: null });
        if (this.signaling.connectionState !== 'connected' || !this.connectedHandshake) return;
        await this.startRoom(roomId, generation);
      })
      .catch(async (error: unknown) => {
        if (!this.isCurrent(generation, roomId)) return;
        const message = safeErrorMessage(error, '语音连接失败，请稍后重试');
        this.setSnapshot({ connection: 'error', error: message });
        await this.cleanupPeer(true);
        throw error;
      });
    this.lifecycle = operation.catch(() => undefined);
    return operation;
  }

  setMicrophoneEnabled(enabled: boolean): Promise<void> {
    if (this.microphoneOperation !== null) return this.microphoneOperation;
    const operation = enabled
      ? this.enableMicrophone()
      : this.disableMicrophone();
    const trackedOperation = operation.finally(() => {
      if (this.microphoneOperation === trackedOperation) this.microphoneOperation = null;
    });
    this.microphoneOperation = trackedOperation;
    return trackedOperation;
  }

  async dispose(): Promise<void> {
    if (this.disposed) return this.lifecycle;
    this.disposed = true;
    this.desiredRoomId = null;
    ++this.generation;
    for (const off of this.offSignals.splice(0)) off();
    if (typeof document !== 'undefined') {
      document.removeEventListener('pointerdown', this.retryAudioPlayback);
      document.removeEventListener('keydown', this.retryAudioPlayback);
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('beforeunload', this.beforeUnload);
      window.removeEventListener('pagehide', this.beforeUnload);
    }
    const cleanup = this.cleanupPeer(true);
    const previous = this.lifecycle.catch(() => undefined);
    this.lifecycle = previous.then(() => cleanup).catch(() => undefined);
    await this.lifecycle;
    this.listeners.clear();
  }

  private handleConnected(message: WsMessage): void {
    if (this.disposed) return;
    this.connectedHandshake = true;
    const configured = parseVoiceIceServers(message.payload);
    this.iceServersValue = configured.length > 0
      ? configured
      : this.signaling.rtcIceServers.length > 0
        ? this.signaling.rtcIceServers
        : fallbackVoiceIceServers(this.signaling.serverUrl);
    this.scheduleStart();
  }

  private iceServersValue: readonly RtcIceServer[] = [];

  private handleSocketState(state: WsConnectionState): void {
    if (this.disposed) return;
    if (state === 'disconnected') {
      this.connectedHandshake = false;
      ++this.generation;
      this.activeRoomId = null;
      this.rejectReadyWaiters(new VoiceClientError('WebSocket 已断开'));
      void this.cleanupPeer(false);
      this.setSnapshot({
        connection: this.desiredRoomId === null ? 'idle' : 'reconnecting',
        participants: [],
        microphone: 'muted',
      });
      return;
    }
    if (state === 'connecting' && this.desiredRoomId !== null) {
      this.setSnapshot({ connection: 'connecting', participants: [], microphone: 'muted' });
    }
  }

  private scheduleStart(): void {
    const roomId = this.desiredRoomId;
    if (roomId === null || this.signaling.connectionState !== 'connected') return;
    const generation = ++this.generation;
    const cleanup = this.cleanupPeer(false);
    const previous = this.lifecycle.catch(() => undefined);
    const operation = previous
      .then(() => cleanup)
      .then(async () => {
        if (!this.isCurrent(generation, roomId) || !this.connectedHandshake) return;
        await this.startRoom(roomId, generation);
      })
      .catch(async (error: unknown) => {
        if (!this.isCurrent(generation, roomId)) return;
        this.setSnapshot({ connection: 'error', error: safeErrorMessage(error, '语音连接失败，请稍后重试') });
        await this.cleanupPeer(true);
      });
    this.lifecycle = operation.catch(() => undefined);
  }

  private async startRoom(roomId: number, generation: number): Promise<void> {
    if (!this.isCurrent(generation, roomId)) return;
    this.activeRoomId = roomId;
    const configuredIceServers = this.iceServersValue.length > 0
      ? this.iceServersValue
      : this.signaling.rtcIceServers.length > 0
        ? this.signaling.rtcIceServers
        : fallbackVoiceIceServers(this.signaling.serverUrl);
    const peer = this.peerConnectionFactory({ iceServers: configuredIceServers });
    if (!this.isCurrent(generation, roomId)) {
      await this.closePeer(peer);
      return;
    }
    this.peer = peer;
    this.localDescriptionSignaled = false;
    this.remoteDescriptionSet = false;
    this.localOfferPending = true;
    this.remoteOfferQueue = [];
    this.bindPeer(peer, generation, roomId);

    for (let index = 0; index < 7; index += 1) {
      peer.addTransceiver('audio', { direction: 'recvonly' });
    }
    const offer = await peer.createOffer({ offerToReceiveAudio: true });
    await peer.setLocalDescription({ type: 'offer', sdp: offer.sdp });
    if (!this.isCurrent(generation, roomId)) return;
    this.signaling.sendRtc('rtc.offer', roomId, {
      type: 'offer',
      sdp: offer.sdp,
    });
    this.localDescriptionSignaled = true;
    await this.flushLocalCandidates(generation, roomId);
  }

  private bindPeer(peer: VoicePeerConnection, generation: number, roomId: number): void {
    peer.onicecandidate = (event) => {
      if (!this.isCurrent(generation, roomId) || event.candidate === null) return;
      const candidate = event.candidate.candidate;
      if (typeof candidate !== 'string' || candidate.length === 0) return;
      const payload: VoiceIceCandidateInit = {
        candidate,
        ...(event.candidate.sdpMid === undefined ? {} : { sdpMid: event.candidate.sdpMid }),
        ...(event.candidate.sdpMLineIndex === undefined
          ? {}
          : { sdpMLineIndex: event.candidate.sdpMLineIndex }),
      };
      if (!this.localDescriptionSignaled) {
        this.pendingLocalCandidates.push(payload);
        return;
      }
      try {
        this.signaling.sendRtc('rtc.ice', roomId, {
          candidate: payload.candidate,
          ...(payload.sdpMid === undefined ? {} : { sdp_mid: payload.sdpMid }),
          ...(payload.sdpMLineIndex === undefined ? {} : { sdp_mline_index: payload.sdpMLineIndex }),
        });
      } catch (error) {
        this.setSnapshot({ connection: 'error', error: safeErrorMessage(error, '本地网络候选发送失败') });
      }
    };
    peer.onconnectionstatechange = () => {
      if (!this.isCurrent(generation, roomId)) return;
      this.updatePeerConnectionState(peer.connectionState);
    };
    peer.oniceconnectionstatechange = () => {
      if (!this.isCurrent(generation, roomId)) return;
      this.updatePeerConnectionState(peer.iceConnectionState);
    };
    peer.ontrack = (event) => {
      if (this.isCurrent(generation, roomId)) this.handleRemoteTrack(event);
    };
  }

  private updatePeerConnectionState(state: string | undefined): void {
    if (state === 'connected' || state === 'completed') {
      this.setSnapshot({ connection: 'connected', error: null });
      this.resolveReadyWaiters();
    } else if (state === 'failed' || state === 'disconnected') {
      this.setSnapshot({ connection: 'reconnecting' });
    } else if (state === 'closed') {
      this.setSnapshot({ connection: 'reconnecting' });
    }
  }

  private async handleAnswer(message: WsMessage): Promise<void> {
    const roomId = readRoomId(message);
    const peer = this.peer;
    const generation = this.generation;
    if (roomId === null || roomId !== this.activeRoomId || peer === null) return;
    const description = readSessionDescription(message, 'answer');
    if (description === null) return;
    try {
      await peer.setRemoteDescription(description);
      if (!this.isCurrent(generation, roomId)) return;
      this.remoteDescriptionSet = true;
      this.localOfferPending = false;
      await this.flushRemoteCandidates(peer, generation, roomId);
      await this.processRemoteOffers(generation, roomId);
      this.flushLocalNegotiation(generation, roomId);
    } catch (error) {
      if (this.isCurrent(generation, roomId)) {
        this.setSnapshot({ connection: 'error', error: safeErrorMessage(error, 'RTC 应答处理失败') });
      }
    }
  }

  private async handleOffer(message: WsMessage): Promise<void> {
    const roomId = readRoomId(message);
    if (roomId === null || roomId !== this.activeRoomId || this.peer === null) return;
    const description = readSessionDescription(message, 'offer');
    if (description === null) return;
    this.remoteOfferQueue.push(description);
    this.remoteDescriptionSet = false;
    await this.processRemoteOffers(this.generation, roomId);
  }

  private async processRemoteOffers(generation: number, roomId: number): Promise<void> {
    if (this.processingRemoteOffers) return;
    this.processingRemoteOffers = true;
    try {
      while (this.remoteOfferQueue.length > 0) {
        const peer = this.peer;
        if (!this.isCurrent(generation, roomId) || peer === null) return;
        if (this.localOfferPending || peer.signalingState !== undefined && peer.signalingState !== 'stable') return;
        const offer = this.remoteOfferQueue.shift();
        if (offer === undefined) return;
        await peer.setRemoteDescription(offer);
        if (!this.isCurrent(generation, roomId)) return;
        this.remoteDescriptionSet = true;
        await this.flushRemoteCandidates(peer, generation, roomId);
        const answer = await peer.createAnswer();
        await peer.setLocalDescription({ type: 'answer', sdp: answer.sdp });
        await this.flushRemoteCandidates(peer, generation, roomId);
        this.signaling.sendRtc('rtc.answer', roomId, {
          type: 'answer',
          sdp: answer.sdp,
        });
      }
    } catch (error) {
      if (this.isCurrent(generation, roomId)) {
        this.setSnapshot({ connection: 'error', error: safeErrorMessage(error, 'RTC 重协商失败') });
      }
    } finally {
      this.processingRemoteOffers = false;
      this.flushLocalNegotiation(generation, roomId);
    }
  }

  private async handleCandidate(message: WsMessage): Promise<void> {
    const roomId = readRoomId(message);
    const peer = this.peer;
    const generation = this.generation;
    if (roomId === null || roomId !== this.activeRoomId || peer === null) return;
    const payload = readPayload(message);
    const candidate = readString(payload.candidate);
    if (candidate === null) return;
    const normalized: VoiceIceCandidateInit = {
      candidate,
      ...(typeof payload.sdp_mid === 'string' || payload.sdp_mid === null
        ? { sdpMid: payload.sdp_mid }
        : {}),
      ...(Number.isInteger(payload.sdp_mline_index) || payload.sdp_mline_index === null
        ? { sdpMLineIndex: payload.sdp_mline_index as number | null }
        : {}),
    };
    if (
      !this.remoteDescriptionSet ||
      this.localOfferPending ||
      this.processingRemoteOffers ||
      this.remoteOfferQueue.length > 0
    ) {
      this.pendingRemoteCandidates.push(normalized);
      return;
    }
    try {
      await peer.addIceCandidate(normalized);
    } catch (error) {
      if (this.isCurrent(generation, roomId)) {
        this.setSnapshot({ connection: 'error', error: safeErrorMessage(error, '远端网络候选处理失败') });
      }
    }
  }

  private async flushRemoteCandidates(
    peer: VoicePeerConnection,
    generation: number,
    roomId: number,
  ): Promise<void> {
    const pending = this.pendingRemoteCandidates.splice(0);
    for (const candidate of pending) {
      if (!this.isCurrent(generation, roomId)) return;
      await peer.addIceCandidate(candidate);
    }
  }

  private async flushLocalCandidates(generation: number, roomId: number): Promise<void> {
    const pending = this.pendingLocalCandidates.splice(0);
    for (const candidate of pending) {
      if (!this.isCurrent(generation, roomId)) return;
      this.signaling.sendRtc('rtc.ice', roomId, {
        candidate: candidate.candidate,
        ...(candidate.sdpMid === undefined ? {} : { sdp_mid: candidate.sdpMid }),
        ...(candidate.sdpMLineIndex === undefined ? {} : { sdp_mline_index: candidate.sdpMLineIndex }),
      });
    }
  }

  private readonly pendingLocalCandidates: VoiceIceCandidateInit[] = [];
  private readonly pendingRemoteCandidates: VoiceIceCandidateInit[] = [];

  private handleParticipants(message: WsMessage): void {
    if (!this.isCurrentRoomMessage(message)) return;
    const payload = readPayload(message);
    if (!Array.isArray(payload.participants)) return;
    const participants = new Map<number, VoiceParticipant>();
    for (const value of payload.participants) {
      if (!isRecord(value) || !Number.isSafeInteger(value.user_id) || (value.user_id as number) < 1) continue;
      const userId = value.user_id as number;
      const muted = readBoolean(value.muted, true);
      participants.set(userId, {
        userId,
        muted,
        speaking: readBoolean(value.speaking, false) && !muted,
      });
    }
    this.setSnapshot({ participants: [...participants.values()] });
  }

  private handleVoiceStateUpdate(message: WsMessage): void {
    if (!this.isCurrentRoomMessage(message)) return;
    const payload = readPayload(message);
    if (!Number.isSafeInteger(payload.user_id) || (payload.user_id as number) < 1) return;
    const userId = payload.user_id as number;
    const current = this.snapshotValue.participants.find((participant) => participant.userId === userId);
    if (current === undefined) return;
    const muted = readBoolean(payload.muted, current.muted);
    const speaking = readBoolean(payload.speaking, current.speaking) && !muted;
    this.setSnapshot({
      participants: this.snapshotValue.participants.map((participant) => participant.userId === userId
        ? { ...participant, muted, speaking }
        : participant),
    });
  }

  private handleRtcState(message: WsMessage): void {
    if (!this.isCurrentRoomMessage(message)) return;
    const state = readString(readPayload(message).state);
    this.updatePeerConnectionState(state ?? undefined);
  }

  private handleRtcError(message: WsMessage): void {
    if (!this.isCurrentRoomMessage(message)) return;
    const payload = readPayload(message);
    const messageText = readString(payload.message) ?? readString(payload.reason) ?? 'RTC 连接失败';
    this.setSnapshot({ connection: 'error', error: messageText });
  }

  private isCurrentRoomMessage(message: WsMessage): boolean {
    const roomId = readRoomId(message);
    return roomId !== null && roomId === this.desiredRoomId;
  }

  private async enableMicrophone(): Promise<void> {
    const roomId = this.desiredRoomId;
    const generation = this.generation;
    if (roomId === null) throw this.failMicrophone('请先选择房间');
    this.setSnapshot({ microphone: 'enabling', error: null });
    let stream: VoiceMediaStream | null = null;
    try {
      if (this.localStream === null) {
        if (this.mediaDevices === undefined) throw new VoiceClientError('当前环境没有可用的麦克风接口');
        stream = await this.mediaDevices.getUserMedia({
          audio: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
          video: false,
        });
        if (!this.isCurrent(generation, roomId)) {
          this.stopStream(stream);
          stream = null;
          throw new VoiceClientError('语音房间已切换');
        }
        this.localStream = stream;
      }
      await this.waitForReady(roomId, generation);
      if (!this.isCurrent(generation, roomId) || this.peer === null) {
        throw new VoiceClientError('语音房间已切换');
      }
      const tracks = this.localStream.getAudioTracks();
      if (tracks.length === 0) throw new VoiceClientError('没有检测到可用的麦克风轨道');
      for (const track of tracks) {
        track.enabled = true;
        if (!this.localTracksAdded.has(track)) {
          this.peer.addTrack(track, this.localStream);
          this.localTracksAdded.add(track);
        }
      }
      await this.requestLocalNegotiation(generation, roomId);
      if (!this.isCurrent(generation, roomId)) return;
      this.signaling.sendRtc('voice.mute', roomId, { muted: false });
      this.startSnapshotSampling();
      this.setSnapshot({ microphone: 'enabled', connection: 'connected', error: null });
    } catch (error) {
      if (stream !== null) {
        if (this.localStream === stream) this.localStream = null;
        this.stopStream(stream);
        this.localTracksAdded.clear();
      }
      if (this.isCurrent(generation, roomId)) {
        const tracks = this.localStream?.getAudioTracks() ?? [];
        for (const track of tracks) track.enabled = false;
        this.stopSnapshotSampling();
        this.activity.reset();
        this.setSnapshot({
          microphone: 'muted',
          error: `开麦失败：${safeErrorMessage(error, '请检查麦克风权限')}`,
        });
      }
      throw error;
    }
  }

  private async disableMicrophone(): Promise<void> {
    const roomId = this.activeRoomId;
    const tracks = this.localStream?.getAudioTracks() ?? [];
    if (roomId === null || tracks.length === 0) {
      this.setSnapshot({ microphone: 'muted' });
      return;
    }
    const previous = tracks.map((track) => track.enabled);
    this.setSnapshot({ microphone: 'disabling', error: null });
    for (const track of tracks) track.enabled = false;
    this.stopSnapshotSampling();
    this.activity.reset();
    try {
      this.signaling.sendRtc('rtc.speaking', roomId, { speaking: false });
      this.signaling.sendRtc('voice.mute', roomId, { muted: true });
      this.setSnapshot({ microphone: 'muted', connection: this.snapshotValue.connection });
    } catch (error) {
      tracks.forEach((track, index) => { track.enabled = previous[index] ?? true; });
      this.startSnapshotSampling();
      this.setSnapshot({ microphone: 'enabled', error: safeErrorMessage(error, '静音状态同步失败，请重试') });
      throw error;
    }
  }

  private failMicrophone(message: string): VoiceClientError {
    const error = new VoiceClientError(message);
    this.setSnapshot({ microphone: 'muted', error: message });
    return error;
  }

  private waitForReady(roomId: number, generation: number): Promise<void> {
    if (
      this.peer !== null &&
      (this.snapshotValue.connection === 'connected' || this.peer.connectionState === 'connected')
    ) return Promise.resolve();
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.readyWaiters.delete(waiter);
        reject(new VoiceClientError('语音连接超时，请检查网络和 UDP 端口'));
      }, this.connectionTimeoutMs);
      const waiter: ReadyWaiter = { generation, roomId, resolve, reject, timer };
      this.readyWaiters.add(waiter);
    });
  }

  private resolveReadyWaiters(): void {
    for (const waiter of [...this.readyWaiters]) {
      clearTimeout(waiter.timer);
      this.readyWaiters.delete(waiter);
      waiter.resolve();
    }
  }

  private rejectReadyWaiters(error: Error): void {
    for (const waiter of [...this.readyWaiters]) {
      clearTimeout(waiter.timer);
      this.readyWaiters.delete(waiter);
      waiter.reject(error);
    }
  }

  private requestLocalNegotiation(generation: number, roomId: number): Promise<void> {
    if (this.canCreateLocalOffer()) return this.createLocalOffer(generation, roomId);
    this.localNegotiationPending = true;
    return new Promise<void>((resolve, reject) => {
      this.localNegotiationWaiters.push({ resolve, reject });
      this.flushLocalNegotiation(generation, roomId);
    });
  }

  private canCreateLocalOffer(): boolean {
    return this.peer !== null
      && !this.localOfferPending
      && !this.processingRemoteOffers
      && (this.peer.signalingState === undefined || this.peer.signalingState === 'stable');
  }

  private async createLocalOffer(generation: number, roomId: number): Promise<void> {
    const peer = this.peer;
    if (!this.isCurrent(generation, roomId) || peer === null) {
      throw new VoiceClientError('语音房间已切换');
    }
    this.localOfferPending = true;
    const offer = await peer.createOffer({ offerToReceiveAudio: true });
    await peer.setLocalDescription({ type: 'offer', sdp: offer.sdp });
    if (!this.isCurrent(generation, roomId)) return;
    this.signaling.sendRtc('rtc.offer', roomId, { type: 'offer', sdp: offer.sdp });
    this.localDescriptionSignaled = true;
    await this.flushLocalCandidates(generation, roomId);
  }

  private flushLocalNegotiation(generation: number, roomId: number): void {
    if (!this.localNegotiationPending || !this.canCreateLocalOffer()) return;
    this.localNegotiationPending = false;
    const waiters = this.localNegotiationWaiters.splice(0);
    void this.createLocalOffer(generation, roomId).then(() => {
      waiters.forEach((waiter) => waiter.resolve());
    }).catch((error: unknown) => {
      waiters.forEach((waiter) => waiter.reject(error instanceof Error ? error : new VoiceClientError('RTC 重协商失败')));
    });
  }

  private startSnapshotSampling(): void {
    if (this.speakerTimer !== null) return;
    this.previousAudioEnergy = null;
    this.previousAudioDuration = null;
    this.speakerTimer = setInterval(() => { void this.sampleSpeaking(); }, this.statsIntervalMs);
  }

  private stopSnapshotSampling(): void {
    if (this.speakerTimer !== null) {
      clearInterval(this.speakerTimer);
      this.speakerTimer = null;
    }
    this.statsSampleInProgress = false;
    this.previousAudioEnergy = null;
    this.previousAudioDuration = null;
  }

  private async sampleSpeaking(): Promise<void> {
    const peer = this.peer;
    const roomId = this.activeRoomId;
    if (
      peer === null ||
      roomId === null ||
      this.snapshotValue.microphone !== 'enabled' ||
      this.statsSampleInProgress
    ) return;
    this.statsSampleInProgress = true;
    try {
      const reports = statReports(await peer.getStats());
      let level = 0;
      let totalEnergy = 0;
      let totalDuration = 0;
      for (const report of reports) {
        if (!isLocalAudioReport(report)) continue;
        const values = reportValues(report);
        const standardLevel = readStatNumber(values.audioLevel);
        if (standardLevel !== null) level = Math.max(level, Math.min(1, Math.max(0, standardLevel)));
        const legacyLevel = readStatNumber(values.googAudioInputLevel);
        if (legacyLevel !== null) level = Math.max(level, Math.min(1, Math.max(0, legacyLevel / 32767)));
        const energy = readStatNumber(values.totalAudioEnergy);
        const duration = readStatNumber(values.totalSamplesDuration);
        if (energy !== null && duration !== null) {
          totalEnergy += energy;
          totalDuration += duration;
        }
      }
      const previousEnergy = this.previousAudioEnergy;
      const previousDuration = this.previousAudioDuration;
      if (totalDuration > 0) {
        this.previousAudioEnergy = totalEnergy;
        this.previousAudioDuration = totalDuration;
        if (previousEnergy !== null && previousDuration !== null) {
          const energyDelta = totalEnergy - previousEnergy;
          const durationDelta = totalDuration - previousDuration;
          if (energyDelta >= 0 && durationDelta > 0) {
            level = Math.max(level, Math.min(1, Math.sqrt(energyDelta / durationDelta)));
          }
        }
      }
      const wasSpeaking = this.activity.speaking;
      const speaking = this.activity.update(level);
      if (speaking !== wasSpeaking && !this.disposed && this.desiredRoomId === roomId) {
        this.signaling.sendRtc('rtc.speaking', roomId, { speaking });
      }
    } catch {
      // Audio stats are optional in Chromium; keep the call usable when absent.
    } finally {
      this.statsSampleInProgress = false;
    }
  }

  private handleRemoteTrack(event: VoiceTrackEvent): void {
    if (event.track.kind !== 'audio') return;
    let stream: VoiceMediaStream;
    try {
      stream = event.streams?.[0] ?? this.mediaStreamFactory(event.track);
    } catch (error) {
      this.setSnapshot({ error: safeErrorMessage(error, '远端语音轨道无法播放') });
      return;
    }
    const key = event.track.id ?? stream.id ?? `remote-${this.audioSequence++}`;
    let remote = this.remoteAudio.get(key);
    if (remote === undefined) {
      const element = this.audioElementFactory();
      element.autoplay = true;
      element.muted = false;
      element.playsInline = true;
      element.setAttribute('aria-hidden', 'true');
      element.setAttribute('class', 'nexusroom-remote-audio');
      this.appendAudioElement(element);
      remote = { element, stream };
      this.remoteAudio.set(key, remote);
    } else {
      remote.stream = stream;
    }
    remote.element.muted = false;
    remote.element.autoplay = true;
    remote.element.srcObject = stream;
    void remote.element.play().then(() => {
      this.blockedAudio.delete(key);
    }).catch(() => {
      this.blockedAudio.add(key);
      this.setSnapshot({ error: '远端语音被浏览器拦截，请点击窗口后重试' });
    });
  }

  private cleanupPeer(sendLeave: boolean): Promise<void> {
    const roomId = this.activeRoomId;
    if (sendLeave && roomId !== null && this.signaling.connectionState === 'connected') {
      try {
        this.signaling.sendRtc('rtc.speaking', roomId, { speaking: false });
      } catch {
        // The socket may have closed between the state check and send.
      }
      try {
        this.signaling.sendRtc('rtc.leave', roomId);
      } catch {
        // The peer is still closed locally below.
      }
    }
    this.activeRoomId = null;
    this.rejectReadyWaiters(new VoiceClientError('语音房间已切换'));
    for (const waiter of this.localNegotiationWaiters.splice(0)) {
      waiter.reject(new VoiceClientError('语音房间已切换'));
    }
    this.localNegotiationPending = false;
    this.remoteOfferQueue = [];
    this.processingRemoteOffers = false;
    this.localDescriptionSignaled = false;
    this.remoteDescriptionSet = false;
    this.localOfferPending = false;
    this.pendingLocalCandidates.splice(0);
    this.pendingRemoteCandidates.splice(0);
    this.localTracksAdded.clear();
    this.stopSnapshotSampling();
    this.activity.reset();
    const peer = this.peer;
    const stream = this.localStream;
    this.peer = null;
    this.localStream = null;
    this.clearRemoteAudio();
    this.setSnapshot({
      roomId: this.desiredRoomId,
      microphone: 'muted',
      participants: [],
    });
    if (peer !== null) {
      peer.onicecandidate = null;
      peer.onconnectionstatechange = null;
      peer.oniceconnectionstatechange = null;
      peer.ontrack = null;
    }
    if (stream !== null) this.stopStream(stream);
    return this.closePeer(peer);
  }

  private async closePeer(peer: VoicePeerConnection | null): Promise<void> {
    if (peer === null) return;
    try {
      await peer.close();
    } catch {
      // Closing an already closed PeerConnection is harmless.
    }
  }

  private stopStream(stream: VoiceMediaStream): void {
    for (const track of stream.getTracks()) {
      try {
        track.stop();
      } catch {
        // A browser may already have stopped the device track.
      }
    }
  }

  private clearRemoteAudio(): void {
    for (const { element, stream } of this.remoteAudio.values()) {
      try {
        element.pause();
        element.srcObject = null;
        element.remove();
      } catch {
        // The element can already be detached during window teardown.
      }
      for (const track of stream.getTracks()) {
        try {
          track.stop();
        } catch {
          // PeerConnection.close() remains the authoritative remote cleanup.
        }
      }
    }
    this.remoteAudio.clear();
    this.blockedAudio.clear();
  }

  private isCurrent(generation: number, roomId: number | null): boolean {
    return !this.disposed && generation === this.generation && roomId === this.desiredRoomId;
  }

  private setSnapshot(patch: Partial<VoiceSnapshot>): void {
    this.snapshotValue = { ...this.snapshotValue, ...patch };
    for (const listener of [...this.listeners]) listener(this.snapshotValue);
  }
}

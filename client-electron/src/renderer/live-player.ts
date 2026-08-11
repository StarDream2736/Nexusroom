import {
  assertValidStreamKey,
  buildFlvStreamUrl,
  buildRtcStreamUrl,
} from './stream-url';
import { normalizeServerUrl } from '../main/server-url';

export { buildFlvStreamUrl, buildRtcStreamUrl } from './stream-url';
export { assertValidStreamKey, isValidStreamKey, STREAM_KEY_PATTERN } from './stream-url';

export type LivePlaybackProtocol = 'webrtc' | 'flv' | null;
export type LivePlayerMode =
  | 'idle'
  | 'connecting'
  | 'webrtc'
  | 'flv'
  | 'autoplay-blocked'
  | 'error'
  | 'closed';

export interface LivePlayerSnapshot {
  readonly mode: LivePlayerMode;
  readonly protocol: LivePlaybackProtocol;
  readonly muted: boolean;
  readonly sourceHasAudio: boolean | null;
  readonly flvRetryCount: number;
  readonly error: string | null;
}

export type LiveFetchImplementation = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export interface MpegtsPlayerLike {
  attachMediaElement(element: HTMLVideoElement): void;
  load(): void;
  play(): Promise<void> | void;
  pause?(): void;
  unload?(): void;
  detachMediaElement?(): void;
  destroy(): void;
  on(eventName: string, listener: (...args: unknown[]) => void): void;
  off?(eventName: string, listener: (...args: unknown[]) => void): void;
}

export interface MpegtsLike {
  readonly Events: { readonly ERROR: string };
  createPlayer(
    mediaDataSource: { readonly type: 'flv'; readonly isLive: true; readonly url: string },
    config?: Record<string, unknown>,
  ): MpegtsPlayerLike;
  getFeatureList(): { readonly mseLivePlayback?: boolean };
}

export interface LivePlayerOptions {
  readonly serverUrl: string;
  readonly streamKey: string;
  readonly video: HTMLVideoElement;
  readonly fetchImpl?: LiveFetchImplementation;
  readonly rtcPeerConnectionFactory?: () => RTCPeerConnection;
  readonly mediaStreamFactory?: () => MediaStream;
  readonly mpegts?: MpegtsLike;
  readonly iceGatheringTimeoutMs?: number;
  readonly disconnectedTimeoutMs?: number;
  readonly mediaWatchdogMs?: number;
}

let defaultMpegtsPromise: Promise<MpegtsLike> | null = null;

async function loadDefaultMpegts(): Promise<MpegtsLike> {
  if (defaultMpegtsPromise === null) {
    defaultMpegtsPromise = import('mpegts.js').then((module) => module.default as unknown as MpegtsLike);
  }
  return defaultMpegtsPromise;
}

const DEFAULT_ICE_GATHERING_TIMEOUT_MS = 8_000;
const DEFAULT_DISCONNECTED_TIMEOUT_MS = 3_000;
const DEFAULT_MEDIA_WATCHDOG_MS = 6_000;
export const FLV_RETRY_DELAYS_MS = [1_000, 2_000, 4_000, 8_000, 15_000] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function errorText(error: unknown, fallback: string): string {
  if (error instanceof Error && error.message.length > 0) return error.message;
  if (typeof error === 'string' && error.length > 0) return error;
  return fallback;
}

export function isAutoplayBlocked(error: unknown): boolean {
  if (!isRecord(error)) return false;
  const name = typeof error.name === 'string' ? error.name : '';
  const message = typeof error.message === 'string' ? error.message.toLowerCase() : '';
  return name === 'NotAllowedError' ||
    message.includes("user didn't interact") ||
    message.includes('notallowederror') ||
    message.includes('autoplay');
}

function stopTracks(stream: MediaStream | null): void {
  if (stream === null) return;
  for (const track of stream.getTracks()) {
    try {
      track.stop();
    } catch {
      // The browser may already have stopped a remote track.
    }
  }
}

function closePeer(peer: RTCPeerConnection | null): void {
  if (peer === null) return;
  try {
    peer.close();
  } catch {
    // Closing an already closed peer is harmless.
  }
}

async function waitForIceGathering(
  peer: RTCPeerConnection,
  timeoutMs: number,
  signal: AbortSignal,
): Promise<void> {
  if (peer.iceGatheringState === 'complete') return;
  await new Promise<void>((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => finish(), timeoutMs);
    const finish = (error?: Error): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      peer.removeEventListener('icegatheringstatechange', handleStateChange);
      signal.removeEventListener('abort', handleAbort);
      if (error === undefined) resolve();
      else reject(error);
    };
    const handleStateChange = (): void => {
      if (peer.iceGatheringState === 'complete') finish();
    };
    const handleAbort = (): void => finish(new Error('WebRTC playback session was cancelled'));
    peer.addEventListener('icegatheringstatechange', handleStateChange);
    signal.addEventListener('abort', handleAbort, { once: true });
    if (peer.iceGatheringState === 'complete') finish();
  });
}

interface InboundMediaStats {
  readonly videoBytes: number;
  readonly audioBytes: number;
}

function readInboundMediaStats(value: unknown): InboundMediaStats {
  let videoBytes = 0;
  let audioBytes = 0;
  if (!isRecord(value)) {
    return { videoBytes, audioBytes };
  }
  const reportCollection = value as {
    readonly forEach?: (callback: (rawReport: unknown) => void) => void;
  };
  if (typeof reportCollection.forEach !== 'function') {
    return { videoBytes, audioBytes };
  }
  reportCollection.forEach((rawReport: unknown) => {
    if (!isRecord(rawReport) || rawReport.type !== 'inbound-rtp' || rawReport.isRemote === true) {
      return;
    }
    const bytesReceived = typeof rawReport.bytesReceived === 'number'
      ? rawReport.bytesReceived
      : 0;
    const kind = rawReport.kind ?? rawReport.mediaType;
    if (kind === 'video') videoBytes += bytesReceived;
    if (kind === 'audio') audioBytes += bytesReceived;
  });
  return { videoBytes, audioBytes };
}

export class LivePlayer {
  private readonly serverUrl: string;
  private readonly streamKey: string;
  private readonly video: HTMLVideoElement;
  private readonly fetchImpl: LiveFetchImplementation;
  private readonly peerFactory: () => RTCPeerConnection;
  private readonly mediaStreamFactory: () => MediaStream;
  private readonly configuredMpegts: MpegtsLike | null;
  private mpegts: MpegtsLike | null = null;
  private readonly iceGatheringTimeoutMs: number;
  private readonly disconnectedTimeoutMs: number;
  private readonly mediaWatchdogMs: number;
  private readonly listeners = new Set<(snapshot: LivePlayerSnapshot) => void>();

  private snapshotValue: LivePlayerSnapshot = {
    mode: 'idle',
    protocol: null,
    muted: false,
    sourceHasAudio: null,
    flvRetryCount: 0,
    error: null,
  };
  private peer: RTCPeerConnection | null = null;
  private remoteStream: MediaStream | null = null;
  private flvPlayer: MpegtsPlayerLike | null = null;
  private flvErrorListener: ((...args: unknown[]) => void) | null = null;
  private abortController: AbortController | null = null;
  private disconnectedTimer: ReturnType<typeof setTimeout> | null = null;
  private mediaWatchdogTimer: ReturnType<typeof setTimeout> | null = null;
  private flvRetryTimer: ReturnType<typeof setTimeout> | null = null;
  private generation = 0;
  private flvRetryCount = 0;
  private started = false;
  private disposed = false;
  private fallbackInProgress = false;
  private videoFrameSeen = false;
  private videoListenersInstalled = false;
  private startPromise: Promise<void> | null = null;

  constructor(options: LivePlayerOptions) {
    this.serverUrl = normalizeServerUrl(options.serverUrl);
    this.streamKey = assertValidStreamKey(options.streamKey);
    this.video = options.video;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
    this.peerFactory = options.rtcPeerConnectionFactory ?? (() => new RTCPeerConnection());
    this.mediaStreamFactory = options.mediaStreamFactory ?? (() => new MediaStream());
    this.configuredMpegts = options.mpegts ?? null;
    this.iceGatheringTimeoutMs = options.iceGatheringTimeoutMs ?? DEFAULT_ICE_GATHERING_TIMEOUT_MS;
    this.disconnectedTimeoutMs = options.disconnectedTimeoutMs ?? DEFAULT_DISCONNECTED_TIMEOUT_MS;
    this.mediaWatchdogMs = options.mediaWatchdogMs ?? DEFAULT_MEDIA_WATCHDOG_MS;
    if (
      !Number.isFinite(this.iceGatheringTimeoutMs) || this.iceGatheringTimeoutMs <= 0 ||
      !Number.isFinite(this.disconnectedTimeoutMs) || this.disconnectedTimeoutMs <= 0 ||
      !Number.isFinite(this.mediaWatchdogMs) || this.mediaWatchdogMs <= 0
    ) {
      throw new Error('直播播放器超时参数必须是正数');
    }
    this.video.autoplay = true;
    this.video.playsInline = true;
    this.video.muted = false;
  }

  get snapshot(): LivePlayerSnapshot {
    return this.snapshotValue;
  }

  get peerConnection(): RTCPeerConnection | null {
    return this.peer;
  }

  get protocol(): LivePlaybackProtocol {
    return this.snapshotValue.protocol;
  }

  onChange(listener: (snapshot: LivePlayerSnapshot) => void): () => void {
    this.listeners.add(listener);
    listener(this.snapshotValue);
    return () => this.listeners.delete(listener);
  }

  setMuted(muted: boolean): void {
    this.video.muted = muted;
    this.setSnapshot({ muted });
  }

  toggleMuted(): boolean {
    this.setMuted(!this.video.muted);
    return this.video.muted;
  }

  start(): Promise<void> {
    if (this.disposed) return Promise.reject(new Error('直播播放器已关闭'));
    if (this.started) return this.startPromise ?? Promise.resolve();
    this.started = true;
    this.startPromise = this.beginSession(true);
    return this.startPromise;
  }

  refresh(): Promise<void> {
    if (this.disposed) return Promise.reject(new Error('直播播放器已关闭'));
    this.started = true;
    this.startPromise = this.beginSession(true);
    return this.startPromise;
  }

  async resume(): Promise<void> {
    if (this.disposed || this.snapshotValue.mode !== 'autoplay-blocked') return;
    try {
      await this.video.play();
      const protocol = this.snapshotValue.protocol;
      this.setSnapshot({
        mode: protocol === 'flv' ? 'flv' : 'webrtc',
        error: null,
      });
      if (protocol === 'webrtc') this.armMediaWatchdog(this.generation);
    } catch (error) {
      if (isAutoplayBlocked(error)) {
        this.setSnapshot({ error: '浏览器限制自动播放，请点击恢复播放' });
        return;
      }
      if (this.snapshotValue.protocol === 'webrtc') {
        await this.fallbackToFlv(this.generation, 'WebRTC 播放失败，已回退 FLV');
      } else {
        this.setSnapshot({ mode: 'error', error: errorText(error, 'FLV 播放失败') });
        this.scheduleFlvRetry(this.generation);
      }
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.generation += 1;
    this.abortController?.abort();
    this.abortController = null;
    this.clearTimers();
    this.removeVideoListeners();
    this.destroyPeer();
    this.destroyFlvPlayer();
    this.clearVideo();
    this.setSnapshot({ mode: 'closed', protocol: null, error: null });
    this.listeners.clear();
  }

  close(): void {
    this.dispose();
  }

  private async beginSession(resetRetryCount: boolean): Promise<void> {
    const generation = ++this.generation;
    this.abortController?.abort();
    this.abortController = new AbortController();
    this.clearTimers();
    this.removeVideoListeners();
    this.destroyPeer();
    this.destroyFlvPlayer();
    this.clearVideo();
    this.fallbackInProgress = false;
    this.videoFrameSeen = false;
    if (resetRetryCount) this.flvRetryCount = 0;
    this.setSnapshot({
      mode: 'connecting',
      protocol: null,
      sourceHasAudio: null,
      flvRetryCount: this.flvRetryCount,
      error: null,
      muted: this.video.muted,
    });

    try {
      await this.startWebRtc(generation, this.abortController.signal);
    } catch (error) {
      if (!this.isCurrent(generation)) return;
      if (isAutoplayBlocked(error)) {
        this.setSnapshot({
          mode: 'autoplay-blocked',
          protocol: 'webrtc',
          error: '浏览器限制自动播放，请点击恢复播放',
        });
        return;
      }
      await this.fallbackToFlv(
        generation,
        `WebRTC 不可用：${errorText(error, '协商失败')}，已回退 FLV`,
      );
    }
  }

  private async startWebRtc(generation: number, signal: AbortSignal): Promise<void> {
    const peer = this.peerFactory();
    const stream = this.mediaStreamFactory();
    this.peer = peer;
    this.remoteStream = stream;
    this.video.srcObject = stream;
    this.installVideoListeners();
    peer.ontrack = (event) => {
      if (!this.isCurrent(generation) || this.peer !== peer) return;
      if (!stream.getTracks().some((track) => track.id === event.track.id)) {
        stream.addTrack(event.track);
      }
    };
    peer.onconnectionstatechange = () => {
      if (!this.isCurrent(generation) || this.peer !== peer) return;
      const state = peer.connectionState;
      if (state === 'failed' || peer.iceConnectionState === 'failed') {
        void this.fallbackToFlv(generation, 'WebRTC 媒体连接失败，已回退 FLV');
        return;
      }
      if (state === 'disconnected' || peer.iceConnectionState === 'disconnected') {
        this.armDisconnectedFallback(generation, peer);
      } else if (state === 'connected' || peer.iceConnectionState === 'connected') {
        this.clearDisconnectedTimer();
      }
    };
    peer.oniceconnectionstatechange = () => {
      if (!this.isCurrent(generation) || this.peer !== peer) return;
      if (peer.iceConnectionState === 'failed') {
        void this.fallbackToFlv(generation, 'WebRTC ICE 连接失败，已回退 FLV');
      } else if (peer.iceConnectionState === 'disconnected') {
        this.armDisconnectedFallback(generation, peer);
      } else if (peer.iceConnectionState === 'connected' || peer.connectionState === 'connected') {
        this.clearDisconnectedTimer();
      }
    };

    peer.addTransceiver('video', { direction: 'recvonly' });
    peer.addTransceiver('audio', { direction: 'recvonly' });
    const offer = await peer.createOffer();
    if (!this.isCurrent(generation)) throw new Error('WebRTC playback session was cancelled');
    await peer.setLocalDescription(offer);
    await waitForIceGathering(peer, this.iceGatheringTimeoutMs, signal);
    if (!this.isCurrent(generation)) throw new Error('WebRTC playback session was cancelled');
    const localSdp = peer.localDescription?.sdp;
    if (typeof localSdp !== 'string' || localSdp.length === 0) {
      throw new Error('WebRTC offer SDP is missing');
    }
    const response = await this.fetchImpl(
      new URL('/api/v1/web/rtc/play', this.serverUrl).toString(),
      {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({
          streamurl: buildRtcStreamUrl(this.serverUrl, this.streamKey),
          sdp: localSdp,
        }),
        signal,
      },
    );
    const raw = await response.json() as unknown;
    if (!response.ok || !isRecord(raw) || typeof raw.sdp !== 'string' || raw.sdp.length === 0 || (typeof raw.code === 'number' && raw.code !== 0)) {
      const message = isRecord(raw) && typeof raw.message === 'string'
        ? raw.message
        : `WebRTC 协商失败（HTTP ${response.status}）`;
      throw new Error(message);
    }
    if (!this.isCurrent(generation)) throw new Error('WebRTC playback session was cancelled');
    if (raw.source_has_audio !== undefined && typeof raw.source_has_audio !== 'boolean') {
      throw new Error('WebRTC 音频状态无效');
    }
    await peer.setRemoteDescription({ type: 'answer', sdp: raw.sdp });
    if (!this.isCurrent(generation)) throw new Error('WebRTC playback session was cancelled');
    const sourceHasAudio = raw.source_has_audio === true;
    this.setSnapshot({
      mode: 'webrtc',
      protocol: 'webrtc',
      sourceHasAudio,
      error: null,
    });
    try {
      await this.video.play();
    } catch (error) {
      if (isAutoplayBlocked(error)) {
        this.setSnapshot({
          mode: 'autoplay-blocked',
          protocol: 'webrtc',
          error: '浏览器限制自动播放，请点击恢复播放',
        });
        return;
      }
      throw error;
    }
    this.armMediaWatchdog(generation);
  }

  private async fallbackToFlv(generation: number, reason: string): Promise<void> {
    if (!this.isCurrent(generation) || this.snapshotValue.protocol === 'flv' || this.fallbackInProgress) return;
    this.fallbackInProgress = true;
    this.clearRtcTimers();
    this.removeVideoListeners();
    this.destroyPeer();
    this.clearVideo();
    this.setSnapshot({ mode: 'flv', protocol: 'flv', error: reason });
    try {
      await this.createFlvPlayer(generation);
      if (this.isCurrent(generation)) {
        this.setSnapshot({ mode: 'flv', protocol: 'flv', error: reason });
      }
    } catch (error) {
      if (!this.isCurrent(generation)) return;
      if (isAutoplayBlocked(error)) {
        this.setSnapshot({
          mode: 'autoplay-blocked',
          protocol: 'flv',
          error: '浏览器限制自动播放，请点击恢复播放',
        });
      } else {
        this.setSnapshot({
          mode: 'error',
          protocol: 'flv',
          error: errorText(error, 'FLV 播放失败'),
        });
        this.scheduleFlvRetry(generation);
      }
    } finally {
      this.fallbackInProgress = false;
    }
  }

  private async createFlvPlayer(generation: number): Promise<void> {
    if (!this.isCurrent(generation)) throw new Error('FLV playback session was cancelled');
    const mpegts = this.configuredMpegts ?? await loadDefaultMpegts();
    if (!this.isCurrent(generation)) throw new Error('FLV playback session was cancelled');
    this.mpegts = mpegts;
    const featureList = mpegts.getFeatureList();
    if (featureList.mseLivePlayback !== true) {
      throw new Error('当前环境不支持 HTTP-FLV 播放');
    }
    this.destroyFlvPlayer();
    const player = mpegts.createPlayer(
      {
        type: 'flv',
        isLive: true,
        url: buildFlvStreamUrl(this.serverUrl, this.streamKey),
      },
      {
        enableWorker: false,
        lazyLoad: false,
        stashInitialSize: 128,
        autoCleanupSourceBuffer: true,
      },
    );
    const onError = (...args: unknown[]): void => {
      if (!this.isCurrent(generation) || this.flvPlayer !== player || this.snapshotValue.protocol !== 'flv') return;
      const detail = args.filter((value) => value !== undefined).map(String).join(' / ');
      this.setSnapshot({ mode: 'error', protocol: 'flv', error: detail || 'FLV 播放中断，正在重连' });
      this.scheduleFlvRetry(generation);
    };
    this.flvPlayer = player;
    this.flvErrorListener = onError;
    player.on(mpegts.Events.ERROR, onError);
    player.attachMediaElement(this.video);
    player.load();
    const playerPlay = player.play();
    if (playerPlay !== undefined) await playerPlay;
    if (!this.isCurrent(generation) || this.flvPlayer !== player) {
      this.destroyFlvPlayer();
      throw new Error('FLV playback session was cancelled');
    }
    try {
      await this.video.play();
    } catch (error) {
      if (isAutoplayBlocked(error)) {
        this.setSnapshot({ mode: 'autoplay-blocked', protocol: 'flv', error: '浏览器限制自动播放，请点击恢复播放' });
      }
      throw error;
    }
  }

  private armDisconnectedFallback(generation: number, peer: RTCPeerConnection): void {
    if (this.disconnectedTimer !== null) return;
    this.disconnectedTimer = setTimeout(() => {
      this.disconnectedTimer = null;
      if (!this.isCurrent(generation) || this.peer !== peer) return;
      if (peer.connectionState === 'disconnected' || peer.iceConnectionState === 'disconnected') {
        void this.fallbackToFlv(generation, 'WebRTC 连接持续中断，已回退 FLV');
      }
    }, this.disconnectedTimeoutMs);
  }

  private armMediaWatchdog(generation: number): void {
    this.clearMediaWatchdog();
    this.mediaWatchdogTimer = setTimeout(() => {
      this.mediaWatchdogTimer = null;
      void this.checkRtcMedia(generation);
    }, this.mediaWatchdogMs);
  }

  private async checkRtcMedia(generation: number): Promise<void> {
    if (!this.isCurrent(generation) || this.snapshotValue.protocol !== 'webrtc' || this.peer === null) return;
    let stats: InboundMediaStats = { videoBytes: 0, audioBytes: 0 };
    try {
      stats = readInboundMediaStats(await this.peer.getStats());
    } catch {
      // A closed peer is handled by the generation and connection guards.
    }
    const hasVideoFrame = this.videoFrameSeen || this.video.videoWidth > 0 || this.video.readyState >= 2;
    if (!hasVideoFrame || stats.videoBytes <= 0) {
      await this.fallbackToFlv(generation, 'WebRTC 无视频首帧，已回退 FLV');
      return;
    }
    if (this.snapshotValue.sourceHasAudio === true && stats.audioBytes <= 0) {
      await this.fallbackToFlv(generation, 'WebRTC 音频不可用，已回退 FLV');
    }
  }

  private scheduleFlvRetry(generation: number): void {
    if (!this.isCurrent(generation) || this.snapshotValue.protocol !== 'flv' || this.flvRetryTimer !== null) return;
    const delay = FLV_RETRY_DELAYS_MS[this.flvRetryCount];
    if (delay === undefined) {
      this.setSnapshot({ mode: 'error', protocol: 'flv', error: 'FLV 多次重连失败，请手动刷新播放' });
      return;
    }
    this.flvRetryCount += 1;
    this.setSnapshot({ flvRetryCount: this.flvRetryCount });
    this.flvRetryTimer = setTimeout(() => {
      this.flvRetryTimer = null;
      if (!this.isCurrent(generation) || this.snapshotValue.protocol !== 'flv') return;
      void this.createFlvPlayer(generation).then(() => {
        if (this.isCurrent(generation)) this.setSnapshot({ mode: 'flv', protocol: 'flv', error: null });
      }).catch((error: unknown) => {
        if (!this.isCurrent(generation)) return;
        if (isAutoplayBlocked(error)) {
          this.setSnapshot({ mode: 'autoplay-blocked', protocol: 'flv', error: '浏览器限制自动播放，请点击恢复播放' });
          return;
        }
        this.setSnapshot({ mode: 'error', protocol: 'flv', error: errorText(error, 'FLV 播放失败') });
        this.scheduleFlvRetry(generation);
      });
    }, delay);
  }

  private installVideoListeners(): void {
    this.removeVideoListeners();
    this.video.addEventListener('loadeddata', this.markVideoFrame);
    this.video.addEventListener('playing', this.markVideoFrame);
    this.video.addEventListener('timeupdate', this.markVideoFrame);
    this.videoListenersInstalled = true;
  }

  private removeVideoListeners(): void {
    if (!this.videoListenersInstalled) return;
    this.video.removeEventListener('loadeddata', this.markVideoFrame);
    this.video.removeEventListener('playing', this.markVideoFrame);
    this.video.removeEventListener('timeupdate', this.markVideoFrame);
    this.videoListenersInstalled = false;
  }

  private clearVideo(): void {
    try {
      this.video.pause?.();
    } catch {
      // The video element may already be detached during window teardown.
    }
    this.video.srcObject = null;
  }

  private readonly markVideoFrame = (): void => {
    this.videoFrameSeen = true;
  };

  private destroyPeer(): void {
    const peer = this.peer;
    this.peer = null;
    if (peer !== null) {
      peer.ontrack = null;
      peer.onconnectionstatechange = null;
      peer.oniceconnectionstatechange = null;
    }
    stopTracks(this.remoteStream);
    this.remoteStream = null;
    closePeer(peer);
  }

  private destroyFlvPlayer(): void {
    const player = this.flvPlayer;
    const listener = this.flvErrorListener;
    this.flvPlayer = null;
    this.flvErrorListener = null;
    if (player === null) return;
    if (listener !== null) player.off?.(this.mpegts?.Events.ERROR ?? 'error', listener);
    try { player.pause?.(); } catch { /* player may already be closed */ }
    try { player.unload?.(); } catch { /* player may already be closed */ }
    try { player.detachMediaElement?.(); } catch { /* player may already be detached */ }
    try { player.destroy(); } catch { /* player may already be destroyed */ }
  }

  private clearRtcTimers(): void {
    this.clearDisconnectedTimer();
    this.clearMediaWatchdog();
  }

  private clearTimers(): void {
    this.clearRtcTimers();
    if (this.flvRetryTimer !== null) {
      clearTimeout(this.flvRetryTimer);
      this.flvRetryTimer = null;
    }
  }

  private clearDisconnectedTimer(): void {
    if (this.disconnectedTimer !== null) {
      clearTimeout(this.disconnectedTimer);
      this.disconnectedTimer = null;
    }
  }

  private clearMediaWatchdog(): void {
    if (this.mediaWatchdogTimer !== null) {
      clearTimeout(this.mediaWatchdogTimer);
      this.mediaWatchdogTimer = null;
    }
  }

  private isCurrent(generation: number): boolean {
    return !this.disposed && generation === this.generation;
  }

  private setSnapshot(patch: Partial<LivePlayerSnapshot>): void {
    this.snapshotValue = { ...this.snapshotValue, ...patch };
    for (const listener of [...this.listeners]) listener(this.snapshotValue);
  }
}

import { describe, expect, it, vi } from 'vitest';
import {
  buildFlvStreamUrl,
  buildRtcStreamUrl,
  LivePlayer,
  type LiveFetchImplementation,
  type MpegtsLike,
  type MpegtsPlayerLike,
} from '../src/renderer/live-player';

class FakeVideo {
  autoplay = false;
  playsInline = false;
  muted = false;
  srcObject: MediaProvider | null = null;
  videoWidth = 0;
  readyState = 0;
  allowAutoplay = true;
  readonly play = vi.fn(async () => {
    if (!this.allowAutoplay) {
      const error = new Error('play() failed because the user did not interact');
      Object.assign(error, { name: 'NotAllowedError' });
      throw error;
    }
  });
  private readonly listeners = new Map<string, Set<() => void>>();

  addEventListener(name: string, listener: EventListenerOrEventListenerObject): void {
    const callbacks = this.listeners.get(name) ?? new Set<() => void>();
    callbacks.add(listener as () => void);
    this.listeners.set(name, callbacks);
  }

  removeEventListener(name: string, listener: EventListenerOrEventListenerObject): void {
    this.listeners.get(name)?.delete(listener as () => void);
  }

  emit(name: string): void {
    for (const listener of this.listeners.get(name) ?? []) listener();
  }

  listenerCount(name: string): number {
    return this.listeners.get(name)?.size ?? 0;
  }
}

class FakeMediaStream {
  readonly tracks: MediaStreamTrack[] = [];

  addTrack(track: MediaStreamTrack): void {
    this.tracks.push(track);
  }

  getTracks(): MediaStreamTrack[] {
    return [...this.tracks];
  }
}

class FakePeer {
  connectionState: RTCPeerConnectionState = 'new';
  iceConnectionState: RTCIceConnectionState = 'new';
  iceGatheringState: RTCIceGatheringState = 'complete';
  localDescription: RTCSessionDescription | null = null;
  ontrack: ((event: RTCTrackEvent) => void) | null = null;
  onconnectionstatechange: (() => void) | null = null;
  oniceconnectionstatechange: (() => void) | null = null;
  readonly addTransceiver = vi.fn();
  readonly createOffer = vi.fn(async () => ({ type: 'offer', sdp: 'offer-sdp' }));
  readonly setLocalDescription = vi.fn(async (description: RTCSessionDescriptionInit) => {
    this.localDescription = description as RTCSessionDescription;
  });
  readonly setRemoteDescription = vi.fn(async () => undefined);
  readonly close = vi.fn(() => {
    this.connectionState = 'closed';
  });
  readonly getStats = vi.fn(async () => new Map<string, Record<string, unknown>>() as unknown as RTCStatsReport);

  addEventListener(): void {}

  removeEventListener(): void {}

  fail(): void {
    this.connectionState = 'failed';
    this.onconnectionstatechange?.();
  }

  setStats(...reports: Record<string, unknown>[]): void {
    const stats = new Map<string, Record<string, unknown>>();
    reports.forEach((report, index) => stats.set(String(index), report));
    this.getStats.mockResolvedValue(stats as unknown as RTCStatsReport);
  }
}

class FakeFlvPlayer implements MpegtsPlayerLike {
  readonly play = vi.fn(async () => undefined);
  readonly load = vi.fn();
  readonly attachMediaElement = vi.fn();
  readonly pause = vi.fn();
  readonly unload = vi.fn();
  readonly detachMediaElement = vi.fn();
  readonly destroy = vi.fn();
  private readonly listeners = new Map<string, (...args: unknown[]) => void>();

  on(eventName: string, listener: (...args: unknown[]) => void): void {
    this.listeners.set(eventName, listener);
  }

  off(eventName: string, listener: (...args: unknown[]) => void): void {
    if (this.listeners.get(eventName) === listener) this.listeners.delete(eventName);
  }

  emitError(...args: unknown[]): void {
    this.listeners.get('error')?.(...args);
  }
}

function createMpegts(): { readonly module: MpegtsLike; readonly players: FakeFlvPlayer[] } {
  const players: FakeFlvPlayer[] = [];
  const module: MpegtsLike = {
    Events: { ERROR: 'error' },
    getFeatureList: vi.fn(() => ({ mseLivePlayback: true })),
    createPlayer: vi.fn(() => {
      const player = new FakeFlvPlayer();
      players.push(player);
      return player;
    }),
  };
  return { module, players };
}

function createRtcResponse(sourceHasAudio = false): Response {
  return new Response(JSON.stringify({ code: 0, sdp: 'answer-sdp', source_has_audio: sourceHasAudio }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

function createPlayer(options: {
  readonly video?: FakeVideo;
  readonly peer?: FakePeer;
  readonly fetchImpl?: LiveFetchImplementation;
  readonly mpegts?: MpegtsLike;
  readonly sourceHasAudio?: boolean;
} = {}): {
  readonly player: LivePlayer;
  readonly video: FakeVideo;
  readonly peer: FakePeer;
  readonly mpegts: MpegtsLike;
  readonly flvPlayers: FakeFlvPlayer[];
} {
  const video = options.video ?? new FakeVideo();
  const peer = options.peer ?? new FakePeer();
  const flv = options.mpegts === undefined ? createMpegts() : { module: options.mpegts, players: [] as FakeFlvPlayer[] };
  const player = new LivePlayer({
    serverUrl: 'https://stream.example:8443',
    streamKey: 'stream-key-1',
    video: video as unknown as HTMLVideoElement,
    rtcPeerConnectionFactory: () => peer as unknown as RTCPeerConnection,
    mediaStreamFactory: () => new FakeMediaStream() as unknown as MediaStream,
    mpegts: flv.module,
    fetchImpl: options.fetchImpl ?? (async () => createRtcResponse(options.sourceHasAudio ?? false)),
  });
  return { player, video, peer, mpegts: flv.module, flvPlayers: flv.players };
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

describe('LivePlayer', () => {
  it('builds the server-compatible RTC URL and posts the offer payload', async () => {
    const requests: Array<{ readonly input: RequestInfo | URL; readonly init?: RequestInit }> = [];
    const { player, video, peer } = createPlayer({
      fetchImpl: async (input, init) => {
        requests.push({ input, init });
        return createRtcResponse();
      },
    });

    expect(buildRtcStreamUrl('https://stream.example:8443', 'stream-key-1')).toBe(
      'webrtc://stream.example:8443/live/stream-key-1?play=/api/v1/web/rtc/play/&schema=https',
    );
    expect(buildFlvStreamUrl('https://stream.example:8443', 'stream-key-1')).toBe(
      'https://stream.example:8443/api/v1/stream/stream-key-1',
    );
    await player.start();
    expect(requests).toHaveLength(1);
    expect(String(requests[0]?.input)).toBe('https://stream.example:8443/api/v1/web/rtc/play');
    expect(JSON.parse(String(requests[0]?.init?.body))).toEqual({
      streamurl: 'webrtc://stream.example:8443/live/stream-key-1?play=/api/v1/web/rtc/play/&schema=https',
      sdp: 'offer-sdp',
    });
    expect(peer.addTransceiver).toHaveBeenCalledWith('video', { direction: 'recvonly' });
    expect(peer.addTransceiver).toHaveBeenCalledWith('audio', { direction: 'recvonly' });
    expect(video.muted).toBe(false);
    player.dispose();
  });

  it('keeps a successful WebRTC session when media arrives', async () => {
    vi.useFakeTimers();
    const peer = new FakePeer();
    peer.setStats({ type: 'inbound-rtp', kind: 'video', bytesReceived: 200 }, { type: 'inbound-rtp', kind: 'audio', bytesReceived: 100 });
    const { player, video } = createPlayer({ peer });
    video.videoWidth = 1280;
    video.readyState = 4;
    await player.start();
    video.emit('playing');
    vi.advanceTimersByTime(6_000);
    await flush();
    expect(player.snapshot).toMatchObject({ mode: 'webrtc', protocol: 'webrtc', error: null });
    player.dispose();
    vi.useRealTimers();
  });

  it('does not fall back when Chromium blocks audible autoplay', async () => {
    const video = new FakeVideo();
    video.allowAutoplay = false;
    const { player, video: playerVideo, peer, mpegts } = createPlayer({ video });
    await player.start();

    expect(player.snapshot).toMatchObject({ mode: 'autoplay-blocked', protocol: 'webrtc' });
    expect(peer.close).not.toHaveBeenCalled();
    expect(mpegts.createPlayer).not.toHaveBeenCalled();
    video.allowAutoplay = true;
    await player.resume();
    expect(playerVideo.play).toHaveBeenCalledTimes(2);
    expect(player.snapshot).toMatchObject({ mode: 'webrtc', protocol: 'webrtc' });
    player.dispose();
  });

  it('waits for sustained disconnection and checks declared audio RTP', async () => {
    vi.useFakeTimers();
    const disconnected = createPlayer();
    await disconnected.player.start();
    disconnected.peer.connectionState = 'disconnected';
    disconnected.peer.onconnectionstatechange?.();
    vi.advanceTimersByTime(2_999);
    expect(disconnected.mpegts.createPlayer).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    await flush();
    expect(disconnected.mpegts.createPlayer).toHaveBeenCalledTimes(1);
    disconnected.player.dispose();

    const peer = new FakePeer();
    peer.setStats({ type: 'inbound-rtp', kind: 'video', bytesReceived: 200 });
    const withMissingAudio = createPlayer({ peer, sourceHasAudio: true });
    withMissingAudio.video.videoWidth = 1280;
    withMissingAudio.video.readyState = 4;
    await withMissingAudio.player.start();
    vi.advanceTimersByTime(6_000);
    await flush();
    expect(withMissingAudio.mpegts.createPlayer).toHaveBeenCalledTimes(1);
    withMissingAudio.player.dispose();
    vi.useRealTimers();
  });

  it('falls back once for negotiation failure, connection failure, and media watchdog failure', async () => {
    const flv = createMpegts();
    const failedNegotiation = createPlayer({
      mpegts: flv.module,
      fetchImpl: async () => new Response(JSON.stringify({ code: 40_001, message: 'not live' }), { status: 404 }),
    });
    await failedNegotiation.player.start();
    expect(flv.module.createPlayer).toHaveBeenCalledTimes(1);
    expect(failedNegotiation.peer.close).toHaveBeenCalledTimes(1);
    expect(failedNegotiation.player.snapshot.protocol).toBe('flv');
    failedNegotiation.player.dispose();

    const connectionFailure = createPlayer();
    await connectionFailure.player.start();
    connectionFailure.peer.fail();
    await flush();
    expect(connectionFailure.mpegts.createPlayer).toHaveBeenCalledTimes(1);
    connectionFailure.peer.fail();
    await flush();
    expect(connectionFailure.mpegts.createPlayer).toHaveBeenCalledTimes(1);
    connectionFailure.player.dispose();

    vi.useFakeTimers();
    const mediaFailure = createPlayer();
    await mediaFailure.player.start();
    vi.advanceTimersByTime(6_000);
    await flush();
    expect(mediaFailure.mpegts.createPlayer).toHaveBeenCalledTimes(1);
    mediaFailure.player.dispose();
    vi.useRealTimers();
  });

  it('locks FLV retries to the current session and caps them at five', async () => {
    vi.useFakeTimers();
    const { player, flvPlayers, mpegts } = createPlayer({
      fetchImpl: async () => new Response(JSON.stringify({ code: 40_001, message: 'not live' }), { status: 404 }),
    });
    await player.start();
    expect(player.snapshot.protocol).toBe('flv');
    const delays = [1_000, 2_000, 4_000, 8_000, 15_000];
    for (const delay of delays) {
      flvPlayers.at(-1)?.emitError('network');
      vi.advanceTimersByTime(delay);
      await flush();
    }
    flvPlayers.at(-1)?.emitError('network');
    await flush();
    expect(mpegts.createPlayer).toHaveBeenCalledTimes(6);
    expect(player.snapshot).toMatchObject({ mode: 'error', protocol: 'flv', flvRetryCount: 5 });
    player.dispose();
    vi.useRealTimers();
  });

  it('refreshes into a new WebRTC session and clears stale async results', async () => {
    const peerFactory = vi.fn(() => new FakePeer());
    const flv = createMpegts();
    let resolveFetch: ((response: Response) => void) | undefined;
    const pending = new Promise<Response>((resolve) => { resolveFetch = resolve; });
    const video = new FakeVideo();
    const player = new LivePlayer({
      serverUrl: 'https://stream.example:8443',
      streamKey: 'stream-key-1',
      video: video as unknown as HTMLVideoElement,
      rtcPeerConnectionFactory: () => peerFactory() as unknown as RTCPeerConnection,
      mediaStreamFactory: () => new FakeMediaStream() as unknown as MediaStream,
      mpegts: flv.module,
      fetchImpl: async () => pending,
    });
    const startPromise = player.start();
    player.dispose();
    resolveFetch?.(createRtcResponse());
    await startPromise;
    expect(peerFactory).toHaveBeenCalledTimes(1);
    expect(flv.module.createPlayer).not.toHaveBeenCalled();
    expect(video.srcObject).toBeNull();

    let refreshFetchCount = 0;
    const refreshed = createPlayer({
      fetchImpl: async () => {
        refreshFetchCount += 1;
        return refreshFetchCount === 1
          ? new Response(JSON.stringify({ code: 40_001, message: 'not live' }), { status: 404 })
          : createRtcResponse();
      },
    });
    await refreshed.player.start();
    expect(refreshed.player.snapshot.protocol).toBe('flv');
    await refreshed.player.refresh();
    expect(refreshed.player.snapshot.protocol).toBe('webrtc');
    expect(refreshed.flvPlayers[0]?.destroy).toHaveBeenCalled();
    refreshed.player.dispose();
  });

  it('removes video listeners and media resources on dispose', async () => {
    const { player, video, peer } = createPlayer();
    await player.start();
    expect(video.listenerCount('playing')).toBe(1);
    player.dispose();
    expect(video.listenerCount('playing')).toBe(0);
    expect(video.srcObject).toBeNull();
    expect(peer.close).toHaveBeenCalledTimes(1);
  });
});

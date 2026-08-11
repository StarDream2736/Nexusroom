import { normalizeServerUrl } from './server-url';

export type WsConnectionState = 'disconnected' | 'connecting' | 'connected';

export interface WsMessage {
  readonly event: string;
  readonly room_id?: number;
  readonly payload?: unknown;
  readonly timestamp?: string;
  readonly [key: string]: unknown;
}

export interface WebSocketLike {
  onopen: ((event: Event) => void) | null;
  onmessage: ((event: MessageEvent) => void) | null;
  onerror: ((event: Event) => void) | null;
  onclose: ((event: CloseEvent) => void) | null;
  send(data: string): void;
  close(code?: number, reason?: string): void;
}

export type WebSocketFactory = (url: string) => WebSocketLike;
export type WsMessageListener = (message: WsMessage) => void;
export type WsStateListener = (state: WsConnectionState) => void;

export interface WsClientOptions {
  readonly webSocketFactory?: WebSocketFactory;
  readonly maxReconnectAttempts?: number;
  readonly reconnectBaseDelayMs?: number;
  readonly reconnectMaxDelayMs?: number;
  readonly connectTimeoutMs?: number;
  readonly heartbeatIntervalMs?: number;
}

export class WsError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WsError';
  }
}

function createNativeWebSocket(url: string): WebSocketLike {
  if (typeof globalThis.WebSocket !== 'function') {
    throw new WsError('当前 Electron 运行时不支持 WebSocket');
  }
  return new globalThis.WebSocket(url);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export function buildWebSocketUrl(serverUrl: string, token: string): string {
  if (token.length === 0) {
    throw new WsError('WebSocket 连接需要认证令牌');
  }
  const url = new URL(normalizeServerUrl(serverUrl));
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.pathname = '/ws';
  url.search = '';
  url.searchParams.set('token', token);
  return url.toString();
}

export class WsClient {
  private readonly webSocketFactory: WebSocketFactory;
  private readonly maxReconnectAttempts: number;
  private readonly reconnectBaseDelayMs: number;
  private readonly reconnectMaxDelayMs: number;
  private readonly connectTimeoutMs: number;
  private readonly heartbeatIntervalMs: number;
  private readonly listeners = new Map<string, Set<WsMessageListener>>();
  private readonly stateListeners = new Set<WsStateListener>();
  private socket: WebSocketLike | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private connectTimeoutTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private serverUrl: string | null = null;
  private token: string | null = null;
  private shouldReconnect = false;
  private reconnectAttempts = 0;
  private connectionGeneration = 0;
  private _state: WsConnectionState = 'disconnected';

  constructor(options: WsClientOptions = {}) {
    this.webSocketFactory = options.webSocketFactory ?? createNativeWebSocket;
    this.maxReconnectAttempts = options.maxReconnectAttempts ?? 5;
    this.reconnectBaseDelayMs = options.reconnectBaseDelayMs ?? 250;
    this.reconnectMaxDelayMs = options.reconnectMaxDelayMs ?? 5_000;
    this.connectTimeoutMs = options.connectTimeoutMs ?? 10_000;
    this.heartbeatIntervalMs = options.heartbeatIntervalMs ?? 30_000;
    if (
      !Number.isInteger(this.maxReconnectAttempts) ||
      this.maxReconnectAttempts < 0 ||
      !Number.isFinite(this.reconnectBaseDelayMs) ||
      this.reconnectBaseDelayMs <= 0 ||
      !Number.isFinite(this.reconnectMaxDelayMs) ||
      this.reconnectMaxDelayMs < this.reconnectBaseDelayMs ||
      !Number.isFinite(this.connectTimeoutMs) ||
      this.connectTimeoutMs <= 0 ||
      !Number.isFinite(this.heartbeatIntervalMs) ||
      this.heartbeatIntervalMs <= 0
    ) {
      throw new WsError('WebSocket 重连参数无效');
    }
  }

  get state(): WsConnectionState {
    return this._state;
  }

  on(eventName: string, listener: WsMessageListener): () => void {
    let listeners = this.listeners.get(eventName);
    if (listeners === undefined) {
      listeners = new Set<WsMessageListener>();
      this.listeners.set(eventName, listeners);
    }
    listeners.add(listener);
    return () => {
      listeners?.delete(listener);
      if (listeners?.size === 0) {
        this.listeners.delete(eventName);
      }
    };
  }

  onStateChange(listener: WsStateListener): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  connect(serverUrl: string, token: string): void {
    const normalizedUrl = normalizeServerUrl(serverUrl);
    if (token.length === 0) {
      throw new WsError('WebSocket 连接需要认证令牌');
    }
    if (
      normalizedUrl === this.serverUrl &&
      token === this.token &&
      this._state !== 'disconnected'
    ) {
      return;
    }

    this.disconnect();
    this.serverUrl = normalizedUrl;
    this.token = token;
    this.reconnectAttempts = 0;
    this.shouldReconnect = true;
    this.open();
  }

  disconnect(): void {
    this.shouldReconnect = false;
    this.reconnectAttempts = 0;
    this.connectionGeneration += 1;
    this.clearReconnectTimer();
    this.clearConnectTimeout();
    this.clearHeartbeat();

    const socket = this.socket;
    this.socket = null;
    if (socket !== null) {
      socket.onopen = null;
      socket.onmessage = null;
      socket.onerror = null;
      socket.onclose = null;
      try {
        socket.close(1000, 'client disconnect');
      } catch {
        // The connection is already considered closed.
      }
    }
    this.setState('disconnected');
  }

  send(event: string, payload?: unknown, roomId?: number): void {
    if (this._state !== 'connected' || this.socket === null) {
      throw new WsError('WebSocket 尚未连接');
    }
    const envelope: Record<string, unknown> = {
      event,
      ...(roomId === undefined ? {} : { room_id: roomId }),
      ...(payload === undefined ? {} : { payload }),
      timestamp: new Date().toISOString(),
    };
    this.socket.send(JSON.stringify(envelope));
  }

  private open(): void {
    if (!this.shouldReconnect || this.serverUrl === null || this.token === null) {
      return;
    }

    const generation = ++this.connectionGeneration;
    const url = buildWebSocketUrl(this.serverUrl, this.token);
    let socket: WebSocketLike;
    try {
      socket = this.webSocketFactory(url);
    } catch {
      this.setState('disconnected');
      this.scheduleReconnect();
      return;
    }

    this.socket = socket;
    this.setState('connecting');
    socket.onopen = () => {
      if (!this.isCurrent(generation, socket)) return;
    };
    socket.onmessage = (event) => {
      if (this.isCurrent(generation, socket)) {
        this.handleMessage(event.data);
      }
    };
    socket.onerror = () => {
      if (!this.isCurrent(generation, socket)) return;
      this.handleClosed(generation, socket);
      try {
        socket.close(4001, 'connection error');
      } catch {
        // Cleanup already completed.
      }
    };
    socket.onclose = () => {
      this.handleClosed(generation, socket);
    };
    this.connectTimeoutTimer = setTimeout(() => {
      if (!this.isCurrent(generation, socket) || this._state !== 'connecting') {
        return;
      }
      this.handleClosed(generation, socket);
      try {
        socket.close(4000, 'connect timeout');
      } catch {
        // Cleanup already completed.
      }
    }, this.connectTimeoutMs);
  }

  private handleMessage(data: unknown): void {
    if (typeof data !== 'string') return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(data) as unknown;
    } catch {
      return;
    }
    if (!isRecord(parsed) || typeof parsed.event !== 'string') return;
    const message = parsed as WsMessage;
    if (message.event === 'connected') {
      this.clearConnectTimeout();
      this.reconnectAttempts = 0;
      this.setState('connected');
      this.startHeartbeat();
    }
    const listeners = this.listeners.get(message.event);
    if (listeners === undefined) return;
    for (const listener of [...listeners]) {
      listener(message);
    }
  }

  private handleClosed(generation: number, socket: WebSocketLike): void {
    if (!this.isCurrent(generation, socket)) return;
    this.clearConnectTimeout();
    this.clearHeartbeat();
    this.socket = null;
    this.setState('disconnected');
    if (this.shouldReconnect) {
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    if (
      !this.shouldReconnect ||
      this.reconnectTimer !== null ||
      this.reconnectAttempts >= this.maxReconnectAttempts
    ) {
      return;
    }
    const attempt = this.reconnectAttempts;
    this.reconnectAttempts += 1;
    const delay = Math.min(
      this.reconnectMaxDelayMs,
      this.reconnectBaseDelayMs * 2 ** attempt,
    );
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.open();
    }, delay);
  }

  private isCurrent(generation: number, socket: WebSocketLike): boolean {
    return generation === this.connectionGeneration && socket === this.socket;
  }

  private setState(state: WsConnectionState): void {
    if (state === this._state) return;
    this._state = state;
    for (const listener of [...this.stateListeners]) {
      listener(state);
    }
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private clearConnectTimeout(): void {
    if (this.connectTimeoutTimer !== null) {
      clearTimeout(this.connectTimeoutTimer);
      this.connectTimeoutTimer = null;
    }
  }

  private startHeartbeat(): void {
    this.clearHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this._state === 'connected' && this.socket !== null) {
        this.send('heartbeat');
      }
    }, this.heartbeatIntervalMs);
  }

  private clearHeartbeat(): void {
    if (this.heartbeatTimer !== null) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }
}

import { describe, expect, it } from 'vitest';
import type {
  AccountScope,
  MessageCacheEntry,
  NexusRoomWireGuardApi,
  WireGuardStatus,
  WireGuardTunnelConfig,
} from '../src/shared/preload-api';
import type {
  NexusRoomStorage,
  RestTransport,
  RoomSocket,
} from '../src/renderer/nexusroom-client';
import {
  NexusRoomClient,
  NexusRoomClientError,
  parseVlanJoinResponse,
  parseVlanPeerUpdate,
  parseVlanPeers,
  parseRtcIceServers,
} from '../src/renderer/nexusroom-client';
import type {
  WsConnectionState,
  WsMessage,
  WsMessageListener,
} from '../src/main/ws-client';

class FakeRest implements RestTransport {
  readonly getPaths: string[] = [];
  readonly postPaths: string[] = [];
  readonly postBodies: unknown[] = [];
  readonly deletePaths: string[] = [];
  readonly formBodies: FormData[] = [];
  readonly deleteErrors: unknown[] = [];
  private readonly getValues: unknown[] = [];
  private readonly postValues: unknown[] = [];
  private formValue: unknown = {
    file_id: 'file-1',
    url: '/api/v1/files/file-1',
    mime_type: 'image/png',
    size_bytes: 4,
    file_name: 'image.png',
  };
  token: string | null = null;

  queueGet(...values: unknown[]): void {
    this.getValues.push(...values);
  }

  queuePost(...values: unknown[]): void {
    this.postValues.push(...values);
  }

  setFormValue(value: unknown): void {
    this.formValue = value;
  }

  queueDeleteError(error: unknown): void {
    this.deleteErrors.push(error);
  }

  setServerUrl(): void {}

  setToken(token: string | null): void {
    this.token = token;
  }

  async get<T>(path: string): Promise<T> {
    this.getPaths.push(path);
    return this.getValues.shift() as T;
  }

  async post<T>(path: string, body?: unknown): Promise<T> {
    this.postPaths.push(path);
    this.postBodies.push(body);
    return (this.postValues.shift() ?? {}) as T;
  }

  async postForm<T>(_path: string, body: FormData): Promise<T> {
    this.formBodies.push(body);
    return this.formValue as T;
  }

  async delete<T>(path: string): Promise<T> {
    this.deletePaths.push(path);
    const error = this.deleteErrors.shift();
    if (error !== undefined) throw error;
    return undefined as T;
  }
}

class FakeWireGuard implements NexusRoomWireGuardApi {
  available = true;
  readonly startConfigs: WireGuardTunnelConfig[] = [];
  stopCalls = 0;
  startError: unknown = undefined;

  async getAvailability(): Promise<{ available: boolean }> {
    return { available: this.available };
  }

  async generateKeyPair(): Promise<{ public_key: string; private_key: string }> {
    return { public_key: 'client-public-key', private_key: 'client-private-key' };
  }

  async startTunnel(config: WireGuardTunnelConfig): Promise<WireGuardStatus> {
    this.startConfigs.push(config);
    if (this.startError !== undefined) throw this.startError;
    return { available: true, state: 'running', address: config.address };
  }

  async stopTunnel(): Promise<WireGuardStatus> {
    this.stopCalls += 1;
    return { available: true, state: 'idle' };
  }

  async getStatus(): Promise<WireGuardStatus> {
    return { available: this.available, state: 'idle' };
  }
}

class FakeSocket implements RoomSocket {
  state: WsConnectionState = 'disconnected';
  readonly sent: Array<{
    event: string;
    payload: unknown;
    roomId: number | undefined;
  }> = [];
  private readonly listeners = new Map<string, Set<WsMessageListener>>();
  private readonly stateListeners = new Set<(state: WsConnectionState) => void>();

  connect(): void {
    this.setState('connected');
  }

  disconnect(): void {
    this.setState('disconnected');
  }

  onStateChange(listener: (state: WsConnectionState) => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  setState(state: WsConnectionState): void {
    this.state = state;
    for (const listener of this.stateListeners) listener(state);
  }

  send(event: string, payload?: unknown, roomId?: number): void {
    this.sent.push({ event, payload, roomId });
  }

  on(eventName: string, listener: WsMessageListener): () => void {
    const listeners = this.listeners.get(eventName) ?? new Set<WsMessageListener>();
    listeners.add(listener);
    this.listeners.set(eventName, listeners);
    return () => listeners.delete(listener);
  }

  emit(event: string, payload: unknown, roomId?: number): void {
    const message: WsMessage = {
      event,
      ...(roomId === undefined ? {} : { room_id: roomId }),
      payload,
    };
    for (const listener of this.listeners.get(event) ?? []) listener(message);
  }
}

function createStorage(): NexusRoomStorage & {
  readonly sessions: Map<string, string>;
  readonly messages: Map<string, MessageCacheEntry[]>;
} {
  const sessions = new Map<string, string>();
  const messages = new Map<string, MessageCacheEntry[]>();
  const key = (scope: AccountScope): string => `${scope.serverUrl}|${scope.accountId}`;
  return {
    sessions,
    messages,
    async saveSession(scope, token) {
      sessions.set(key(scope), token);
    },
    async getMessages(scope, roomId) {
      const values = messages.get(key(scope)) ?? [];
      return roomId === undefined ? [...values] : values.filter((item) => item.roomId === roomId);
    },
    async saveMessages(scope, incoming) {
      const values = messages.get(key(scope)) ?? [];
      for (const message of incoming) {
        const index = values.findIndex((item) => item.id === message.id);
        if (index < 0) values.push(message);
        else values[index] = message;
      }
      messages.set(key(scope), values);
    },
  };
}

function message(id: number, roomId = 1, senderId = 2): Record<string, unknown> {
  return {
    id,
    room_id: roomId,
    sender_id: senderId,
    type: 'text',
    content: `message-${id}`,
    created_at: '2026-08-11T00:00:00Z',
    sender: { id: senderId, nickname: `user-${senderId}`, avatar_url: '' },
  };
}

function vlanJoinResponse(): Record<string, unknown> {
  return {
    assigned_ip: '10.0.8.2/24',
    server_public_key: 'server-public-key',
    server_endpoint: 'wg.example.test:51820',
    dns: '10.0.8.1',
    peers: [{
      user_id: 22,
      nickname: 'Bob',
      public_key: 'bob-public-key',
      allowed_ips: '10.0.8.3/24',
    }],
  };
}

function vlanPeers(): Record<string, unknown>[] {
  return [{
    user_id: 22,
    nickname: 'Bob',
    public_key: 'bob-public-key',
    assigned_ip: '10.0.8.3/24',
    last_handshake: '2026-08-11T00:00:00Z',
  }];
}

describe('NexusRoomClient', () => {
  it('exposes connected RTC ICE configuration and RTC signal transport', () => {
    expect(parseRtcIceServers({
      rtc: {
        ice_servers: [
          { urls: 'stun:one.test:3478' },
          { urls: ['turn:two.test:3478'], username: 'user', credential: 'secret' },
        ],
      },
    })).toEqual([
      { urls: 'stun:one.test:3478' },
      { urls: ['turn:two.test:3478'], username: 'user', credential: 'secret' },
    ]);

    const storage = createStorage();
    const socket = new FakeSocket();
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: new FakeRest(),
      wsClient: socket,
    });
    socket.emit('connected', {
      rtc: { ice_servers: [{ urls: 'stun:connected.test:3478' }] },
    });
    expect(client.rtcIceServers).toEqual([{ urls: 'stun:connected.test:3478' }]);
    client.sendRtc('rtc.speaking', 3, { speaking: false });
    expect(socket.sent.at(-1)).toMatchObject({
      event: 'rtc.speaking',
      roomId: 3,
      payload: { speaking: false },
    });
  });

  it('lists, creates, and deletes strictly validated room ingresses', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    rest.queueGet([
      {
        id: 9,
        ingress_id: 'ingress-9',
        rtmp_url: 'rtmps://stream.example:1935/live',
        stream_key: 'stream-key-9',
        publish_url: 'rtmps://stream.example:1935/live/stream-key-9',
        label: 'Desk',
        is_active: true,
      },
    ]);
    rest.queuePost({
      id: 10,
      ingress_id: 'ingress-10',
      rtmp_url: 'rtmp://stream.example:1935/live',
      stream_key: 'stream-key-10',
      publish_url: 'rtmp://stream.example:1935/live/stream-key-10',
      label: 'Camera',
    });
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
    });
    await client.login('alice', 'password');

    await expect(client.listRoomIngresses(7)).resolves.toEqual([
      {
        id: 9,
        ingressId: 'ingress-9',
        rtmpUrl: 'rtmps://stream.example:1935/live',
        streamKey: 'stream-key-9',
        publishUrl: 'rtmps://stream.example:1935/live/stream-key-9',
        label: 'Desk',
        isActive: true,
      },
    ]);
    await expect(client.createRoomIngress(7, ' Camera ')).resolves.toMatchObject({
      id: 10,
      publishUrl: 'rtmp://stream.example:1935/live/stream-key-10',
      isActive: false,
    });
    await client.deleteRoomIngress(7, 10);

    expect(rest.getPaths).toEqual(['/api/v1/rooms/7/ingresses']);
    expect(rest.postPaths).toEqual(['/api/v1/auth/login', '/api/v1/rooms/7/ingresses']);
    expect(rest.postBodies[1]).toEqual({ label: 'Camera' });
    expect(rest.deletePaths).toEqual(['/api/v1/rooms/7/ingresses/10']);
  });

  it('rejects unsafe ingress publish addresses and stream keys', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    rest.queueGet(
      [{
        id: 1,
        ingress_id: 'ingress-1',
        rtmp_url: 'rtmp://stream.example/live',
        stream_key: 'stream-key-1',
        publish_url: 'https://stream.example/live/stream-key-1',
        label: 'Bad scheme',
      }],
      [{
        id: 2,
        ingress_id: 'ingress-2',
        rtmp_url: 'rtmp://stream.example/live',
        stream_key: 'bad/key',
        publish_url: 'rtmp://stream.example/live/bad/key',
        label: 'Bad key',
      }],
    );
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
    });
    await client.login('alice', 'password');
    await expect(client.listRoomIngresses(1)).rejects.toThrow('rtmp/rtmps');
    await expect(client.listRoomIngresses(1)).rejects.toThrow('stream key');
  });

  it('only forwards ingress updates for the current room', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    const socket = new FakeSocket();
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: socket,
    });
    await client.login('alice', 'password');
    client.connect();
    client.switchRoom(7);
    const updates: number[] = [];
    client.onIngressUpdate((event) => updates.push(event.roomId));
    socket.emit('room.ingress_update', { room_id: 8, action: 'created' }, 8);
    socket.emit('room.ingress_update', { room_id: 7, action: 'status_changed' }, 7);
    expect(updates).toEqual([7]);
  });

  it('stores login sessions by normalized server origin and account id', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost(
      { user_id: 11, user_display_id: 'A11', token: 'token-a' },
      { user_id: 22, user_display_id: 'B22', token: 'token-b' },
    );
    const first = new NexusRoomClient({ serverUrl: 'https://chat.test/', storage, restClient: rest, wsClient: new FakeSocket() });
    const second = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: new FakeSocket() });

    await first.login('alice', 'password');
    await second.login('bob', 'password');

    expect(storage.sessions.get('https://chat.test|11')).toBe('token-a');
    expect(storage.sessions.get('https://chat.test|22')).toBe('token-b');
  });

  it('keeps message caches separate for two accounts', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost(
      { user_id: 11, user_display_id: 'A11', token: 'token-a' },
      { user_id: 22, user_display_id: 'B22', token: 'token-b' },
    );
    const socketA = new FakeSocket();
    const socketB = new FakeSocket();
    const first = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: socketA });
    const second = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: socketB });
    await first.login('alice', 'password');
    await second.login('bob', 'password');
    first.onChatMessage(() => {});
    second.onChatMessage(() => {});
    socketA.emit('chat.message', message(1));
    socketB.emit('chat.message', message(2));
    await Promise.resolve();

    expect(storage.messages.get('https://chat.test|11')?.map((item) => item.id)).toEqual([1]);
    expect(storage.messages.get('https://chat.test|22')?.map((item) => item.id)).toEqual([2]);
  });

  it('pulls pages using after_id and writes each page to the scoped cache', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    rest.queueGet([message(6), message(7)], [message(8)]);
    const client = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: new FakeSocket() });
    await client.login('alice', 'password');

    const result = await client.syncMessages(1, { afterId: 5, limit: 2 });
    expect(result.map((item) => item.id)).toEqual([6, 7, 8]);
    expect(rest.getPaths).toEqual([
      '/api/v1/rooms/1/messages?after_id=5&limit=2',
      '/api/v1/rooms/1/messages?after_id=7&limit=2',
    ]);
  });

  it('leaves the old room before joining the new room', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    const socket = new FakeSocket();
    const client = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: socket });
    await client.login('alice', 'password');
    client.connect();
    client.switchRoom(1);
    client.switchRoom(2);

    expect(socket.sent.map((item) => `${item.event}:${item.roomId}`)).toEqual([
      'room.join:1',
      'room.leave:1',
      'room.join:2',
    ]);
  });

  it('joins a room selected while the socket is connecting once connected', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    const socket = new FakeSocket();
    const client = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: socket });
    await client.login('alice', 'password');
    socket.setState('connecting');
    client.switchRoom(9);
    expect(socket.sent).toHaveLength(0);
    socket.setState('connected');
    expect(socket.sent.map((item) => `${item.event}:${item.roomId}`)).toEqual(['room.join:9']);
    client.disconnect();
    socket.setState('connected');
    expect(socket.sent).toHaveLength(1);
  });

  it('sends text and image chat payloads and rejects cross-origin images', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    const socket = new FakeSocket();
    const client = new NexusRoomClient({ serverUrl: 'https://chat.test', storage, restClient: rest, wsClient: socket });
    await client.login('alice', 'password');
    client.connect();
    await client.sendText(1, '  hello  ', 'client-1');
    await client.sendChat(1, 'https://chat.test/uploads/image.png', 'image', { alt: 'image' });

    expect(socket.sent[1]).toMatchObject({
      event: 'chat.send',
      roomId: 1,
      payload: { type: 'text', content: 'hello', client_message_id: 'client-1' },
    });
    expect(socket.sent[2]).toMatchObject({
      event: 'chat.send',
      roomId: 1,
      payload: { type: 'image', content: 'https://chat.test/uploads/image.png', meta: { alt: 'image' } },
    });
    await expect(client.sendText(1, '   ')).rejects.toBeInstanceOf(NexusRoomClientError);
    await expect(client.sendChat(1, 'https://evil.test/image.png', 'image')).rejects.toBeInstanceOf(NexusRoomClientError);
  });

  it('uploads an image, resolves same-origin URLs, and caches chat.message', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    const socket = new FakeSocket();
    const client = new NexusRoomClient({ serverUrl: 'https://chat.test/', storage, restClient: rest, wsClient: socket });
    await client.login('alice', 'password');
    const uploaded = await client.uploadImage(1, new Blob(['image'], { type: 'image/png' }), 'picture.png');
    expect(uploaded.url).toBe('https://chat.test/api/v1/files/file-1');
    expect(rest.formBodies[0]?.get('room_id')).toBe('1');
    expect(rest.formBodies[0]?.get('file')).toBeInstanceOf(Blob);

    client.onChatMessage(() => {});
    socket.emit('chat.message', message(4));
    await Promise.resolve();
    expect(storage.messages.get('https://chat.test|11')?.map((item) => item.id)).toEqual([4]);

    rest.setFormValue({ file_id: 'file-2', url: 'https://evil.test/file', mime_type: 'image/png', size_bytes: 1 });
    await expect(client.uploadImage(1, new Blob(['x']))).rejects.toThrow('server origin');
  });

  it('loads same-origin images with Authorization and rejects unsafe URLs before fetch', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'secret-image-token' });
    let fetchCalls = 0;
    let request: Request | undefined;
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      fetchImpl: async (input, init) => {
        fetchCalls += 1;
        request = new Request(input, init);
        return new Response('image', {
          status: 200,
          headers: { 'Content-Type': 'image/png' },
        });
      },
    });
    await client.login('alice', 'password');
    const blob = await client.loadImage('/api/v1/files/file-1');
    expect(blob.type).toBe('image/png');
    expect(request?.url).toBe('https://chat.test/api/v1/files/file-1');
    expect(request?.headers.get('Authorization')).toBe('Bearer secret-image-token');

    await expect(client.loadImage('https://evil.test/file')).rejects.toThrow('server origin');
    await expect(client.loadImage('https://user:pass@chat.test/file')).rejects.toThrow('server origin');
    expect(fetchCalls).toBe(1);

    const errorClient = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      fetchImpl: async () => {
        throw new Error('request failed: secret-image-token');
      },
    });
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'secret-image-token' });
    await errorClient.login('alice', 'password');
    await expect(errorClient.loadImage('/api/v1/files/file-1')).rejects.not.toThrow('secret-image-token');
  });

  it('uses the VLAN REST contract, parses snake_case fields, and builds the server peer', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' }, vlanJoinResponse());
    rest.queueGet(vlanPeers());
    const socket = new FakeSocket();
    const wireguard = new FakeWireGuard();
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: socket,
      wireguard,
    });
    await client.login('alice', 'password');

    await expect(client.joinVlan(7)).resolves.toMatchObject({
      state: 'connected',
      roomId: 7,
      assignedIp: '10.0.8.2/24',
      peers: [{ userId: 22, nickname: 'Bob', assignedIp: '10.0.8.3/24' }],
    });
    expect(rest.postPaths).toEqual([
      '/api/v1/auth/login',
      '/api/v1/rooms/7/vlan/join',
    ]);
    expect(rest.postBodies[1]).toEqual({ public_key: 'client-public-key' });
    expect(rest.getPaths).toEqual(['/api/v1/rooms/7/vlan/peers']);
    expect(wireguard.startConfigs).toHaveLength(1);
    expect(wireguard.startConfigs[0]).toMatchObject({
      address: '10.0.8.2/24',
      dns: '10.0.8.1',
      peers: [{
        public_key: 'server-public-key',
        endpoint: 'wg.example.test:51820',
        allowed_ips: '10.0.8.0/24',
        persistent_keepalive: 25,
      }],
    });
    expect(wireguard.startConfigs[0]?.private_key).toBe('client-private-key');
  });

  it('rejects malformed VLAN responses without accepting camelCase aliases', () => {
    expect(() => parseVlanJoinResponse({
      assignedIp: '10.0.8.2/24',
      server_public_key: 'server-public-key',
      server_endpoint: 'wg.example.test:51820',
      peers: [],
    })).toThrow('assigned IP');
    expect(() => parseVlanPeers([{
      user_id: 22,
      nickname: 'Bob',
      publicKey: 'bob-public-key',
      assigned_ip: '10.0.8.3/24',
    }])).toThrow('public key');
  });

  it('filters VLAN peer updates by current enabled room and parses join/leave payloads', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' }, vlanJoinResponse());
    rest.queueGet(vlanPeers());
    const socket = new FakeSocket();
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: socket,
      wireguard: new FakeWireGuard(),
    });
    await client.login('alice', 'password');
    await client.joinVlan(7);
    const updates: string[] = [];
    client.onVlanPeerUpdate((event) => updates.push(`${event.roomId}:${event.action}`));

    socket.emit('vlan.peer_update', {
      room_id: 7,
      action: 'join',
      peer_info: {
        user_id: 23,
        nickname: 'Carol',
        public_key: 'carol-public-key',
        assigned_ip: '10.0.8.4/24',
      },
    }, 7);
    socket.emit('vlan.peer_update', {
      room_id: 8,
      action: 'leave',
      peer_info: { user_id: 23, nickname: '', public_key: '', assigned_ip: '' },
    }, 8);
    expect(updates).toEqual(['7:join']);
    expect(parseVlanPeerUpdate({
      event: 'vlan.peer_update',
      payload: {
        room_id: 7,
        action: 'leave',
        peer_info: { user_id: 23, nickname: '', public_key: '', assigned_ip: '' },
      },
    })).toEqual({ roomId: 7, action: 'leave', peerInfo: { userId: 23 } });
  });

  it('rolls back the server peer when local tunnel startup fails', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' }, vlanJoinResponse());
    const wireguard = new FakeWireGuard();
    wireguard.startError = new Error('uac denied');
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      wireguard,
    });
    await client.login('alice', 'password');

    await expect(client.joinVlan(7)).rejects.toThrow('WireGuard 隧道启动失败');
    expect(rest.deletePaths).toEqual(['/api/v1/rooms/7/vlan/leave']);
    expect(client.vlanSnapshot.state).toBe('error');
  });

  it('reports a clean rollback error when the start failure cannot leave the server peer', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' }, vlanJoinResponse());
    rest.queueDeleteError(new Error('rollback unavailable'));
    const wireguard = new FakeWireGuard();
    wireguard.startError = new Error('uac denied');
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      wireguard,
    });
    await client.login('alice', 'password');

    await expect(client.joinVlan(7)).rejects.toThrow('服务端注销失败');
    expect(client.vlanSnapshot.state).toBe('error');
  });

  it('checks Helper availability before the VLAN join request', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' });
    const wireguard = new FakeWireGuard();
    wireguard.available = false;
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      wireguard,
    });
    await client.login('alice', 'password');

    await expect(client.joinVlan(7)).rejects.toThrow('WireGuard Helper 未找到');
    expect(rest.postPaths).toEqual(['/api/v1/auth/login']);
    expect(client.vlanSnapshot.state).toBe('unavailable');
  });

  it('clears local VLAN state when the leave API fails', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' }, vlanJoinResponse());
    rest.queueGet(vlanPeers());
    rest.queueDeleteError(new Error('server unavailable'));
    const wireguard = new FakeWireGuard();
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      wireguard,
    });
    await client.login('alice', 'password');
    await client.joinVlan(7);
    await client.leaveVlan(7);

    expect(client.vlanSnapshot.state).toBe('disabled');
    expect(client.vlanSnapshot.roomId).toBeNull();
    expect(client.vlanSnapshot.peers).toEqual([]);
    expect(client.vlanSnapshot.error).toContain('服务端注销失败');
    expect(wireguard.stopCalls).toBe(1);
  });

  it('does not start the same VLAN tunnel twice on a double click', async () => {
    const storage = createStorage();
    const rest = new FakeRest();
    rest.queuePost({ user_id: 11, user_display_id: 'A11', token: 'token-a' }, vlanJoinResponse());
    rest.queueGet(vlanPeers());
    const wireguard = new FakeWireGuard();
    const client = new NexusRoomClient({
      serverUrl: 'https://chat.test',
      storage,
      restClient: rest,
      wsClient: new FakeSocket(),
      wireguard,
    });
    await client.login('alice', 'password');
    const first = client.joinVlan(7);
    const second = client.joinVlan(7);
    await Promise.all([first, second]);

    expect(rest.postPaths.filter((path) => path.includes('/vlan/join'))).toHaveLength(1);
    expect(wireguard.startConfigs).toHaveLength(1);
  });
});

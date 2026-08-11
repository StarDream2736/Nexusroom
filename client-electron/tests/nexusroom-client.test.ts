import { describe, expect, it } from 'vitest';
import type {
  AccountScope,
  MessageCacheEntry,
} from '../src/shared/preload-api';
import type {
  NexusRoomStorage,
  RestTransport,
  RoomSocket,
} from '../src/renderer/nexusroom-client';
import { NexusRoomClient, NexusRoomClientError } from '../src/renderer/nexusroom-client';
import type {
  WsConnectionState,
  WsMessage,
  WsMessageListener,
} from '../src/main/ws-client';

class FakeRest implements RestTransport {
  readonly getPaths: string[] = [];
  readonly formBodies: FormData[] = [];
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

  setServerUrl(): void {}

  setToken(token: string | null): void {
    this.token = token;
  }

  async get<T>(path: string): Promise<T> {
    this.getPaths.push(path);
    return this.getValues.shift() as T;
  }

  async post<T>(_path: string, _body?: unknown): Promise<T> {
    void _path;
    void _body;
    return (this.postValues.shift() ?? {}) as T;
  }

  async postForm<T>(_path: string, body: FormData): Promise<T> {
    this.formBodies.push(body);
    return this.formValue as T;
  }

  async delete<T>(_path: string): Promise<T> {
    void _path;
    return undefined as T;
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

describe('NexusRoomClient', () => {
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
});

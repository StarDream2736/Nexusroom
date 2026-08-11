import { normalizeServerUrl } from '../main/server-url';
import {
  RestClient,
} from '../main/rest-client';
import {
  WsClient,
  type WsConnectionState,
  type WsMessage,
  type WsMessageListener,
} from '../main/ws-client';
import type {
  AccountScope,
  MessageCacheEntry,
  NexusRoomStorageApi,
} from '../shared/preload-api';

export type NexusRoomStorage = Pick<
  NexusRoomStorageApi,
  'saveSession' | 'getMessages' | 'saveMessages'
>;

export type RestTransport = Pick<
  RestClient,
  'get' | 'post' | 'postForm' | 'delete' | 'setToken' | 'setServerUrl'
>;

export interface RoomSocket {
  readonly state: WsConnectionState;
  connect(serverUrl: string, token: string): void;
  disconnect(): void;
  send(event: string, payload?: unknown, roomId?: number): void;
  on(eventName: string, listener: WsMessageListener): () => void;
  onStateChange(listener: (state: WsConnectionState) => void): () => void;
}

export interface NexusRoomClientOptions {
  readonly serverUrl: string;
  readonly storage: NexusRoomStorage;
  readonly restClient?: RestTransport;
  readonly wsClient?: RoomSocket;
  readonly fetchImpl?: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;
}

export interface AuthSession {
  readonly userId: number;
  readonly userDisplayId: string;
  readonly token: string;
  readonly scope: AccountScope;
}

export interface RoomSummary {
  readonly id: number;
  readonly name: string;
  readonly roomCode?: string;
  readonly inviteCode?: string;
  readonly ownerId?: number;
  readonly mediaRoomName?: string;
}

export interface RoomMember {
  readonly userId: number;
  readonly nickname: string;
  readonly avatarUrl?: string;
  readonly role?: string;
}

export interface RoomIngress {
  readonly id: number;
  readonly ingressId?: string;
  readonly rtmpUrl?: string;
  readonly streamKey?: string;
  readonly label?: string;
  readonly isActive?: boolean;
}

export interface RoomDetail extends RoomSummary {
  readonly members: readonly RoomMember[];
  readonly ingresses: readonly RoomIngress[];
}

export type ChatMessageType = 'text' | 'image' | 'file';

export interface ChatSender {
  readonly id: number;
  readonly nickname: string;
  readonly avatarUrl?: string;
}

export interface ChatMessage {
  readonly id: number;
  readonly roomId: number;
  readonly senderId: number;
  readonly type: string;
  readonly content: string;
  readonly createdAt: string;
  readonly sender?: ChatSender;
  readonly clientMessageId?: string;
  readonly meta?: unknown;
}

export interface UploadedImage {
  readonly fileId: string;
  readonly url: string;
  readonly mimeType: string;
  readonly sizeBytes: number;
  readonly fileName?: string;
}

export interface RoomMemberEvent {
  readonly userId: number;
  readonly roomId: number;
  readonly nickname?: string;
  readonly avatarUrl?: string;
}

export interface RoomKickedEvent {
  readonly roomId?: number;
  readonly reason: string;
}

export interface RoomDisbandedEvent {
  readonly roomId: number;
}

export class NexusRoomClientError extends Error {
  readonly kind: 'configuration' | 'unauthenticated' | 'invalid-response';

  constructor(
    message: string,
    kind: NexusRoomClientError['kind'] = 'invalid-response',
  ) {
    super(message);
    this.name = 'NexusRoomClientError';
    this.kind = kind;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function readRecord(value: unknown, label: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new NexusRoomClientError(`${label} must be an object`);
  }
  return value;
}

function readId(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw new NexusRoomClientError(`${label} must be a positive integer`);
  }
  return value as number;
}

function readString(value: unknown, label: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new NexusRoomClientError(`${label} must be a non-empty string`);
  }
  return value;
}

function readOptionalString(
  value: unknown,
  label: string,
): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new NexusRoomClientError(`${label} must be a string`);
  }
  return value;
}

function readOptionalId(value: unknown, label: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  return readId(value, label);
}

function readOptionalMeta(value: unknown): unknown {
  if (value === undefined || value === null) return undefined;
  if (!isRecord(value)) {
    throw new NexusRoomClientError('message meta must be an object');
  }
  return value;
}

function readList(value: unknown, label: string): readonly unknown[] {
  if (Array.isArray(value)) return value;
  if (isRecord(value) && Array.isArray(value.items)) return value.items;
  if (isRecord(value) && Array.isArray(value.messages)) return value.messages;
  throw new NexusRoomClientError(`${label} must be an array`);
}

function readRoomSummary(value: unknown): RoomSummary {
  const record = readRecord(value, 'room');
  return {
    id: readId(record.id, 'room id'),
    name: readString(record.name, 'room name'),
    ...(readOptionalString(record.room_code, 'room code') === undefined
      ? {}
      : { roomCode: readOptionalString(record.room_code, 'room code') }),
    ...(readOptionalString(record.invite_code, 'invite code') === undefined
      ? {}
      : { inviteCode: readOptionalString(record.invite_code, 'invite code') }),
    ...(readOptionalId(record.owner_id, 'room owner id') === undefined
      ? {}
      : { ownerId: readOptionalId(record.owner_id, 'room owner id') }),
    ...(readOptionalString(record.media_room_name, 'media room name') === undefined
      ? {}
      : {
          mediaRoomName: readOptionalString(
            record.media_room_name,
            'media room name',
          ),
        }),
  };
}

function readMember(value: unknown): RoomMember {
  const record = readRecord(value, 'room member');
  return {
    userId: readId(record.user_id, 'member user id'),
    nickname: readString(record.nickname, 'member nickname'),
    ...(readOptionalString(record.avatar_url, 'member avatar url') === undefined
      ? {}
      : { avatarUrl: readOptionalString(record.avatar_url, 'member avatar url') }),
    ...(readOptionalString(record.role, 'member role') === undefined
      ? {}
      : { role: readOptionalString(record.role, 'member role') }),
  };
}

function readIngress(value: unknown): RoomIngress {
  const record = readRecord(value, 'room ingress');
  const active = record.is_active;
  if (active !== undefined && typeof active !== 'boolean') {
    throw new NexusRoomClientError('ingress active flag must be a boolean');
  }
  return {
    id: readId(record.id, 'ingress id'),
    ...(readOptionalString(record.ingress_id, 'ingress id') === undefined
      ? {}
      : { ingressId: readOptionalString(record.ingress_id, 'ingress id') }),
    ...(readOptionalString(record.rtmp_url, 'ingress RTMP URL') === undefined
      ? {}
      : { rtmpUrl: readOptionalString(record.rtmp_url, 'ingress RTMP URL') }),
    ...(readOptionalString(record.stream_key, 'ingress stream key') === undefined
      ? {}
      : { streamKey: readOptionalString(record.stream_key, 'ingress stream key') }),
    ...(readOptionalString(record.label, 'ingress label') === undefined
      ? {}
      : { label: readOptionalString(record.label, 'ingress label') }),
    ...(active === undefined ? {} : { isActive: active }),
  };
}

function readChatMessage(value: unknown): ChatMessage {
  const record = readRecord(value, 'chat message');
  const senderValue = record.sender;
  let sender: ChatSender | undefined;
  if (senderValue !== undefined && senderValue !== null) {
    const senderRecord = readRecord(senderValue, 'message sender');
    sender = {
      id: readId(senderRecord.id, 'sender id'),
      nickname: readString(senderRecord.nickname, 'sender nickname'),
      ...(readOptionalString(senderRecord.avatar_url, 'sender avatar url') === undefined
        ? {}
        : {
            avatarUrl: readOptionalString(
              senderRecord.avatar_url,
              'sender avatar url',
            ),
          }),
    };
  }
  const clientMessageId = readOptionalString(
    record.client_message_id,
    'client message id',
  );
  return {
    id: readId(record.id, 'message id'),
    roomId: readId(record.room_id, 'message room id'),
    senderId: readId(record.sender_id, 'message sender id'),
    type: readString(record.type, 'message type'),
    content: readString(record.content, 'message content'),
    createdAt: readString(record.created_at, 'message created time'),
    ...(sender === undefined ? {} : { sender }),
    ...(clientMessageId === undefined ? {} : { clientMessageId }),
    ...(record.meta === undefined || record.meta === null
      ? {}
      : { meta: readOptionalMeta(record.meta) }),
  };
}

function toCacheEntry(message: ChatMessage): MessageCacheEntry {
  return {
    id: message.id,
    roomId: message.roomId,
    senderId: message.senderId,
    type: message.type,
    content: message.content,
    createdAt: message.createdAt,
    senderNickname: message.sender?.nickname,
    senderAvatarUrl: message.sender?.avatarUrl,
    meta: message.meta,
  };
}

function mergeWsPayload(message: WsMessage): Record<string, unknown> {
  const payload = isRecord(message.payload) ? { ...message.payload } : {};
  if (message.room_id !== undefined && payload.room_id === undefined) {
    payload.room_id = message.room_id;
  }
  return payload;
}

function readMemberEvent(message: WsMessage): RoomMemberEvent {
  const record = mergeWsPayload(message);
  return {
    userId: readId(record.user_id, 'member event user id'),
    roomId: readId(record.room_id, 'member event room id'),
    ...(readOptionalString(record.nickname, 'member event nickname') === undefined
      ? {}
      : { nickname: readOptionalString(record.nickname, 'member event nickname') }),
    ...(readOptionalString(record.avatar_url, 'member event avatar url') === undefined
      ? {}
      : {
          avatarUrl: readOptionalString(
            record.avatar_url,
            'member event avatar url',
          ),
        }),
  };
}

function readKickedEvent(message: WsMessage): RoomKickedEvent {
  const record = mergeWsPayload(message);
  return {
    ...(readOptionalId(record.room_id, 'kicked room id') === undefined
      ? {}
      : { roomId: readOptionalId(record.room_id, 'kicked room id') }),
    reason: readString(record.reason, 'kick reason'),
  };
}

function readDisbandedEvent(message: WsMessage): RoomDisbandedEvent {
  const record = mergeWsPayload(message);
  return { roomId: readId(record.room_id, 'disbanded room id') };
}

export class NexusRoomClient {
  readonly serverUrl: string;
  readonly storage: NexusRoomStorage;
  readonly rest: RestTransport;
  readonly socket: RoomSocket;

  private sessionValue: AuthSession | null = null;
  private activeRoomId: number | null = null;
  private messageSequence = 0;
  private readonly fetchImpl: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;

  constructor(options: NexusRoomClientOptions) {
    this.serverUrl = normalizeServerUrl(options.serverUrl);
    this.storage = options.storage;
    this.rest = options.restClient ?? new RestClient({ serverUrl: this.serverUrl });
    this.socket = options.wsClient ?? new WsClient();
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
    this.rest.setServerUrl(this.serverUrl);
    this.socket.onStateChange((state) => {
      if (state === 'connected' && this.activeRoomId !== null) {
        this.socket.send('room.join', {}, this.activeRoomId);
      }
    });
  }

  get session(): AuthSession | null {
    return this.sessionValue;
  }

  get currentRoomId(): number | null {
    return this.activeRoomId;
  }

  async login(username: string, password: string): Promise<AuthSession> {
    if (username.length === 0 || password.length === 0) {
      throw new NexusRoomClientError('username and password are required', 'configuration');
    }
    const raw = await this.rest.post<unknown>('/api/v1/auth/login', {
      username,
      password,
    });
    const record = readRecord(raw, 'login response');
    const session: AuthSession = {
      userId: readId(record.user_id, 'user id'),
      userDisplayId: readString(record.user_display_id, 'user display id'),
      token: readString(record.token, 'access token'),
      scope: { serverUrl: this.serverUrl, accountId: readId(record.user_id, 'user id') },
    };
    await this.storage.saveSession(session.scope, session.token);
    this.rest.setToken(session.token);
    this.sessionValue = session;
    return session;
  }

  connect(): void {
    const session = this.requireSession();
    this.socket.connect(this.serverUrl, session.token);
  }

  disconnect(): void {
    this.socket.disconnect();
    this.activeRoomId = null;
  }

  async listRooms(): Promise<readonly RoomSummary[]> {
    this.requireSession();
    const raw = await this.rest.get<unknown>('/api/v1/rooms');
    return readList(raw, 'room list').map(readRoomSummary);
  }

  async getRoomDetail(roomId: number): Promise<RoomDetail> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    const raw = await this.rest.get<unknown>(`/api/v1/rooms/${id}`);
    const record = readRecord(raw, 'room detail');
    const summary = readRoomSummary(record);
    const members = record.members === undefined
      ? []
      : readList(record.members, 'room members').map(readMember);
    const ingresses = record.ingresses === undefined
      ? []
      : readList(record.ingresses, 'room ingresses').map(readIngress);
    return { ...summary, members, ingresses };
  }

  async createRoom(name: string): Promise<RoomSummary> {
    this.requireSession();
    if (name.trim().length === 0) {
      throw new NexusRoomClientError('room name is required', 'configuration');
    }
    return readRoomSummary(
      await this.rest.post<unknown>('/api/v1/rooms', { name }),
    );
  }

  async joinRoom(inviteCode: string): Promise<RoomSummary> {
    this.requireSession();
    if (inviteCode.trim().length === 0) {
      throw new NexusRoomClientError('invite code is required', 'configuration');
    }
    return readRoomSummary(
      await this.rest.post<unknown>('/api/v1/rooms/join', {
        invite_code: inviteCode,
      }),
    );
  }

  async leaveRoom(roomId: number): Promise<void> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    if (this.activeRoomId === id) {
      this.leaveSocketRoom(id);
      this.activeRoomId = null;
    }
    await this.rest.delete(`/api/v1/rooms/${id}/leave`);
  }

  switchRoom(roomId: number): void {
    const id = readId(roomId, 'room id');
    if (this.activeRoomId === id) return;
    const previous = this.activeRoomId;
    if (previous !== null) {
      this.leaveSocketRoom(previous);
    }
    this.activeRoomId = id;
    if (this.socket.state === 'connected') {
      this.socket.send('room.join', {}, id);
    }
  }

  async syncMessages(
    roomId: number,
    options: { readonly afterId?: number; readonly limit?: number } = {},
  ): Promise<readonly ChatMessage[]> {
    const session = this.requireSession();
    const id = readId(roomId, 'room id');
    const limit = options.limit ?? 50;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
      throw new NexusRoomClientError('message limit must be between 1 and 100', 'configuration');
    }
    let cursor = options.afterId;
    if (cursor !== undefined) {
      cursor = readId(cursor, 'after message id');
    } else {
      const cached = await this.storage.getMessages(session.scope, id);
      for (const message of cached) {
        if (message.id > (cursor ?? 0)) cursor = message.id;
      }
    }

    const messages: ChatMessage[] = [];
    while (true) {
      const query = cursor === undefined
        ? `limit=${limit}`
        : `after_id=${cursor}&limit=${limit}`;
      const raw = await this.rest.get<unknown>(
        `/api/v1/rooms/${id}/messages?${query}`,
      );
      const page = readList(raw, 'message list').map(readChatMessage);
      if (page.length === 0) break;
      await this.storage.saveMessages(session.scope, page.map(toCacheEntry));
      messages.push(...page);
      if (page.length < limit) break;
      const nextCursor = page[page.length - 1]?.id;
      if (nextCursor === undefined || (cursor !== undefined && nextCursor <= cursor)) {
        throw new NexusRoomClientError('message pagination did not advance');
      }
      cursor = nextCursor;
    }
    return messages;
  }

  async uploadImage(
    roomId: number,
    file: Blob,
    fileName?: string,
  ): Promise<UploadedImage> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    if (!(file instanceof Blob)) {
      throw new NexusRoomClientError('image file must be a Blob', 'configuration');
    }
    const form = new FormData();
    form.append('room_id', String(id));
    const inferredName = fileName ?? (
      typeof file === 'object' && 'name' in file && typeof file.name === 'string'
        ? file.name
        : 'image'
    );
    form.append('file', file, inferredName);
    const raw = await this.rest.postForm<unknown>('/api/v1/files/upload', form);
    const record = readRecord(raw, 'upload response');
    const url = this.resolveImageUrl(readString(record.url, 'uploaded image URL'));
    const mimeType = readString(record.mime_type, 'uploaded image MIME type');
    if (!mimeType.toLowerCase().startsWith('image/')) {
      throw new NexusRoomClientError('uploaded file is not an image');
    }
    const sizeBytes = record.size_bytes;
    if (!Number.isSafeInteger(sizeBytes) || (sizeBytes as number) < 0) {
      throw new NexusRoomClientError('uploaded image size is invalid');
    }
    return {
      fileId: readString(record.file_id, 'uploaded file id'),
      url,
      mimeType,
      sizeBytes: sizeBytes as number,
      ...(readOptionalString(record.file_name, 'uploaded file name') === undefined
        ? {}
        : { fileName: readOptionalString(record.file_name, 'uploaded file name') }),
    };
  }

  async sendImage(
    roomId: number,
    file: Blob,
    meta: Record<string, unknown> = {},
    fileName?: string,
  ): Promise<UploadedImage> {
    const uploaded = await this.uploadImage(roomId, file, fileName);
    await this.sendChat(roomId, uploaded.url, 'image', {
      ...meta,
      file_id: uploaded.fileId,
      mime_type: uploaded.mimeType,
      size_bytes: uploaded.sizeBytes,
      ...(uploaded.fileName === undefined ? {} : { file_name: uploaded.fileName }),
    });
    return uploaded;
  }

  async sendChat(
    roomId: number,
    content: string,
    type: ChatMessageType = 'text',
    meta?: Record<string, unknown>,
    clientMessageId?: string,
  ): Promise<void> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    const messageContent = readString(content, 'message content');
    const messageType = type;
    if (messageType !== 'text' && messageType !== 'image' && messageType !== 'file') {
      throw new NexusRoomClientError('unsupported message type', 'configuration');
    }
    if (messageType === 'image') this.resolveImageUrl(messageContent);
    if (this.activeRoomId !== id) this.switchRoom(id);
    if (this.socket.state !== 'connected') {
      throw new NexusRoomClientError('WebSocket is not connected', 'unauthenticated');
    }
    const outgoingClientMessageId = clientMessageId ?? `${Date.now()}-${this.messageSequence++}`;
    this.socket.send(
      'chat.send',
      {
        type: messageType,
        content: messageContent,
        client_message_id: outgoingClientMessageId,
        ...(meta === undefined ? {} : { meta }),
      },
      id,
    );
  }

  async sendText(
    roomId: number,
    content: string,
    clientMessageId?: string,
  ): Promise<void> {
    const trimmed = content.trim();
    if (trimmed.length === 0) {
      throw new NexusRoomClientError('message content is required', 'configuration');
    }
    return this.sendChat(roomId, trimmed, 'text', undefined, clientMessageId);
  }

  onChatMessage(listener: (message: ChatMessage) => void): () => void {
    return this.socket.on('chat.message', (event) => {
      try {
        const message = readChatMessage(mergeWsPayload(event));
        listener(message);
        const session = this.sessionValue;
        if (session !== null) {
          try {
            void this.storage
              .saveMessages(session.scope, [toCacheEntry(message)])
              .catch(() => undefined);
          } catch {
            // A synchronous storage failure must not escape the socket callback.
          }
        }
      } catch {
        // Ignore malformed external events; the socket remains usable.
      }
    });
  }

  onMemberJoin(listener: (event: RoomMemberEvent) => void): () => void {
    return this.subscribe('room.member_join', readMemberEvent, listener);
  }

  onMemberLeave(listener: (event: RoomMemberEvent) => void): () => void {
    return this.subscribe('room.member_leave', readMemberEvent, listener);
  }

  onKicked(listener: (event: RoomKickedEvent) => void): () => void {
    return this.subscribe('room.kicked', readKickedEvent, listener);
  }

  onDisbanded(listener: (event: RoomDisbandedEvent) => void): () => void {
    return this.subscribe('room.disbanded', readDisbandedEvent, listener);
  }

  private subscribe<T>(
    eventName: string,
    parser: (message: WsMessage) => T,
    listener: (event: T) => void,
  ): () => void {
    return this.socket.on(eventName, (message) => {
      try {
        listener(parser(message));
      } catch {
        // Ignore malformed external events; the socket remains usable.
      }
    });
  }

  private leaveSocketRoom(roomId: number): void {
    if (this.socket.state === 'connected') {
      this.socket.send('room.leave', {}, roomId);
    }
  }

  private requireSession(): AuthSession {
    if (this.sessionValue === null) {
      throw new NexusRoomClientError('Login is required', 'unauthenticated');
    }
    return this.sessionValue;
  }

  async loadImage(rawUrl: string): Promise<Blob> {
    const session = this.requireSession();
    const url = this.resolveImageUrl(rawUrl);
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        method: 'GET',
        redirect: 'error',
        headers: {
          Accept: 'image/*',
          Authorization: `Bearer ${session.token}`,
        },
      });
    } catch {
      throw new NexusRoomClientError('Image request failed');
    }
    if (!response.ok) {
      throw new NexusRoomClientError(`Image request failed (HTTP ${response.status})`);
    }
    const contentType = response.headers.get('Content-Type')?.split(';', 1)[0]?.trim();
    if (contentType === undefined || !contentType.toLowerCase().startsWith('image/')) {
      throw new NexusRoomClientError('Image response has an invalid content type');
    }
    return response.blob();
  }

  private resolveImageUrl(value: string): string {
    let url: URL;
    try {
      url = new URL(value, this.serverUrl);
    } catch {
      throw new NexusRoomClientError('Image URL is invalid', 'configuration');
    }
    if (
      (url.protocol !== 'http:' && url.protocol !== 'https:') ||
      url.origin !== this.serverUrl ||
      url.username.length > 0 ||
      url.password.length > 0 ||
      !url.pathname.startsWith('/')
    ) {
      throw new NexusRoomClientError('Image URL must use the server origin', 'configuration');
    }
    return url.toString();
  }
}

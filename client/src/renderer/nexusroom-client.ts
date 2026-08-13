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
import {
  assertValidStreamKey,
} from './stream-url';
import type {
  AccountScope,
  MessageCacheEntry,
  NexusRoomStorageApi,
  NexusRoomWireGuardApi,
} from '../shared/preload-api';
import {
  VlanSessionController,
  type VlanErrorPhase,
  type VlanJoinResponse,
  type VlanPeer,
  type VlanPeerUpdate,
  type VlanSessionDriver,
  type VlanSnapshot,
} from './vlan-session';

export {
  buildVlanTunnelConfig,
  deriveIPv4Subnet,
  VlanSessionController,
} from './vlan-session';
export type {
  VlanErrorPhase,
  VlanJoinPeer,
  VlanJoinResponse,
  VlanPeer,
  VlanPeerInfo,
  VlanPeerUpdate,
  VlanSessionDriver,
  VlanSnapshot,
  VlanState,
} from './vlan-session';

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

export interface RtcIceServer {
  readonly urls: string | readonly string[];
  readonly username?: string;
  readonly credential?: string;
}

export type VoiceEventName =
  | 'connected'
  | 'rtc.answer'
  | 'rtc.offer'
  | 'rtc.ice'
  | 'rtc.participants'
  | 'rtc.state'
  | 'rtc.error'
  | 'voice.state_update';

export type VoiceClientEvent =
  | 'rtc.offer'
  | 'rtc.answer'
  | 'rtc.ice'
  | 'rtc.leave'
  | 'rtc.speaking'
  | 'voice.mute';

export interface NexusRoomClientOptions {
  readonly serverUrl: string;
  readonly storage: NexusRoomStorage;
  readonly restClient?: RestTransport;
  readonly wsClient?: RoomSocket;
  readonly wireguard?: NexusRoomWireGuardApi;
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
  readonly ingressId: string;
  readonly rtmpUrl: string;
  readonly streamKey: string;
  readonly publishUrl: string;
  readonly label: string;
  readonly isActive: boolean;
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

export interface RoomIngressUpdateEvent {
  readonly roomId: number;
  readonly action: string;
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

export function parseRtcIceServers(value: unknown): readonly RtcIceServer[] {
  const root = isRecord(value) && isRecord(value.rtc) ? value.rtc : value;
  const rawServers = isRecord(root) ? root.ice_servers : undefined;
  if (!Array.isArray(rawServers)) return [];
  const servers: RtcIceServer[] = [];
  for (const rawServer of rawServers) {
    if (!isRecord(rawServer)) continue;
    const rawUrls = rawServer.urls;
    const urls = typeof rawUrls === 'string'
      ? rawUrls.trim()
      : Array.isArray(rawUrls)
        ? rawUrls
          .filter((url): url is string => typeof url === 'string' && url.trim().length > 0)
          .map((url) => url.trim())
        : [];
    if ((typeof urls === 'string' && urls.length === 0) || (Array.isArray(urls) && urls.length === 0)) {
      continue;
    }
    const username = typeof rawServer.username === 'string' && rawServer.username.length > 0
      ? rawServer.username
      : undefined;
    const credential = typeof rawServer.credential === 'string' && rawServer.credential.length > 0
      ? rawServer.credential
      : undefined;
    servers.push({
      urls,
      ...(username === undefined ? {} : { username }),
      ...(credential === undefined ? {} : { credential }),
    });
  }
  return servers;
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

function readRtmpUrl(value: unknown, label: string): string {
  const raw = readString(value, label);
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new NexusRoomClientError(`${label} must be a valid RTMP URL`);
  }
  if (
    (url.protocol !== 'rtmp:' && url.protocol !== 'rtmps:') ||
    url.hostname.length === 0 ||
    url.username.length > 0 ||
    url.password.length > 0 ||
    url.search.length > 0 ||
    url.hash.length > 0 ||
    url.pathname.replace(/\/+$/gu, '') !== '/live'
  ) {
    throw new NexusRoomClientError(`${label} must use rtmp/rtmps and end at /live`);
  }
  return url.toString().replace(/\/+$/u, '');
}

function readPublishUrl(
  value: unknown,
  label: string,
  rtmpUrl: string,
  streamKey: string,
): string {
  const raw = readString(value, label);
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new NexusRoomClientError(`${label} must be a valid RTMP URL`);
  }
  const base = new URL(rtmpUrl);
  if (
    (url.protocol !== 'rtmp:' && url.protocol !== 'rtmps:') ||
    url.hostname.length === 0 ||
    url.username.length > 0 ||
    url.password.length > 0 ||
    url.search.length > 0 ||
    url.hash.length > 0 ||
    url.protocol !== base.protocol ||
    url.hostname !== base.hostname ||
    url.port !== base.port ||
    url.pathname !== `/live/${streamKey}`
  ) {
    throw new NexusRoomClientError(
      `${label} must use rtmp/rtmps and end at /live/{stream_key}`,
    );
  }
  return url.toString();
}

function buildIngressPublishUrl(rtmpUrl: string, streamKey: string): string {
  return `${rtmpUrl.replace(/\/+$/u, '')}/${streamKey}`;
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

function readIngress(value: unknown, requirePublishUrl: boolean): RoomIngress {
  const record = readRecord(value, 'room ingress');
  const rtmpUrl = readRtmpUrl(record.rtmp_url, 'ingress RTMP URL');
  const streamKey = readString(record.stream_key, 'ingress stream key');
  try {
    assertValidStreamKey(streamKey, 'ingress stream key');
  } catch (error) {
    throw new NexusRoomClientError(error instanceof Error ? error.message : 'ingress stream key is invalid');
  }
  const publishValue = record.publish_url;
  if (requirePublishUrl && typeof publishValue !== 'string') {
    throw new NexusRoomClientError('ingress publish URL must be a non-empty string');
  }
  const publishUrl = publishValue === undefined || publishValue === null
    ? buildIngressPublishUrl(rtmpUrl, streamKey)
    : readPublishUrl(publishValue, 'ingress publish URL', rtmpUrl, streamKey);
  const active = record.is_active;
  if (active !== undefined && typeof active !== 'boolean') {
    throw new NexusRoomClientError('ingress active flag must be a boolean');
  }
  return {
    id: readId(record.id, 'ingress id'),
    ingressId: readString(record.ingress_id, 'ingress id'),
    rtmpUrl,
    streamKey,
    publishUrl,
    label: readString(record.label, 'ingress label'),
    isActive: active ?? false,
  };
}

function readNonBlankString(value: unknown, label: string): string {
  const result = readString(value, label).trim();
  if (result.length === 0) {
    throw new NexusRoomClientError(`${label} must be a non-empty string`);
  }
  return result;
}

function readOptionalNonBlankString(
  value: unknown,
  label: string,
): string | undefined {
  if (value === undefined || value === null) return undefined;
  return readNonBlankString(value, label);
}

function readVlanUpdateString(
  value: unknown,
  label: string,
): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw new NexusRoomClientError(`${label} must be a string`);
  }
  const result = value.trim();
  return result.length === 0 ? undefined : result;
}

function readVlanJoinPeer(value: unknown): import('./vlan-session').VlanJoinPeer {
  const record = readRecord(value, 'VLAN join peer');
  return {
    userId: readId(record.user_id, 'VLAN peer user id'),
    nickname: readNonBlankString(record.nickname, 'VLAN peer nickname'),
    publicKey: readNonBlankString(record.public_key, 'VLAN peer public key'),
    allowedIps: readNonBlankString(record.allowed_ips, 'VLAN peer allowed IPs'),
  };
}

function readVlanPeer(value: unknown): VlanPeer {
  const record = readRecord(value, 'VLAN peer');
  const lastHandshake = readOptionalNonBlankString(
    record.last_handshake,
    'VLAN peer last handshake',
  );
  return {
    userId: readId(record.user_id, 'VLAN peer user id'),
    nickname: readNonBlankString(record.nickname, 'VLAN peer nickname'),
    publicKey: readNonBlankString(record.public_key, 'VLAN peer public key'),
    assignedIp: readNonBlankString(record.assigned_ip, 'VLAN peer assigned IP'),
    ...(lastHandshake === undefined ? {} : { lastHandshake }),
  };
}

export function parseVlanJoinResponse(value: unknown): VlanJoinResponse {
  const record = readRecord(value, 'VLAN join response');
  const dns = readOptionalNonBlankString(record.dns, 'VLAN DNS');
  if (!Array.isArray(record.peers)) {
    throw new NexusRoomClientError('VLAN join peers must be an array');
  }
  return {
    assignedIp: readNonBlankString(record.assigned_ip, 'VLAN assigned IP'),
    serverPublicKey: readNonBlankString(
      record.server_public_key,
      'VLAN server public key',
    ),
    serverEndpoint: readNonBlankString(
      record.server_endpoint,
      'VLAN server endpoint',
    ),
    ...(dns === undefined ? {} : { dns }),
    peers: record.peers.map(readVlanJoinPeer),
  };
}

export function parseVlanPeers(value: unknown): readonly VlanPeer[] {
  if (!Array.isArray(value)) {
    throw new NexusRoomClientError('VLAN peer list must be an array');
  }
  return value.map(readVlanPeer);
}

export function parseVlanPeerUpdate(message: WsMessage): VlanPeerUpdate {
  if (message.event !== 'vlan.peer_update') {
    throw new NexusRoomClientError('VLAN peer update event is invalid');
  }
  const payload = readRecord(message.payload, 'VLAN peer update payload');
  const outerRoomId = message.room_id;
  const payloadRoomId = payload.room_id;
  if (
    outerRoomId !== undefined &&
    payloadRoomId !== undefined &&
    outerRoomId !== payloadRoomId
  ) {
    throw new NexusRoomClientError('VLAN peer update room ID is inconsistent');
  }
  const parsedRoomId = readId(
    payloadRoomId ?? outerRoomId,
    'VLAN peer update room id',
  );
  const action = readString(payload.action, 'VLAN peer update action');
  if (action !== 'join' && action !== 'leave') {
    throw new NexusRoomClientError('VLAN peer update action must be join or leave');
  }
  const info = readRecord(payload.peer_info, 'VLAN peer update peer info');
  const nickname = readVlanUpdateString(
    info.nickname,
    'VLAN peer update nickname',
  );
  const publicKey = readVlanUpdateString(
    info.public_key,
    'VLAN peer update public key',
  );
  const assignedIp = readVlanUpdateString(
    info.assigned_ip,
    'VLAN peer update assigned IP',
  );
  if (action === 'join' && (nickname === undefined || publicKey === undefined || assignedIp === undefined)) {
    throw new NexusRoomClientError('VLAN join update peer info is incomplete');
  }
  return {
    roomId: parsedRoomId,
    action,
    peerInfo: {
      userId: readId(info.user_id, 'VLAN peer update user id'),
      ...(nickname === undefined ? {} : { nickname }),
      ...(publicKey === undefined ? {} : { publicKey }),
      ...(assignedIp === undefined ? {} : { assignedIp }),
    },
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

function readIngressUpdateEvent(message: WsMessage): RoomIngressUpdateEvent {
  const record = mergeWsPayload(message);
  return {
    roomId: readId(record.room_id, 'ingress update room id'),
    action: readString(record.action, 'ingress update action'),
  };
}

export class NexusRoomClient {
  readonly serverUrl: string;
  readonly storage: NexusRoomStorage;
  readonly rest: RestTransport;
  readonly socket: RoomSocket;

  private sessionValue: AuthSession | null = null;
  private activeRoomId: number | null = null;
  private rtcIceServersValue: readonly RtcIceServer[] = [];
  private messageSequence = 0;
  private readonly wireguardApi: NexusRoomWireGuardApi | undefined;
  private readonly vlanSession: VlanSessionController;
  private readonly fetchImpl: (
    input: RequestInfo | URL,
    init?: RequestInit,
  ) => Promise<Response>;

  constructor(options: NexusRoomClientOptions) {
    this.serverUrl = normalizeServerUrl(options.serverUrl);
    this.storage = options.storage;
    this.rest = options.restClient ?? new RestClient({ serverUrl: this.serverUrl });
    this.socket = options.wsClient ?? new WsClient();
    this.wireguardApi = options.wireguard;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
    this.rest.setServerUrl(this.serverUrl);
    this.vlanSession = new VlanSessionController(this.createVlanDriver());
    this.socket.on('connected', (message) => {
      this.rtcIceServersValue = parseRtcIceServers(message.payload);
    });
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

  get connectionState(): WsConnectionState {
    return this.socket.state;
  }

  get rtcIceServers(): readonly RtcIceServer[] {
    return this.rtcIceServersValue;
  }

  get vlanSnapshot(): VlanSnapshot {
    return this.vlanSession.snapshot;
  }

  onConnectionStateChange(listener: (state: WsConnectionState) => void): () => void {
    return this.socket.onStateChange(listener);
  }

  onRtcEvent(eventName: VoiceEventName, listener: WsMessageListener): () => void {
    return this.socket.on(eventName, listener);
  }

  onVlanStateChange(listener: (snapshot: VlanSnapshot) => void): () => void {
    return this.vlanSession.onChange(listener);
  }

  sendRtc(eventName: VoiceClientEvent, roomId: number, payload?: unknown): void {
    this.socket.send(eventName, payload, readId(roomId, 'room id'));
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

  async register(
    username: string,
    password: string,
    nickname: string,
  ): Promise<AuthSession> {
    if (username.trim().length === 0 || password.length === 0 || nickname.trim().length === 0) {
      throw new NexusRoomClientError(
        'username, password, and nickname are required',
        'configuration',
      );
    }
    const raw = await this.rest.post<unknown>('/api/v1/auth/register', {
      username: username.trim(),
      password,
      nickname: nickname.trim(),
    });
    const record = readRecord(raw, 'register response');
    const userId = readId(record.user_id, 'user id');
    const session: AuthSession = {
      userId,
      userDisplayId: readString(record.user_display_id, 'user display id'),
      token: readString(record.token, 'access token'),
      scope: { serverUrl: this.serverUrl, accountId: userId },
    };
    await this.storage.saveSession(session.scope, session.token);
    this.rest.setToken(session.token);
    this.sessionValue = session;
    return session;
  }

  restoreSession(accountId: number, accessToken: string, userDisplayId?: string): AuthSession {
    const userId = readId(accountId, 'user id');
    const token = readString(accessToken, 'access token');
    const displayId = userDisplayId === undefined
      ? String(userId)
      : readString(userDisplayId, 'user display id');
    const session: AuthSession = {
      userId,
      userDisplayId: displayId,
      token,
      scope: { serverUrl: this.serverUrl, accountId: userId },
    };
    this.rest.setToken(token);
    this.sessionValue = session;
    return session;
  }

  connect(): void {
    const session = this.requireSession();
    this.socket.connect(this.serverUrl, session.token);
  }

  disconnect(): void {
    void this.vlanSession.leave();
    this.socket.disconnect();
    this.activeRoomId = null;
    this.rtcIceServersValue = [];
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
      : readList(record.ingresses, 'room ingresses').map((value) => readIngress(value, false));
    return { ...summary, members, ingresses };
  }

  async listRoomIngresses(roomId: number): Promise<readonly RoomIngress[]> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    const raw = await this.rest.get<unknown>(`/api/v1/rooms/${id}/ingresses`);
    return readList(raw, 'room ingress list').map((value) => readIngress(value, true));
  }

  async createRoomIngress(roomId: number, label: string): Promise<RoomIngress> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    const trimmedLabel = label.trim();
    if (trimmedLabel.length === 0 || trimmedLabel.length > 64) {
      throw new NexusRoomClientError('ingress label must be between 1 and 64 characters', 'configuration');
    }
    const raw = await this.rest.post<unknown>(
      `/api/v1/rooms/${id}/ingresses`,
      { label: trimmedLabel },
    );
    return readIngress(raw, true);
  }

  async deleteRoomIngress(roomId: number, ingressId: number): Promise<void> {
    this.requireSession();
    const room = readId(roomId, 'room id');
    const ingress = readId(ingressId, 'ingress id');
    await this.rest.delete(`/api/v1/rooms/${room}/ingresses/${ingress}`);
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
    await this.vlanSession.leave(id);
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
      void this.vlanSession.leave(previous);
      this.leaveSocketRoom(previous);
    }
    this.activeRoomId = id;
    if (this.socket.state === 'connected') {
      this.socket.send('room.join', {}, id);
    }
  }

  async joinVlan(roomId: number): Promise<VlanSnapshot> {
    this.requireSession();
    return this.vlanSession.join(readId(roomId, 'room id'));
  }

  async leaveVlan(roomId?: number): Promise<void> {
    await this.vlanSession.leave(
      roomId === undefined ? undefined : readId(roomId, 'room id'),
    );
  }

  async listVlanPeers(roomId: number): Promise<readonly VlanPeer[]> {
    this.requireSession();
    const id = readId(roomId, 'room id');
    const raw = await this.rest.get<unknown>(`/api/v1/rooms/${id}/vlan/peers`);
    return parseVlanPeers(raw);
  }

  async refreshVlanPeers(roomId: number): Promise<readonly VlanPeer[]> {
    this.requireSession();
    return this.vlanSession.refresh(readId(roomId, 'room id'));
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

  onIngressUpdate(listener: (event: RoomIngressUpdateEvent) => void): () => void {
    return this.socket.on('room.ingress_update', (message) => {
      try {
        const event = readIngressUpdateEvent(message);
        if (this.activeRoomId !== event.roomId) return;
        listener(event);
      } catch {
        // Ignore malformed external events; the socket remains usable.
      }
    });
  }

  onVlanPeerUpdate(listener: (event: VlanPeerUpdate) => void): () => void {
    return this.socket.on('vlan.peer_update', (message) => {
      try {
        const event = parseVlanPeerUpdate(message);
        const snapshot = this.vlanSession.snapshot;
        if (
          snapshot.state !== 'connected' ||
          snapshot.roomId !== event.roomId
        ) {
          return;
        }
        listener(event);
      } catch {
        // Ignore malformed external events; the tunnel remains usable.
      }
    });
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

  private getWireGuardApi(): NexusRoomWireGuardApi | null {
    const runtimeApi = typeof window !== 'undefined'
      ? window.nexusroom?.wireguard
      : undefined;
    const api = this.wireguardApi ?? runtimeApi;
    if (
      api === undefined ||
      typeof api.getAvailability !== 'function' ||
      typeof api.generateKeyPair !== 'function' ||
      typeof api.startTunnel !== 'function' ||
      typeof api.stopTunnel !== 'function'
    ) {
      return null;
    }
    return api;
  }

  private createVlanDriver(): VlanSessionDriver {
    return {
      getAvailability: async () => {
        const api = this.getWireGuardApi();
        if (api === null) return { available: false, reason: 'missing' };
        return api.getAvailability();
      },
      generateKeyPair: async () => {
        const api = this.getWireGuardApi();
        if (api === null) throw new NexusRoomClientError('WireGuard Helper 不可用');
        return api.generateKeyPair();
      },
      joinServer: (roomId, publicKey) => this.joinVlanServer(roomId, publicKey),
      leaveServer: (roomId) => this.leaveVlanServer(roomId),
      listPeers: (roomId) => this.listVlanPeers(roomId),
      startTunnel: async (config) => {
        const api = this.getWireGuardApi();
        if (api === null) throw new NexusRoomClientError('WireGuard Helper 不可用');
        return api.startTunnel(config);
      },
      stopTunnel: async () => {
        const api = this.getWireGuardApi();
        if (api === null) return undefined;
        return api.stopTunnel();
      },
      toUserError: (error, phase) => this.toVlanUserError(error, phase),
      unavailableMessage: (reason) => reason === 'unsupported'
        ? '当前系统不支持 WireGuard，VLAN 不可用'
        : 'WireGuard Helper 未找到，VLAN 不可用',
    };
  }

  private async joinVlanServer(
    roomId: number,
    publicKey: string,
  ): Promise<VlanJoinResponse> {
    let raw: unknown;
    try {
      raw = await this.rest.post<unknown>(
        `/api/v1/rooms/${roomId}/vlan/join`,
        { public_key: publicKey },
      );
    } catch (error) {
      throw this.toVlanUserError(error, 'join');
    }
    try {
      return parseVlanJoinResponse(raw);
    } catch (error) {
      try {
        await this.rest.delete(`/api/v1/rooms/${roomId}/vlan/leave`);
      } catch {
        // A malformed join response still gets a best-effort server rollback.
      }
      throw error;
    }
  }

  private async leaveVlanServer(roomId: number): Promise<void> {
    if (this.sessionValue === null) return;
    try {
      await this.rest.delete(`/api/v1/rooms/${roomId}/vlan/leave`);
    } catch (error) {
      throw this.toVlanUserError(error, 'leave');
    }
  }

  private toVlanUserError(error: unknown, phase: VlanErrorPhase): NexusRoomClientError {
    if (error instanceof NexusRoomClientError) return error;
    const record = isRecord(error) ? error : undefined;
    const code = typeof record?.code === 'string' ? record.code : undefined;
    if (code === 'helper-missing') {
      return new NexusRoomClientError('WireGuard Helper 未找到，VLAN 不可用');
    }
    if (code === 'spawn-failed') {
      return new NexusRoomClientError('WireGuard Helper 启动失败，请检查安装和权限');
    }
    if (code === 'connection' || code === 'timeout') {
      return new NexusRoomClientError('WireGuard 隧道连接超时，请检查权限和网络');
    }
    if (code === 'cancelled') {
      return new NexusRoomClientError('WireGuard 隧道操作已取消');
    }
    const status = typeof record?.status === 'number' ? record.status : undefined;
    if (status === 401 || status === 403) {
      return new NexusRoomClientError('VLAN 请求被拒绝，请重新登录或确认房间权限');
    }
    if (phase === 'leave') {
      return new NexusRoomClientError('VLAN 已关闭，但服务端注销失败，请稍后重试');
    }
    if (phase === 'refresh') {
      return new NexusRoomClientError('VLAN Peer 刷新失败，请稍后重试');
    }
    if (phase === 'availability') {
      return new NexusRoomClientError('无法检查 WireGuard Helper，请稍后重试');
    }
    if (phase === 'key generation') {
      return new NexusRoomClientError('WireGuard 密钥生成失败，请检查 Helper 权限');
    }
    if (phase === 'start') {
      return new NexusRoomClientError('WireGuard 隧道启动失败，请检查权限或系统网络');
    }
    if (phase === 'configuration') {
      return new NexusRoomClientError('VLAN 配置无效，无法启动隧道');
    }
    return new NexusRoomClientError('VLAN 加入失败，请检查服务器连接和房间权限');
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

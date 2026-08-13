export type RuntimePlatform = 'win32' | 'darwin' | 'linux' | 'other' | 'browser';

export interface RuntimeInfo {
  readonly platform: RuntimePlatform;
  readonly electron: string;
  readonly chrome: string;
}

export const nexusRoomIpcChannels = {
  getSetting: 'nexusroom.storage.get-setting',
  setSetting: 'nexusroom.storage.set-setting',
  getSession: 'nexusroom.storage.get-session',
  saveSession: 'nexusroom.storage.save-session',
  removeSession: 'nexusroom.storage.remove-session',
  getMessages: 'nexusroom.storage.get-messages',
  saveMessages: 'nexusroom.storage.save-messages',
  clearMessages: 'nexusroom.storage.clear-messages',
  clearData: 'nexusroom.storage.clear-data',
  setAuthenticatedWindowState: 'nexusroom.window.set-authenticated-state',
  wireguardAvailability: 'nexusroom.wireguard.availability',
  wireguardGenerateKeyPair: 'nexusroom.wireguard.generate-key-pair',
  wireguardStartTunnel: 'nexusroom.wireguard.start-tunnel',
  wireguardStopTunnel: 'nexusroom.wireguard.stop-tunnel',
  wireguardStatus: 'nexusroom.wireguard.status',
} as const;

export type NexusRoomIpcChannel =
  | typeof nexusRoomIpcChannels.getSetting
  | typeof nexusRoomIpcChannels.setSetting
  | typeof nexusRoomIpcChannels.getSession
  | typeof nexusRoomIpcChannels.saveSession
  | typeof nexusRoomIpcChannels.removeSession
  | typeof nexusRoomIpcChannels.getMessages
  | typeof nexusRoomIpcChannels.saveMessages
  | typeof nexusRoomIpcChannels.clearMessages
  | typeof nexusRoomIpcChannels.clearData;

export type NexusRoomWindowStateIpcChannel =
  typeof nexusRoomIpcChannels.setAuthenticatedWindowState;

export type NexusRoomWireGuardIpcChannel =
  | typeof nexusRoomIpcChannels.wireguardAvailability
  | typeof nexusRoomIpcChannels.wireguardGenerateKeyPair
  | typeof nexusRoomIpcChannels.wireguardStartTunnel
  | typeof nexusRoomIpcChannels.wireguardStopTunnel
  | typeof nexusRoomIpcChannels.wireguardStatus;

export interface AccountScope {
  readonly serverUrl: string;
  readonly accountId: number;
}

export interface AccountSession {
  readonly serverUrl: string;
  readonly accountId: number;
  readonly accessToken: string;
  readonly updatedAt: string;
}

export interface MessageCacheEntry {
  readonly id: number;
  readonly roomId: number;
  readonly senderId: number;
  readonly type: string;
  readonly content: string;
  readonly createdAt: string;
  readonly senderNickname?: string | null;
  readonly senderAvatarUrl?: string | null;
  readonly meta?: unknown;
}

export type CachedMessage = MessageCacheEntry;

export interface WireGuardPeerConfig {
  readonly public_key: string;
  readonly endpoint?: string;
  readonly allowed_ips: string;
  readonly persistent_keepalive?: number;
}

export interface WireGuardTunnelConfig {
  readonly interface_name?: string;
  readonly private_key: string;
  readonly address: string;
  readonly dns?: string;
  readonly listen_port?: number;
  readonly peers: readonly WireGuardPeerConfig[];
}

export interface WireGuardKeyPair {
  readonly public_key: string;
  readonly private_key: string;
}

export interface WireGuardAvailability {
  readonly available: boolean;
  readonly reason?: 'missing' | 'unsupported';
}

export type WireGuardTunnelState =
  | 'unavailable'
  | 'idle'
  | 'starting'
  | 'running'
  | 'stopping';

export interface WireGuardStatus {
  readonly available: boolean;
  readonly state: WireGuardTunnelState;
  readonly address?: string;
}

export interface NexusRoomStorageApi {
  readonly getSetting: (key: string) => Promise<string | null>;
  readonly setSetting: (key: string, value: string) => Promise<void>;
  readonly getSession: (scope: AccountScope) => Promise<AccountSession | null>;
  readonly saveSession: (
    scope: AccountScope,
    accessToken: string,
  ) => Promise<void>;
  readonly removeSession: (scope: AccountScope) => Promise<void>;
  readonly getMessages: (
    scope: AccountScope,
    roomId?: number,
  ) => Promise<readonly CachedMessage[]>;
  readonly saveMessages: (
    scope: AccountScope,
    messages: readonly MessageCacheEntry[],
  ) => Promise<void>;
  readonly clearMessages: (scope: AccountScope, roomId?: number) => Promise<void>;
  readonly clearData: () => Promise<void>;
}

export interface NexusRoomWindowState {
  readonly setAuthenticated: (authenticated: boolean) => Promise<void>;
}

export interface NexusRoomWireGuardApi {
  readonly getAvailability: () => Promise<WireGuardAvailability>;
  readonly generateKeyPair: () => Promise<WireGuardKeyPair>;
  readonly startTunnel: (config: WireGuardTunnelConfig) => Promise<WireGuardStatus>;
  readonly stopTunnel: () => Promise<WireGuardStatus>;
  readonly getStatus: () => Promise<WireGuardStatus>;
}

export interface NexusRoomApi {
  readonly getRuntimeInfo: () => RuntimeInfo;
  readonly storage: NexusRoomStorageApi;
  readonly windowState: NexusRoomWindowState;
  readonly wireguard: NexusRoomWireGuardApi;
}

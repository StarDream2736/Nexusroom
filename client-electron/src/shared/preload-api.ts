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
} as const;

export type NexusRoomIpcChannel =
  (typeof nexusRoomIpcChannels)[keyof typeof nexusRoomIpcChannels];

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

export interface NexusRoomApi {
  readonly getRuntimeInfo: () => RuntimeInfo;
  readonly storage: NexusRoomStorageApi;
}

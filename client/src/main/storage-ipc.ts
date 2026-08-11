import {
  nexusRoomIpcChannels,
  type AccountScope,
  type MessageCacheEntry,
  type NexusRoomIpcChannel,
} from '../shared/preload-api';
import {
  ClientDatabase,
  ClientStorageError,
  normalizeAccountScope,
} from './client-database';

export interface IpcInvokeEvent {
  readonly sender: {
    readonly id: number;
  };
}

export type StorageIpcHandler = (
  event: IpcInvokeEvent,
  ...args: unknown[]
) => Promise<unknown>;

export interface IpcMainLike {
  handle(channel: string, listener: StorageIpcHandler): void;
  removeHandler(channel: string): void;
}

export interface StorageIpcOptions {
  readonly database: ClientDatabase;
  readonly getMainWindowId: () => number | null;
}

const storageIpcChannels: readonly NexusRoomIpcChannel[] = [
  nexusRoomIpcChannels.getSetting,
  nexusRoomIpcChannels.setSetting,
  nexusRoomIpcChannels.getSession,
  nexusRoomIpcChannels.saveSession,
  nexusRoomIpcChannels.removeSession,
  nexusRoomIpcChannels.getMessages,
  nexusRoomIpcChannels.saveMessages,
  nexusRoomIpcChannels.clearMessages,
  nexusRoomIpcChannels.clearData,
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function requireString(value: unknown, message: string): string {
  if (typeof value !== 'string') {
    throw new ClientStorageError(message);
  }
  return value;
}

function requireScope(value: unknown): AccountScope {
  if (
    !isRecord(value) ||
    typeof value.serverUrl !== 'string' ||
    typeof value.accountId !== 'number'
  ) {
    throw new ClientStorageError('账号 scope 无效');
  }
  try {
    return normalizeAccountScope({
      serverUrl: value.serverUrl,
      accountId: value.accountId,
    });
  } catch {
    throw new ClientStorageError('账号 scope 无效');
  }
}

function requireRoomId(value: unknown): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw new ClientStorageError('房间 ID 无效');
  }
  return value as number;
}

function requireMessages(value: unknown): readonly MessageCacheEntry[] {
  if (!Array.isArray(value)) {
    throw new ClientStorageError('消息缓存无效');
  }
  return value as readonly MessageCacheEntry[];
}

function assertMainWindow(
  event: IpcInvokeEvent,
  getMainWindowId: () => number | null,
): void {
  if (event.sender.id !== getMainWindowId()) {
    throw new ClientStorageError('禁止从非主窗口调用本地存储');
  }
}

export function createStorageIpcHandlers(
  options: StorageIpcOptions,
): Readonly<Record<NexusRoomIpcChannel, StorageIpcHandler>> {
  const assertSource = (event: IpcInvokeEvent): void => {
    assertMainWindow(event, options.getMainWindowId);
  };

  return {
    [nexusRoomIpcChannels.getSetting]: async (event, key) => {
      assertSource(event);
      return options.database.getSetting(requireString(key, '设置键无效'));
    },
    [nexusRoomIpcChannels.setSetting]: async (event, key, value) => {
      assertSource(event);
      options.database.setSetting(
        requireString(key, '设置键无效'),
        requireString(value, '设置值无效'),
      );
    },
    [nexusRoomIpcChannels.getSession]: async (event, scope) => {
      assertSource(event);
      return options.database.getSession(requireScope(scope));
    },
    [nexusRoomIpcChannels.saveSession]: async (event, scope, accessToken) => {
      assertSource(event);
      options.database.saveSession(
        requireScope(scope),
        requireString(accessToken, '访问令牌无效'),
      );
    },
    [nexusRoomIpcChannels.removeSession]: async (event, scope) => {
      assertSource(event);
      options.database.removeSession(requireScope(scope));
    },
    [nexusRoomIpcChannels.getMessages]: async (event, scope, roomId) => {
      assertSource(event);
      return options.database.listMessages(
        requireScope(scope),
        requireRoomId(roomId),
      );
    },
    [nexusRoomIpcChannels.saveMessages]: async (event, scope, messages) => {
      assertSource(event);
      options.database.saveMessages(requireScope(scope), requireMessages(messages));
    },
    [nexusRoomIpcChannels.clearMessages]: async (event, scope, roomId) => {
      assertSource(event);
      options.database.clearMessages(requireScope(scope), requireRoomId(roomId));
    },
    [nexusRoomIpcChannels.clearData]: async (event) => {
      assertSource(event);
      options.database.clearData();
    },
  };
}

export function registerStorageIpc(
  ipcMain: IpcMainLike,
  options: StorageIpcOptions,
): () => void {
  const handlers = createStorageIpcHandlers(options);
  for (const channel of storageIpcChannels) {
    ipcMain.handle(channel, handlers[channel]);
  }
  return () => {
    for (const channel of storageIpcChannels) {
      ipcMain.removeHandler(channel);
    }
  };
}

import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, it } from 'vitest';
import {
  ClientDatabase,
  ClientStorageError,
} from '../src/main/client-database';
import {
  registerStorageIpc,
  type IpcMainLike,
  type StorageIpcHandler,
} from '../src/main/storage-ipc';
import {
  nexusRoomIpcChannels,
  type AccountScope,
} from '../src/shared/preload-api';

const databases: ClientDatabase[] = [];
const roots: string[] = [];

afterEach(() => {
  for (const database of databases.splice(0)) {
    database.close();
  }
  for (const root of roots.splice(0)) {
    rmSync(root, { recursive: true, force: true });
  }
});

function createDatabase(): ClientDatabase {
  const root = mkdtempSync(join(tmpdir(), 'nexusroom-electron-ipc-'));
  roots.push(root);
  const database = new ClientDatabase(join(root, 'nexusroom.sqlite'));
  databases.push(database);
  return database;
}

describe('storage IPC', () => {
  it('rejects calls whose sender is not the current main window', async () => {
    const database = createDatabase();
    const handlers = new Map<string, StorageIpcHandler>();
    const ipcMain: IpcMainLike = {
      handle(channel, handler) {
        handlers.set(channel, handler);
      },
      removeHandler(channel) {
        handlers.delete(channel);
      },
    };
    let mainWindowId = 42;
    const dispose = registerStorageIpc(ipcMain, {
      database,
      getMainWindowId: () => mainWindowId,
    });
    const scope: AccountScope = {
      serverUrl: 'https://example.test',
      accountId: 11,
    };
    const saveSession = handlers.get(nexusRoomIpcChannels.saveSession);
    if (saveSession === undefined) {
      throw new Error('save-session handler was not registered');
    }

    await expect(
      saveSession({ sender: { id: 7 } }, scope, 'rejected-token'),
    ).rejects.toBeInstanceOf(ClientStorageError);
    expect(database.getSession(scope)).toBeNull();

    await saveSession({ sender: { id: mainWindowId } }, scope, 'accepted-token');
    expect(database.getSession(scope)?.accessToken).toBe('accepted-token');

    mainWindowId = 43;
    await expect(
      saveSession({ sender: { id: 42 } }, scope, 'stale-window-token'),
    ).rejects.toBeInstanceOf(ClientStorageError);
    expect(database.getSession(scope)?.accessToken).toBe('accepted-token');

    dispose();
    expect(handlers).toHaveLength(0);
  });
});

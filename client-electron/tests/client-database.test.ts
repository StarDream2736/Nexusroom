import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { DatabaseSync } from 'node:sqlite';
import { afterEach, describe, expect, it } from 'vitest';
import {
  ClientDatabase,
  ClientStorageError,
} from '../src/main/client-database';
import type { AccountScope, MessageCacheEntry } from '../src/shared/preload-api';

const message: MessageCacheEntry = {
  id: 1,
  roomId: 7,
  senderId: 99,
  type: 'text',
  content: 'private message',
  createdAt: '2026-08-11T00:00:00.000Z',
  senderNickname: 'Alice',
  meta: { clientMessageId: 'local-1' },
};

const roots: string[] = [];
const databases: ClientDatabase[] = [];

afterEach(() => {
  for (const database of databases.splice(0)) {
    database.close();
  }
  for (const root of roots.splice(0)) {
    rmSync(root, { recursive: true, force: true });
  }
});

function createDatabase(): ClientDatabase {
  const root = mkdtempSync(join(tmpdir(), 'nexusroom-electron-'));
  roots.push(root);
  const database = new ClientDatabase(join(root, 'data', 'nexusroom.sqlite'));
  databases.push(database);
  return database;
}

describe('ClientDatabase', () => {
  it('normalizes server URLs and isolates two accounts on one server', () => {
    const database = createDatabase();
    const firstAccount: AccountScope = {
      serverUrl: ' HTTPS://Example.test:443/ ',
      accountId: 11,
    };
    const secondAccount: AccountScope = {
      serverUrl: 'https://example.test',
      accountId: 12,
    };
    const otherServer: AccountScope = {
      serverUrl: 'https://other.example.test',
      accountId: 11,
    };

    database.saveMessages(firstAccount, [message]);
    database.saveMessages(secondAccount, [{ ...message, content: 'other account' }]);
    database.saveMessages(otherServer, [{ ...message, content: 'other server' }]);

    expect(database.listMessages(firstAccount, 7)).toEqual([
      { ...message },
    ]);
    expect(database.listMessages(secondAccount, 7)[0]?.content).toBe(
      'other account',
    );
    expect(database.listMessages(otherServer, 7)[0]?.content).toBe('other server');
    expect(database.getLatestMessageId(firstAccount, 7)).toBe(1);
    expect(database.getLatestMessageId(firstAccount, 8)).toBeNull();

    database.saveSession(firstAccount, 'first-token');
    expect(database.getSession(firstAccount)).toMatchObject({
      serverUrl: 'https://example.test',
      accountId: 11,
      accessToken: 'first-token',
    });
    expect(database.getSession(secondAccount)).toBeNull();
  });

  it('keeps the schema and connection usable after transactional clear', () => {
    const database = createDatabase();
    const scope: AccountScope = {
      serverUrl: 'https://example.test',
      accountId: 11,
    };

    database.setSetting('theme', 'dark');
    database.saveSession(scope, 'session-token');
    database.saveMessages(scope, [message]);
    database.clearData();

    expect(database.isOpen).toBe(true);
    expect(database.getSetting('theme')).toBeNull();
    expect(database.getSession(scope)).toBeNull();
    expect(database.listMessages(scope)).toEqual([]);
    expect(existsSync(database.filePath)).toBe(true);

    const verifier = new DatabaseSync(database.filePath);
    const tables = verifier
      .prepare(
        `SELECT name FROM sqlite_schema
         WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
         ORDER BY name`,
      )
      .all() as Array<{ name: string }>;
    verifier.close();
    expect(tables.map((row) => row.name)).toEqual([
      'account_sessions',
      'messages',
      'settings',
    ]);

    database.setSetting('server_url', 'http://localhost:8080');
    database.saveSession(scope, 'new-session-token');
    database.saveMessages(scope, [message]);
    expect(database.getSetting('server_url')).toBe('http://localhost:8080');
    expect(database.getSession(scope)?.accessToken).toBe('new-session-token');
    expect(database.listMessages(scope, 7)).toHaveLength(1);
  });

  it('rejects an unsupported existing schema version without changing it', () => {
    const root = mkdtempSync(join(tmpdir(), 'nexusroom-electron-version-'));
    roots.push(root);
    const filePath = join(root, 'nexusroom.sqlite');
    const existing = new DatabaseSync(filePath);
    existing.exec('PRAGMA user_version = 2');
    existing.close();

    expect(() => new ClientDatabase(filePath)).toThrow(ClientStorageError);

    const verifier = new DatabaseSync(filePath);
    const row = verifier
      .prepare('PRAGMA user_version')
      .get() as { user_version: number };
    verifier.close();
    expect(row.user_version).toBe(2);
  });

  it('requires positive account and message identifiers', () => {
    const database = createDatabase();
    const invalidScope: AccountScope = {
      serverUrl: 'https://example.test',
      accountId: 0,
    };

    expect(() => database.saveSession(invalidScope, 'token')).toThrow(
      ClientStorageError,
    );
    expect(() =>
      database.saveMessages(
        { serverUrl: 'https://example.test', accountId: 11 },
        [{ ...message, id: 0 }],
      ),
    ).toThrow(ClientStorageError);
    expect(() =>
      database.saveMessages(
        { serverUrl: 'https://example.test', accountId: 11 },
        [{ ...message, roomId: 0 }],
      ),
    ).toThrow(ClientStorageError);
    expect(() =>
      database.saveMessages(
        { serverUrl: 'https://example.test', accountId: 11 },
        [{ ...message, senderId: 0 }],
      ),
    ).toThrow(ClientStorageError);
  });
});

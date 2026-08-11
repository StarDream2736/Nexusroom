import { existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { normalizeServerUrl } from './server-url';
import type {
  AccountScope,
  AccountSession,
  CachedMessage,
  MessageCacheEntry,
} from '../shared/preload-api';

export class ClientStorageError extends Error {
  constructor(message = '本地数据操作失败') {
    super(message);
    this.name = 'ClientStorageError';
  }
}

interface ScopeRow {
  readonly server_url: string;
  readonly account_id: number;
}

interface SessionRow extends ScopeRow {
  readonly access_token: string;
  readonly updated_at: string;
}

interface MessageRow extends ScopeRow {
  readonly id: number;
  readonly room_id: number;
  readonly sender_id: number;
  readonly type: string;
  readonly content: string;
  readonly created_at: string;
  readonly sender_nickname: string | null;
  readonly sender_avatar_url: string | null;
  readonly meta_json: string | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function assertAccountId(accountId: unknown): asserts accountId is number {
  if (!Number.isSafeInteger(accountId) || (accountId as number) < 1) {
    throw new ClientStorageError('账号标识无效');
  }
}

function assertMessageId(value: unknown, fieldName: string): asserts value is number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw new ClientStorageError(`${fieldName} 无效`);
  }
}

function assertString(value: unknown, message: string): asserts value is string {
  if (typeof value !== 'string') {
    throw new ClientStorageError(message);
  }
}

function parseMeta(value: string | null): unknown {
  if (value === null) {
    return undefined;
  }
  return JSON.parse(value) as unknown;
}

function serializeMeta(value: unknown): string | null {
  if (value === undefined) {
    return null;
  }
  const serialized = JSON.stringify(value);
  if (serialized === undefined) {
    throw new ClientStorageError('消息元数据无效');
  }
  return serialized;
}

export function normalizeAccountScope(scope: AccountScope): AccountScope {
  if (!isRecord(scope)) {
    throw new ClientStorageError('账号 scope 无效');
  }
  assertString(scope.serverUrl, '服务器地址无效');
  assertAccountId(scope.accountId);
  return {
    serverUrl: normalizeServerUrl(scope.serverUrl),
    accountId: scope.accountId,
  };
}

function normalizeMessage(message: MessageCacheEntry): MessageCacheEntry {
  if (!isRecord(message)) {
    throw new ClientStorageError('消息缓存无效');
  }
  assertMessageId(message.id, '消息 ID');
  assertMessageId(message.roomId, '房间 ID');
  assertMessageId(message.senderId, '发送者 ID');
  assertString(message.type, '消息类型无效');
  assertString(message.content, '消息内容无效');
  assertString(message.createdAt, '消息时间无效');
  if (
    message.senderNickname !== undefined &&
    message.senderNickname !== null
  ) {
    assertString(message.senderNickname, '发送者昵称无效');
  }
  if (
    message.senderAvatarUrl !== undefined &&
    message.senderAvatarUrl !== null
  ) {
    assertString(message.senderAvatarUrl, '发送者头像无效');
  }
  serializeMeta(message.meta);
  return message;
}

export class ClientDatabase {
  private readonly database: DatabaseSync;
  private closed = false;

  constructor(readonly filePath: string) {
    const existed = existsSync(filePath);
    let database: DatabaseSync | undefined;
    try {
      mkdirSync(dirname(filePath), { recursive: true });
      database = new DatabaseSync(filePath);
      const versionRow = database
        .prepare('PRAGMA user_version')
        .get() as { user_version?: number } | undefined;
      const userVersion = versionRow?.user_version ?? 0;
      if (existed && userVersion !== 0 && userVersion !== 1) {
        throw new ClientStorageError();
      }
      database.exec(`
        PRAGMA journal_mode = WAL;
        PRAGMA busy_timeout = 5000;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT NOT NULL PRIMARY KEY,
          value TEXT NULL
        );
        CREATE TABLE IF NOT EXISTS account_sessions (
          server_url TEXT NOT NULL,
          account_id INTEGER NOT NULL CHECK (account_id > 0),
          access_token TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (server_url, account_id)
        );
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER NOT NULL CHECK (id > 0),
          server_url TEXT NOT NULL,
          account_id INTEGER NOT NULL CHECK (account_id > 0),
          room_id INTEGER NOT NULL CHECK (room_id > 0),
          sender_id INTEGER NOT NULL CHECK (sender_id > 0),
          type TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          sender_nickname TEXT NULL,
          sender_avatar_url TEXT NULL,
          meta_json TEXT NULL,
          PRIMARY KEY (server_url, account_id, id)
        );
        CREATE INDEX IF NOT EXISTS messages_scope_room_id
          ON messages (server_url, account_id, room_id, id);
        PRAGMA user_version = 1;
      `);
      this.database = database;
    } catch {
      try {
        database?.close();
      } catch {
        // Do not replace the safe storage error with a close error.
      }
      throw new ClientStorageError();
    }
  }

  get isOpen(): boolean {
    return !this.closed;
  }

  getSetting(key: string): string | null {
    return this.execute(() => {
      assertString(key, '设置键无效');
      const row = this.database
        .prepare('SELECT value FROM settings WHERE key = ?')
        .get(key) as { value?: string | null } | undefined;
      return row?.value ?? null;
    });
  }

  setSetting(key: string, value: string): void {
    this.execute(() => {
      assertString(key, '设置键无效');
      assertString(value, '设置值无效');
      this.database
        .prepare(
          `INSERT INTO settings (key, value) VALUES (?, ?)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
        )
        .run(key, value);
    });
  }

  removeSetting(key: string): void {
    this.execute(() => {
      assertString(key, '设置键无效');
      this.database.prepare('DELETE FROM settings WHERE key = ?').run(key);
    });
  }

  getSession(scope: AccountScope): AccountSession | null {
    return this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      const row = this.database
        .prepare(
          `SELECT server_url, account_id, access_token, updated_at
           FROM account_sessions
           WHERE server_url = ? AND account_id = ?`,
        )
        .get(normalizedScope.serverUrl, normalizedScope.accountId) as
        | SessionRow
        | undefined;
      if (row === undefined) {
        return null;
      }
      return {
        serverUrl: row.server_url,
        accountId: row.account_id,
        accessToken: row.access_token,
        updatedAt: row.updated_at,
      };
    });
  }

  saveSession(scope: AccountScope, accessToken: string): void {
    this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      assertString(accessToken, '访问令牌无效');
      if (accessToken.length === 0) {
        throw new ClientStorageError('访问令牌无效');
      }
      this.database
        .prepare(
          `INSERT INTO account_sessions
             (server_url, account_id, access_token, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(server_url, account_id) DO UPDATE SET
             access_token = excluded.access_token,
             updated_at = excluded.updated_at`,
        )
        .run(
          normalizedScope.serverUrl,
          normalizedScope.accountId,
          accessToken,
          new Date().toISOString(),
        );
    });
  }

  removeSession(scope: AccountScope): void {
    this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      this.database
        .prepare(
          'DELETE FROM account_sessions WHERE server_url = ? AND account_id = ?',
        )
        .run(normalizedScope.serverUrl, normalizedScope.accountId);
    });
  }

  saveMessages(scope: AccountScope, messages: readonly MessageCacheEntry[]): void {
    this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      if (messages.length === 0) {
        return;
      }
      this.withTransaction(() => {
        const statement = this.database.prepare(
          `INSERT INTO messages (
             id, server_url, account_id, room_id, sender_id, type, content,
             created_at, sender_nickname, sender_avatar_url, meta_json
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(server_url, account_id, id) DO UPDATE SET
             room_id = excluded.room_id,
             sender_id = excluded.sender_id,
             type = excluded.type,
             content = excluded.content,
             created_at = excluded.created_at,
             sender_nickname = excluded.sender_nickname,
             sender_avatar_url = excluded.sender_avatar_url,
             meta_json = excluded.meta_json`,
        );
        for (const input of messages) {
          const message = normalizeMessage(input);
          statement.run(
            message.id,
            normalizedScope.serverUrl,
            normalizedScope.accountId,
            message.roomId,
            message.senderId,
            message.type,
            message.content,
            message.createdAt,
            message.senderNickname ?? null,
            message.senderAvatarUrl ?? null,
            serializeMeta(message.meta),
          );
        }
      });
    });
  }

  listMessages(scope: AccountScope, roomId?: number): CachedMessage[] {
    return this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      if (roomId !== undefined) {
        assertMessageId(roomId, '房间 ID');
      }
      const rows = roomId === undefined
        ? this.database
            .prepare(
              `SELECT id, server_url, account_id, room_id, sender_id, type,
                      content, created_at, sender_nickname, sender_avatar_url,
                      meta_json
               FROM messages
               WHERE server_url = ? AND account_id = ?
               ORDER BY id`,
            )
            .all(normalizedScope.serverUrl, normalizedScope.accountId) as MessageRow[]
        : this.database
            .prepare(
              `SELECT id, server_url, account_id, room_id, sender_id, type,
                      content, created_at, sender_nickname, sender_avatar_url,
                      meta_json
               FROM messages
               WHERE server_url = ? AND account_id = ? AND room_id = ?
               ORDER BY id`,
            )
            .all(
              normalizedScope.serverUrl,
              normalizedScope.accountId,
              roomId,
            ) as MessageRow[];

      return rows.map((row) => ({
        id: row.id,
        roomId: row.room_id,
        senderId: row.sender_id,
        type: row.type,
        content: row.content,
        createdAt: row.created_at,
        senderNickname: row.sender_nickname ?? undefined,
        senderAvatarUrl: row.sender_avatar_url ?? undefined,
        meta: parseMeta(row.meta_json),
      }));
    });
  }

  getLatestMessageId(scope: AccountScope, roomId: number): number | null {
    return this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      assertMessageId(roomId, '房间 ID');
      const row = this.database
        .prepare(
          `SELECT MAX(id) AS id
           FROM messages
           WHERE server_url = ? AND account_id = ? AND room_id = ?`,
        )
        .get(normalizedScope.serverUrl, normalizedScope.accountId, roomId) as
        | { id?: number | null }
        | undefined;
      return row?.id ?? null;
    });
  }

  clearMessages(scope: AccountScope, roomId?: number): void {
    this.execute(() => {
      const normalizedScope = normalizeAccountScope(scope);
      if (roomId !== undefined) {
        assertMessageId(roomId, '房间 ID');
        this.database
          .prepare(
            `DELETE FROM messages
             WHERE server_url = ? AND account_id = ? AND room_id = ?`,
          )
          .run(normalizedScope.serverUrl, normalizedScope.accountId, roomId);
        return;
      }
      this.database
        .prepare('DELETE FROM messages WHERE server_url = ? AND account_id = ?')
        .run(normalizedScope.serverUrl, normalizedScope.accountId);
    });
  }

  clearData(): void {
    this.execute(() => {
      this.withTransaction(() => {
        this.database.exec(
          'DELETE FROM settings; DELETE FROM account_sessions; DELETE FROM messages;',
        );
      });
      this.database.exec('VACUUM; PRAGMA wal_checkpoint(TRUNCATE);');
    });
  }

  close(): void {
    if (this.closed) {
      return;
    }
    try {
      this.database.close();
      this.closed = true;
    } catch {
      throw new ClientStorageError();
    }
  }

  private execute<T>(operation: () => T): T {
    if (this.closed) {
      throw new ClientStorageError('本地数据库已关闭');
    }
    try {
      return operation();
    } catch (error) {
      if (error instanceof ClientStorageError) {
        throw error;
      }
      throw new ClientStorageError();
    }
  }

  private withTransaction<T>(operation: () => T): T {
    this.database.exec('BEGIN IMMEDIATE');
    try {
      const result = operation();
      this.database.exec('COMMIT');
      return result;
    } catch {
      try {
        this.database.exec('ROLLBACK');
      } catch {
        // Preserve the original storage failure without exposing data.
      }
      throw new ClientStorageError();
    }
  }
}

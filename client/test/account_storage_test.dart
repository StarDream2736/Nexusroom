import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexusroom/core/db/app_database.dart';
import 'package:nexusroom/core/storage/app_data_paths.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('portable data directory is next to the executable', () {
    final executable = path.join(
      Directory.systemTemp.path,
      'portable',
      'NexusRoom',
      'Nexusroom.exe',
    );
    final directory = AppDataPaths.dataDirectoryForExecutable(executable);

    expect(
      directory.path,
      path.join(Directory.systemTemp.path, 'portable', 'NexusRoom', 'data'),
    );
  });

  test('message cache is isolated by local account', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.messagesDao.upsertMessages([
      MessagesCompanion.insert(
        id: 1,
        serverUrl: const Value('https://example.test'),
        accountUserId: const Value(11),
        roomId: 7,
        senderId: 99,
        type: 'text',
        content: 'private message',
        createdAt: DateTime.utc(2026, 7, 17),
      ),
    ]);

    final ownerMessages = await database.messagesDao
        .watchByRoom(7, 'https://example.test', 11)
        .first;
    final otherMessages = await database.messagesDao
        .watchByRoom(7, 'https://example.test', 12)
        .first;

    expect(ownerMessages, hasLength(1));
    expect(otherMessages, isEmpty);
  });

  test('clearing local data keeps the database open and reusable', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.settingsDao.setValue('token', 'secret');
    await database.messagesDao.upsertMessages([
      MessagesCompanion.insert(
        id: 1,
        serverUrl: const Value('https://example.test'),
        accountUserId: const Value(11),
        roomId: 7,
        senderId: 99,
        type: 'text',
        content: 'private message',
        createdAt: DateTime.utc(2026, 7, 17),
      ),
    ]);

    await database.clearLocalData();

    expect(await database.settingsDao.getValue('token'), null);
    expect(
      await database.messagesDao
          .watchByRoom(7, 'https://example.test', 11)
          .first,
      isEmpty,
    );
    await database.settingsDao.setValue('server_url', 'http://localhost:8080');
    expect(
      await database.settingsDao.getValue('server_url'),
      'http://localhost:8080',
    );
  });

  test('legacy database and WAL are moved into the data directory', () async {
    final root = await Directory.systemTemp.createTemp('nexusroom-storage-');
    addTearDown(() => root.delete(recursive: true));
    final legacy = File('${root.path}/documents/nexusroom.sqlite');
    final target = File('${root.path}/local/NexusRoom/data/nexusroom.sqlite');
    await legacy.parent.create(recursive: true);
    await legacy.writeAsString('database');
    await File('${legacy.path}-wal').writeAsString('wal');

    final migrated = await AppDataPaths.migrateLegacyDatabase(
      target: target,
      legacy: legacy,
    );

    expect(migrated.path, target.path);
    expect(await target.readAsString(), 'database');
    expect(await File('${target.path}-wal').readAsString(), 'wal');
    expect(await legacy.exists(), isFalse);
  });

  test('the newest application-data location is migrated before Documents',
      () async {
    final root = await Directory.systemTemp.createTemp('nexusroom-sources-');
    addTearDown(() => root.delete(recursive: true));
    final target = File('${root.path}/portable/data/nexusroom.sqlite');
    final applicationData =
        File('${root.path}/app-data/NexusRoom/data/nexusroom.sqlite');
    final documents = File('${root.path}/documents/nexusroom.sqlite');
    await applicationData.parent.create(recursive: true);
    await documents.parent.create(recursive: true);
    await applicationData.writeAsString('application-data');
    await documents.writeAsString('documents');

    await AppDataPaths.migrateFirstAvailableDatabase(
      target: target,
      legacyCandidates: [applicationData, documents],
    );

    expect(await target.readAsString(), 'application-data');
    expect(await applicationData.exists(), isFalse);
    expect(await documents.readAsString(), 'documents');
  });

  test('schema v2 rows migrate to the current account scope', () async {
    final root = await Directory.systemTemp.createTemp('nexusroom-schema-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/nexusroom.sqlite');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NULL
      )
    ''');
    legacy.execute('''
      CREATE TABLE messages (
        id INTEGER NOT NULL,
        server_url TEXT NOT NULL DEFAULT '',
        room_id INTEGER NOT NULL,
        sender_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        sender_nickname TEXT NULL,
        sender_avatar_url TEXT NULL,
        meta_json TEXT NULL,
        PRIMARY KEY (server_url, id)
      )
    ''');
    legacy.execute("INSERT INTO settings VALUES ('user_id', '23')");
    legacy.execute('''
      INSERT INTO messages (
        id, server_url, room_id, sender_id, type, content, created_at
      ) VALUES (1, 'https://example.test', 7, 99, 'text', 'legacy', 0)
    ''');
    legacy.execute('PRAGMA user_version = 2');
    legacy.dispose();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    await database.customSelect('SELECT 1').get();
    addTearDown(database.close);

    final ownerRows = await database.messagesDao
        .watchByRoom(7, 'https://example.test', 23)
        .first;
    final otherRows = await database.messagesDao
        .watchByRoom(7, 'https://example.test', 24)
        .first;
    expect(ownerRows.single.content, 'legacy');
    expect(otherRows, isEmpty);
  });
}

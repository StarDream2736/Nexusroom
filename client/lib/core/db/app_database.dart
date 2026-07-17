import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'daos/messages_dao.dart';
import 'daos/settings_dao.dart';
import 'tables/messages.dart';
import 'tables/settings.dart';
import '../storage/app_data_paths.dart';

part 'app_database.g.dart';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await AppDataPaths.databaseFile();
    return NativeDatabase(file);
  });
}

@DriftDatabase(
  tables: [Settings, Messages],
  daos: [SettingsDao, MessagesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  /// Clears user-owned state while keeping the live database connection and
  /// schema available to the running application.
  Future<void> clearLocalData() async {
    await transaction(() async {
      await delete(messages).go();
      await delete(settings).go();
    });
    await customStatement('VACUUM');
    await customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          // v1→v2: 旧表 primary key 只有 id，无法直接 ALTER 改复合主键。
          // 最安全的做法：删除旧消息表，由 Drift 自动创建新表。
          // 消息数据会在下次进入房间时从服务端重新同步。
          await migrator.deleteTable('messages');
          await migrator.createTable(messages);
        }
        if (from < 3) {
          await customStatement('ALTER TABLE messages RENAME TO messages_v2');
          await migrator.createTable(messages);
          await customStatement('''
            INSERT INTO messages (
              id, server_url, account_user_id, room_id, sender_id, type,
              content, created_at, sender_nickname, sender_avatar_url, meta_json
            )
            SELECT
              id,
              server_url,
              COALESCE(
                (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'user_id'),
                0
              ),
              room_id,
              sender_id,
              type,
              content,
              created_at,
              sender_nickname,
              sender_avatar_url,
              meta_json
            FROM messages_v2
          ''');
          await customStatement('DROP TABLE messages_v2');
        }
      },
    );
  }
}

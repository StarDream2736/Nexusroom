import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'daos/messages_dao.dart';
import 'daos/settings_dao.dart';
import 'tables/messages.dart';
import 'tables/settings.dart';

part 'app_database.g.dart';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/nexusroom.sqlite');
    return NativeDatabase(file);
  });
}

@DriftDatabase(
  tables: [Settings, Messages],
  daos: [SettingsDao, MessagesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

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
      },
    );
  }
}

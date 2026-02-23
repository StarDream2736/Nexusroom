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
  int get schemaVersion => 1;
}

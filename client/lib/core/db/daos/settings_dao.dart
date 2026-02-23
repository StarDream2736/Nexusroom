import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/settings.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<String?> getValue(String key) async {
    final row = await (select(settings)..where((tbl) => tbl.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setValue(String key, String value) async {
    await into(settings).insertOnConflictUpdate(SettingsCompanion(
      key: Value(key),
      value: Value(value),
    ));
  }

  Future<void> remove(String key) async {
    await (delete(settings)..where((tbl) => tbl.key.equals(key))).go();
  }
}

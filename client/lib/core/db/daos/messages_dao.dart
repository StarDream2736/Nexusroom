import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/messages.dart';

part 'messages_dao.g.dart';

@DriftAccessor(tables: [Messages])
class MessagesDao extends DatabaseAccessor<AppDatabase> with _$MessagesDaoMixin {
  MessagesDao(super.db);

  Stream<List<Message>> watchByRoom(int roomId) {
    return (select(messages)
          ..where((tbl) => tbl.roomId.equals(roomId))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.id)]))
        .watch();
  }

  Future<int?> getLatestMessageId(int roomId) async {
    final row = await (selectOnly(messages)
          ..addColumns([messages.id.max()])
          ..where(messages.roomId.equals(roomId)))
        .getSingleOrNull();
    return row?.read(messages.id.max());
  }

  Future<void> upsertMessages(List<MessagesCompanion> entries) async {
    if (entries.isEmpty) return;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(messages, entries);
    });
  }

  Future<void> clearRoom(int roomId) async {
    await (delete(messages)..where((tbl) => tbl.roomId.equals(roomId))).go();
  }
}

import 'package:drift/drift.dart';

class Messages extends Table {
  /// 消息在目标服务器上的 ID（不同服务器可能重复）
  IntColumn get id => integer()();

  /// 消息所属服务器 URL，用于隔离不同服务器的数据
  TextColumn get serverUrl => text().withDefault(const Constant(''))();

  /// Local account that owns this cached row.
  IntColumn get accountUserId => integer().withDefault(const Constant(0))();

  IntColumn get roomId => integer()();
  IntColumn get senderId => integer()();
  TextColumn get type => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get senderNickname => text().nullable()();
  TextColumn get senderAvatarUrl => text().nullable()();
  TextColumn get metaJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {serverUrl, accountUserId, id};
}

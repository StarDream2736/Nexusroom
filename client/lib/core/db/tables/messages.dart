import 'package:drift/drift.dart';

class Messages extends Table {
  IntColumn get id => integer()();
  IntColumn get roomId => integer()();
  IntColumn get senderId => integer()();
  TextColumn get type => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get senderNickname => text().nullable()();
  TextColumn get senderAvatarUrl => text().nullable()();
  TextColumn get metaJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

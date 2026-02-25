// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(Insertable<Setting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value']),
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String? value;
  const Setting({required this.key, this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value:
          value == null && nullToAbsent ? const Value.absent() : Value(value),
    );
  }

  factory Setting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
    };
  }

  Setting copyWith(
          {String? key, Value<String?> value = const Value.absent()}) =>
      Setting(
        key: key ?? this.key,
        value: value.present ? value.value : this.value,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String?> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith(
      {Value<String>? key, Value<String?>? value, Value<int>? rowid}) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _serverUrlMeta =
      const VerificationMeta('serverUrl');
  @override
  late final GeneratedColumn<String> serverUrl = GeneratedColumn<String>(
      'server_url', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<int> roomId = GeneratedColumn<int>(
      'room_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<int> senderId = GeneratedColumn<int>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _senderNicknameMeta =
      const VerificationMeta('senderNickname');
  @override
  late final GeneratedColumn<String> senderNickname = GeneratedColumn<String>(
      'sender_nickname', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderAvatarUrlMeta =
      const VerificationMeta('senderAvatarUrl');
  @override
  late final GeneratedColumn<String> senderAvatarUrl = GeneratedColumn<String>(
      'sender_avatar_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metaJsonMeta =
      const VerificationMeta('metaJson');
  @override
  late final GeneratedColumn<String> metaJson = GeneratedColumn<String>(
      'meta_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        serverUrl,
        roomId,
        senderId,
        type,
        content,
        createdAt,
        senderNickname,
        senderAvatarUrl,
        metaJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_url')) {
      context.handle(_serverUrlMeta,
          serverUrl.isAcceptableOrUnknown(data['server_url']!, _serverUrlMeta));
    }
    if (data.containsKey('room_id')) {
      context.handle(_roomIdMeta,
          roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta));
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('sender_nickname')) {
      context.handle(
          _senderNicknameMeta,
          senderNickname.isAcceptableOrUnknown(
              data['sender_nickname']!, _senderNicknameMeta));
    }
    if (data.containsKey('sender_avatar_url')) {
      context.handle(
          _senderAvatarUrlMeta,
          senderAvatarUrl.isAcceptableOrUnknown(
              data['sender_avatar_url']!, _senderAvatarUrlMeta));
    }
    if (data.containsKey('meta_json')) {
      context.handle(_metaJsonMeta,
          metaJson.isAcceptableOrUnknown(data['meta_json']!, _metaJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverUrl, id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_url'])!,
      roomId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}room_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sender_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      senderNickname: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_nickname']),
      senderAvatarUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}sender_avatar_url']),
      metaJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}meta_json']),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  /// 消息在目标服务器上的 ID（不同服务器可能重复）
  final int id;

  /// 消息所属服务器 URL，用于隔离不同服务器的数据
  final String serverUrl;
  final int roomId;
  final int senderId;
  final String type;
  final String content;
  final DateTime createdAt;
  final String? senderNickname;
  final String? senderAvatarUrl;
  final String? metaJson;
  const Message(
      {required this.id,
      required this.serverUrl,
      required this.roomId,
      required this.senderId,
      required this.type,
      required this.content,
      required this.createdAt,
      this.senderNickname,
      this.senderAvatarUrl,
      this.metaJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_url'] = Variable<String>(serverUrl);
    map['room_id'] = Variable<int>(roomId);
    map['sender_id'] = Variable<int>(senderId);
    map['type'] = Variable<String>(type);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || senderNickname != null) {
      map['sender_nickname'] = Variable<String>(senderNickname);
    }
    if (!nullToAbsent || senderAvatarUrl != null) {
      map['sender_avatar_url'] = Variable<String>(senderAvatarUrl);
    }
    if (!nullToAbsent || metaJson != null) {
      map['meta_json'] = Variable<String>(metaJson);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      serverUrl: Value(serverUrl),
      roomId: Value(roomId),
      senderId: Value(senderId),
      type: Value(type),
      content: Value(content),
      createdAt: Value(createdAt),
      senderNickname: senderNickname == null && nullToAbsent
          ? const Value.absent()
          : Value(senderNickname),
      senderAvatarUrl: senderAvatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(senderAvatarUrl),
      metaJson: metaJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metaJson),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      serverUrl: serializer.fromJson<String>(json['serverUrl']),
      roomId: serializer.fromJson<int>(json['roomId']),
      senderId: serializer.fromJson<int>(json['senderId']),
      type: serializer.fromJson<String>(json['type']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      senderNickname: serializer.fromJson<String?>(json['senderNickname']),
      senderAvatarUrl: serializer.fromJson<String?>(json['senderAvatarUrl']),
      metaJson: serializer.fromJson<String?>(json['metaJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverUrl': serializer.toJson<String>(serverUrl),
      'roomId': serializer.toJson<int>(roomId),
      'senderId': serializer.toJson<int>(senderId),
      'type': serializer.toJson<String>(type),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'senderNickname': serializer.toJson<String?>(senderNickname),
      'senderAvatarUrl': serializer.toJson<String?>(senderAvatarUrl),
      'metaJson': serializer.toJson<String?>(metaJson),
    };
  }

  Message copyWith(
          {int? id,
          String? serverUrl,
          int? roomId,
          int? senderId,
          String? type,
          String? content,
          DateTime? createdAt,
          Value<String?> senderNickname = const Value.absent(),
          Value<String?> senderAvatarUrl = const Value.absent(),
          Value<String?> metaJson = const Value.absent()}) =>
      Message(
        id: id ?? this.id,
        serverUrl: serverUrl ?? this.serverUrl,
        roomId: roomId ?? this.roomId,
        senderId: senderId ?? this.senderId,
        type: type ?? this.type,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        senderNickname:
            senderNickname.present ? senderNickname.value : this.senderNickname,
        senderAvatarUrl: senderAvatarUrl.present
            ? senderAvatarUrl.value
            : this.senderAvatarUrl,
        metaJson: metaJson.present ? metaJson.value : this.metaJson,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      serverUrl: data.serverUrl.present ? data.serverUrl.value : this.serverUrl,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      type: data.type.present ? data.type.value : this.type,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      senderNickname: data.senderNickname.present
          ? data.senderNickname.value
          : this.senderNickname,
      senderAvatarUrl: data.senderAvatarUrl.present
          ? data.senderAvatarUrl.value
          : this.senderAvatarUrl,
      metaJson: data.metaJson.present ? data.metaJson.value : this.metaJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('serverUrl: $serverUrl, ')
          ..write('roomId: $roomId, ')
          ..write('senderId: $senderId, ')
          ..write('type: $type, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('senderNickname: $senderNickname, ')
          ..write('senderAvatarUrl: $senderAvatarUrl, ')
          ..write('metaJson: $metaJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, serverUrl, roomId, senderId, type,
      content, createdAt, senderNickname, senderAvatarUrl, metaJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.serverUrl == this.serverUrl &&
          other.roomId == this.roomId &&
          other.senderId == this.senderId &&
          other.type == this.type &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.senderNickname == this.senderNickname &&
          other.senderAvatarUrl == this.senderAvatarUrl &&
          other.metaJson == this.metaJson);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<String> serverUrl;
  final Value<int> roomId;
  final Value<int> senderId;
  final Value<String> type;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<String?> senderNickname;
  final Value<String?> senderAvatarUrl;
  final Value<String?> metaJson;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.serverUrl = const Value.absent(),
    this.roomId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.type = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.senderNickname = const Value.absent(),
    this.senderAvatarUrl = const Value.absent(),
    this.metaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required int id,
    this.serverUrl = const Value.absent(),
    required int roomId,
    required int senderId,
    required String type,
    required String content,
    required DateTime createdAt,
    this.senderNickname = const Value.absent(),
    this.senderAvatarUrl = const Value.absent(),
    this.metaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        roomId = Value(roomId),
        senderId = Value(senderId),
        type = Value(type),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<String>? serverUrl,
    Expression<int>? roomId,
    Expression<int>? senderId,
    Expression<String>? type,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<String>? senderNickname,
    Expression<String>? senderAvatarUrl,
    Expression<String>? metaJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverUrl != null) 'server_url': serverUrl,
      if (roomId != null) 'room_id': roomId,
      if (senderId != null) 'sender_id': senderId,
      if (type != null) 'type': type,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (senderNickname != null) 'sender_nickname': senderNickname,
      if (senderAvatarUrl != null) 'sender_avatar_url': senderAvatarUrl,
      if (metaJson != null) 'meta_json': metaJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? serverUrl,
      Value<int>? roomId,
      Value<int>? senderId,
      Value<String>? type,
      Value<String>? content,
      Value<DateTime>? createdAt,
      Value<String?>? senderNickname,
      Value<String?>? senderAvatarUrl,
      Value<String?>? metaJson,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      serverUrl: serverUrl ?? this.serverUrl,
      roomId: roomId ?? this.roomId,
      senderId: senderId ?? this.senderId,
      type: type ?? this.type,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      senderNickname: senderNickname ?? this.senderNickname,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      metaJson: metaJson ?? this.metaJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverUrl.present) {
      map['server_url'] = Variable<String>(serverUrl.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<int>(roomId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<int>(senderId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (senderNickname.present) {
      map['sender_nickname'] = Variable<String>(senderNickname.value);
    }
    if (senderAvatarUrl.present) {
      map['sender_avatar_url'] = Variable<String>(senderAvatarUrl.value);
    }
    if (metaJson.present) {
      map['meta_json'] = Variable<String>(metaJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('serverUrl: $serverUrl, ')
          ..write('roomId: $roomId, ')
          ..write('senderId: $senderId, ')
          ..write('type: $type, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('senderNickname: $senderNickname, ')
          ..write('senderAvatarUrl: $senderAvatarUrl, ')
          ..write('metaJson: $metaJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  late final MessagesDao messagesDao = MessagesDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [settings, messages];
}

typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  Value<String?> value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String?> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SettingsTable,
    Setting,
    $$SettingsTableFilterComposer,
    $$SettingsTableOrderingComposer,
    $$SettingsTableAnnotationComposer,
    $$SettingsTableCreateCompanionBuilder,
    $$SettingsTableUpdateCompanionBuilder,
    (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
    Setting,
    PrefetchHooks Function()> {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String?> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            Value<String?> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SettingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SettingsTable,
    Setting,
    $$SettingsTableFilterComposer,
    $$SettingsTableOrderingComposer,
    $$SettingsTableAnnotationComposer,
    $$SettingsTableCreateCompanionBuilder,
    $$SettingsTableUpdateCompanionBuilder,
    (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
    Setting,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required int id,
  Value<String> serverUrl,
  required int roomId,
  required int senderId,
  required String type,
  required String content,
  required DateTime createdAt,
  Value<String?> senderNickname,
  Value<String?> senderAvatarUrl,
  Value<String?> metaJson,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<String> serverUrl,
  Value<int> roomId,
  Value<int> senderId,
  Value<String> type,
  Value<String> content,
  Value<DateTime> createdAt,
  Value<String?> senderNickname,
  Value<String?> senderAvatarUrl,
  Value<String?> metaJson,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverUrl => $composableBuilder(
      column: $table.serverUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get roomId => $composableBuilder(
      column: $table.roomId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderNickname => $composableBuilder(
      column: $table.senderNickname,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderAvatarUrl => $composableBuilder(
      column: $table.senderAvatarUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metaJson => $composableBuilder(
      column: $table.metaJson, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverUrl => $composableBuilder(
      column: $table.serverUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get roomId => $composableBuilder(
      column: $table.roomId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderNickname => $composableBuilder(
      column: $table.senderNickname,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderAvatarUrl => $composableBuilder(
      column: $table.senderAvatarUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metaJson => $composableBuilder(
      column: $table.metaJson, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverUrl =>
      $composableBuilder(column: $table.serverUrl, builder: (column) => column);

  GeneratedColumn<int> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<int> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get senderNickname => $composableBuilder(
      column: $table.senderNickname, builder: (column) => column);

  GeneratedColumn<String> get senderAvatarUrl => $composableBuilder(
      column: $table.senderAvatarUrl, builder: (column) => column);

  GeneratedColumn<String> get metaJson =>
      $composableBuilder(column: $table.metaJson, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> serverUrl = const Value.absent(),
            Value<int> roomId = const Value.absent(),
            Value<int> senderId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> senderNickname = const Value.absent(),
            Value<String?> senderAvatarUrl = const Value.absent(),
            Value<String?> metaJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            serverUrl: serverUrl,
            roomId: roomId,
            senderId: senderId,
            type: type,
            content: content,
            createdAt: createdAt,
            senderNickname: senderNickname,
            senderAvatarUrl: senderAvatarUrl,
            metaJson: metaJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int id,
            Value<String> serverUrl = const Value.absent(),
            required int roomId,
            required int senderId,
            required String type,
            required String content,
            required DateTime createdAt,
            Value<String?> senderNickname = const Value.absent(),
            Value<String?> senderAvatarUrl = const Value.absent(),
            Value<String?> metaJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            serverUrl: serverUrl,
            roomId: roomId,
            senderId: senderId,
            type: type,
            content: content,
            createdAt: createdAt,
            senderNickname: senderNickname,
            senderAvatarUrl: senderAvatarUrl,
            metaJson: metaJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
}

import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

class MessageModel {
  const MessageModel({
    required this.id,
    required this.serverUrl,
    required this.roomId,
    required this.senderId,
    required this.type,
    required this.content,
    required this.createdAt,
    this.senderNickname,
    this.senderAvatarUrl,
    this.meta,
  });

  final int id;
  final String serverUrl;
  final int roomId;
  final int senderId;
  final String type;
  final String content;
  final DateTime createdAt;
  final String? senderNickname;
  final String? senderAvatarUrl;
  final Map<String, dynamic>? meta;

  /// [serverUrl] 必须由调用方传入，服务端 JSON 不包含此信息
  factory MessageModel.fromApi(Map<String, dynamic> json, {required String serverUrl}) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return MessageModel(
      id: (json['id'] as num).toInt(),
      serverUrl: serverUrl,
      roomId: (json['room_id'] as num).toInt(),
      senderId: (json['sender_id'] as num).toInt(),
      type: json['type'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderNickname: sender?['nickname'] as String?,
      senderAvatarUrl: sender?['avatar_url'] as String?,
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }

  factory MessageModel.fromWs(Map<String, dynamic> json, {required String serverUrl}) {
    return MessageModel.fromApi(json, serverUrl: serverUrl);
  }

  MessagesCompanion toCompanion() {
    return MessagesCompanion(
      id: Value(id),
      serverUrl: Value(serverUrl),
      roomId: Value(roomId),
      senderId: Value(senderId),
      type: Value(type),
      content: Value(content),
      createdAt: Value(createdAt),
      senderNickname: Value(senderNickname),
      senderAvatarUrl: Value(senderAvatarUrl),
      metaJson: Value(meta == null ? null : jsonEncode(meta)),
    );
  }
}

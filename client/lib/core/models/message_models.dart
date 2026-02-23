import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

class MessageModel {
  const MessageModel({
    required this.id,
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
  final int roomId;
  final int senderId;
  final String type;
  final String content;
  final DateTime createdAt;
  final String? senderNickname;
  final String? senderAvatarUrl;
  final Map<String, dynamic>? meta;

  factory MessageModel.fromApi(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return MessageModel(
      id: (json['id'] as num).toInt(),
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

  factory MessageModel.fromWs(Map<String, dynamic> json) {
    return MessageModel.fromApi(json);
  }

  MessagesCompanion toCompanion() {
    return MessagesCompanion(
      id: Value(id),
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

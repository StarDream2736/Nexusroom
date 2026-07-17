import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexusroom/core/db/app_database.dart';
import 'package:nexusroom/core/network/ws_service.dart';

void main() {
  late AppDatabase database;
  late FakeWsChannel channel;
  late WsService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    channel = FakeWsChannel();
    service = WsService(db: database, connector: (_) => channel);
  });

  tearDown(() async {
    service.dispose();
    await channel.close();
    await database.close();
  });

  test('waits for room join and server echo before confirming a message',
      () async {
    service.connect('http://localhost:8080', 'token');
    channel.receive({
      'event': 'connected',
      'payload': {
        'rtc': <String, dynamic>{'ice_servers': <dynamic>[]}
      },
    });
    await _waitFor(
        () => service.connectionState == WsConnectionState.connected);

    final send = service.sendChat(roomId: 7, content: 'hello');
    final join = await channel.nextSent('room.join');
    expect(join['room_id'], 7);

    channel.receive({
      'event': 'room.joined',
      'room_id': 7,
      'payload': {'room_id': 7},
    });

    final chat = await channel.nextSent('chat.send');
    final chatPayload = chat['payload'] as Map<String, dynamic>;
    final clientMessageId = chatPayload['client_message_id'] as String;
    expect(chatPayload['content'], 'hello');

    channel.receive({
      'event': 'chat.message',
      'room_id': 7,
      'payload': {
        'id': 1,
        'room_id': 7,
        'sender_id': 9,
        'type': 'text',
        'content': 'hello',
        'client_message_id': clientMessageId,
        'created_at': DateTime.utc(2026, 7, 17).toIso8601String(),
        'sender': {
          'id': 9,
          'nickname': 'Tester',
          'avatar_url': '',
        },
      },
    });

    await send;
    await _waitFor(() async {
      final messages = await database.messagesDao
          .watchByRoom(7, 'http://localhost:8080')
          .first;
      return messages.length == 1;
    });
  });

  test('surfaces a server chat rejection to the caller', () async {
    service.connect('http://localhost:8080', 'token');
    channel.receive({
      'event': 'connected',
      'payload': {
        'rtc': <String, dynamic>{'ice_servers': <dynamic>[]}
      },
    });
    await _waitFor(
        () => service.connectionState == WsConnectionState.connected);

    final send = service.sendChat(roomId: 8, content: 'blocked');
    await channel.nextSent('room.join');
    channel.receive({
      'event': 'room.joined',
      'room_id': 8,
      'payload': {'room_id': 8},
    });
    final chat = await channel.nextSent('chat.send');
    final payload = chat['payload'] as Map<String, dynamic>;
    channel.receive({
      'event': 'chat.error',
      'room_id': 8,
      'payload': {
        'room_id': 8,
        'reason': 'content_too_large',
        'client_message_id': payload['client_message_id'],
      },
    });

    await expectLater(
      send,
      throwsA(
        isA<ChatSendException>().having(
          (error) => error.reason,
          'reason',
          'content_too_large',
        ),
      ),
    );
  });
}

class FakeWsChannel implements WsChannel {
  FakeWsChannel() {
    _outgoing.stream.listen((data) {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      _sent.add(decoded);
    });
  }

  final _incoming = StreamController<dynamic>();
  final _outgoing = StreamController<dynamic>();
  final List<Map<String, dynamic>> _sent = [];

  @override
  Future<void> get ready async {}

  @override
  StreamSink<dynamic> get sink => _outgoing.sink;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  void receive(Map<String, dynamic> message) {
    _incoming.add(jsonEncode(message));
  }

  Future<Map<String, dynamic>> nextSent(String event) async {
    Map<String, dynamic>? match;
    await _waitFor(() {
      final index = _sent.indexWhere((item) => item['event'] == event);
      if (index < 0) return false;
      match = _sent.removeAt(index);
      return true;
    });
    return match!;
  }

  Future<void> close() async {
    await _incoming.close();
    await _outgoing.close();
  }
}

Future<void> _waitFor(FutureOr<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

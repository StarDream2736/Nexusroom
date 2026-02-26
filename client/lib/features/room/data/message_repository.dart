import '../../../core/db/daos/messages_dao.dart';
import '../../../core/models/message_models.dart';
import '../../../core/network/api_client.dart';

class MessageRepository {
  MessageRepository(this._client, this._dao);

  final ApiClient _client;
  final MessagesDao _dao;

  /// 递归拉取所有新消息，直到返回数量 < limit 说明已追平
  /// [serverUrl] 用于本地消息隔离（不同服务器的消息互不干扰）
  Future<void> syncLatest(int roomId, {required String serverUrl, int limit = 50}) async {
    int? afterId = await _dao.getLatestMessageId(roomId, serverUrl);

    while (true) {
      final data = await _client.getData(
        '/api/v1/rooms/$roomId/messages',
        queryParameters: {
          if (afterId != null) 'after_id': afterId,
          'limit': limit,
        },
      );

      final list = (data as List<dynamic>);
      if (list.isEmpty) break;

      final messages = list
          .map((item) => MessageModel.fromApi(
                item as Map<String, dynamic>,
                serverUrl: serverUrl,
              ))
          .toList();

      await _dao.upsertMessages(messages.map((m) => m.toCompanion()).toList());

      // 如果返回数量 < limit，说明已经拉完所有新消息
      if (messages.length < limit) break;

      // 用最后一条消息的 ID 作为下一次拉取的 after_id
      afterId = messages.last.id;
    }
  }
}

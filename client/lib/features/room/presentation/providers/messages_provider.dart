import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/providers/app_providers.dart';

/// Family key: (roomId, serverUrl)
typedef MessageKey = ({int roomId, String serverUrl});

final messagesStreamProvider = StreamProvider.family<List<Message>, MessageKey>(
  (ref, key) {
    return ref.watch(appDatabaseProvider).messagesDao.watchByRoom(
      key.roomId,
      key.serverUrl,
    );
  },
);

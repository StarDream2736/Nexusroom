import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database.dart';
import '../../../../core/providers/app_providers.dart';

final messagesStreamProvider = StreamProvider.family<List<Message>, int>(
  (ref, roomId) {
    return ref.watch(appDatabaseProvider).messagesDao.watchByRoom(roomId);
  },
);

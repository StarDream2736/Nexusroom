import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/room_models.dart';
import '../../../../core/providers/app_providers.dart';

final roomDetailProvider = FutureProvider.family<RoomDetail, int>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).getRoomDetail(roomId);
});

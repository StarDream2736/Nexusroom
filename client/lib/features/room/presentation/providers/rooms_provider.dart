import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/models/room_models.dart';

final roomsProvider = FutureProvider<List<RoomSummary>>((ref) async {
  return ref.watch(roomRepositoryProvider).listRooms();
});

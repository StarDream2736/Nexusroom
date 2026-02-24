import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/livekit_models.dart';
import '../../../../core/providers/app_providers.dart';

/// Loads the ingress list for a given room.
final roomIngressesProvider =
    FutureProvider.family<List<IngressModel>, int>((ref, roomId) {
  return ref.watch(roomRepositoryProvider).listIngresses(roomId);
});

/// Currently selected ingress (shared between RoomDetailPage & RightPanel).
final selectedIngressProvider = StateProvider<IngressModel?>((ref) => null);

/// Whether the stream audio is muted by the viewer.
final streamMutedProvider = StateProvider<bool>((ref) => false);

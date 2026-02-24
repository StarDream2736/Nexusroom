import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks which user IDs are currently speaking (audio active).
///
/// Updated by the `voice.state_update` WebSocket event in RoomDetailPage.
class VoiceActiveNotifier extends StateNotifier<Set<int>> {
  VoiceActiveNotifier() : super({});

  void setActive(int userId, {required bool active}) {
    if (active) {
      state = {...state, userId};
    } else {
      state = {...state}..remove(userId);
    }
  }

  void clear() => state = {};
}

final voiceActiveUsersProvider =
    StateNotifierProvider<VoiceActiveNotifier, Set<int>>(
  (ref) => VoiceActiveNotifier(),
);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/native/screen_capture_service.dart';
import '../../../../core/native/screen_source_enumerator.dart';
import '../../../../core/providers/app_providers.dart';

/// Provides a reactive stream of the current [CaptureStatus].
final captureStatusProvider = StreamProvider<CaptureStatus>((ref) {
  final service = ref.watch(screenCaptureServiceProvider);
  return service.statusStream;
});

/// Provides a reactive stream of encoding [CaptureStats].
final captureStatsProvider = StreamProvider<CaptureStats>((ref) {
  final service = ref.watch(screenCaptureServiceProvider);
  return service.statsStream;
});

/// Whether a screen capture session is currently active (streaming or starting).
final isCapturingProvider = Provider<bool>((ref) {
  final status = ref.watch(captureStatusProvider).valueOrNull;
  return status == CaptureStatus.streaming ||
      status == CaptureStatus.starting;
});

/// The stream key currently being captured (null if idle).
final captureStreamKeyProvider = Provider<String?>((ref) {
  final service = ref.watch(screenCaptureServiceProvider);
  return service.activeStreamKey;
});

/// Available window sources for capture (async, refreshable).
final windowSourcesProvider = FutureProvider<List<WindowSource>>((ref) async {
  return ScreenSourceEnumerator.listWindows();
});

/// Available display sources for capture (async, refreshable).
final displaySourcesProvider = FutureProvider<List<DisplaySource>>((ref) async {
  return ScreenSourceEnumerator.listDisplays();
});

/// Available audio devices for capture (async, refreshable).
final audioDevicesProvider = FutureProvider<List<AudioDevice>>((ref) async {
  return ScreenSourceEnumerator.listAudioDevices();
});

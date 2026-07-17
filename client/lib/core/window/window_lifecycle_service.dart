import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../native/screen_capture_service.dart';
import '../native/wireguard_service.dart';
import '../network/rtc_service.dart';
import '../network/ws_service.dart';

/// Coordinates window visibility and bounded native-resource shutdown.
class WindowLifecycleService with WindowListener {
  WindowLifecycleService(
    this._screenCaptureService,
    this._rtcService,
    this._wsService,
    this._wireGuardService,
  );

  final ScreenCaptureService _screenCaptureService;
  final RtcService _rtcService;
  final WsService _wsService;
  final WireGuardService _wireGuardService;
  bool _isBackground = false;
  bool _initialized = false;
  bool _isClosing = false;
  Timer? _blurTimer;

  bool get isBackground => _isBackground;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.setMinimumSize(const Size(900, 600));
  }

  void dispose() {
    _blurTimer?.cancel();
    windowManager.removeListener(this);
  }

  @override
  void onWindowClose() {
    if (_isClosing) return;
    _isClosing = true;
    unawaited(_closeWindow());
  }

  Future<void> _closeWindow() async {
    _blurTimer?.cancel();

    // Remove the window immediately. Native media cleanup may take hundreds
    // of milliseconds on Windows and must not hold the visible UI open.
    try {
      await windowManager.hide();
    } catch (error) {
      debugPrint('[WindowLifecycle] hide failed: $error');
    }

    _screenCaptureService.dispose();
    _wsService.disconnect();

    final cleanup = <Future<void>>[
      _rtcService.disconnect(),
      if (_wireGuardService.isConnected) _wireGuardService.stopTunnel(),
    ];
    try {
      await Future.wait(cleanup).timeout(const Duration(milliseconds: 1200));
    } catch (error) {
      debugPrint('[WindowLifecycle] cleanup timed out or failed: $error');
    }

    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (error) {
      debugPrint('[WindowLifecycle] destroy failed: $error');
    }
  }

  @override
  void onWindowMinimize() => _enterBackground();

  @override
  void onWindowRestore() => _enterForeground();

  @override
  void onWindowFocus() {
    _blurTimer?.cancel();
    if (_isBackground) _enterForeground();
  }

  @override
  void onWindowBlur() {
    _blurTimer?.cancel();
    _blurTimer = Timer(const Duration(seconds: 1), () async {
      final focused = await windowManager.isFocused();
      if (!focused) _enterBackground();
    });
  }

  void _enterBackground() {
    if (_isBackground) return;
    _isBackground = true;
  }

  void _enterForeground() {
    if (!_isBackground) return;
    _isBackground = false;
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../network/livekit_service.dart';

/// 窗口生命周期管理：最小化/失焦时暂停视频解码
class WindowLifecycleService with WindowListener {
  WindowLifecycleService(this._livekitService);

  final LiveKitService _livekitService;
  bool _isBackground = false;
  bool _initialized = false;
  Timer? _blurTimer;

  bool get isBackground => _isBackground;

  Future<void> init() async {
    if (_initialized) return; // 防止重复初始化
    _initialized = true;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    // 设置窗口属性
    await windowManager.setPreventClose(false);
    await windowManager.setMinimumSize(const Size(900, 600));
  }

  void dispose() {
    _blurTimer?.cancel();
    windowManager.removeListener(this);
  }

  @override
  void onWindowMinimize() {
    _enterBackground();
  }

  @override
  void onWindowRestore() {
    _enterForeground();
  }

  @override
  void onWindowFocus() {
    _blurTimer?.cancel();
    if (_isBackground) {
      _enterForeground();
    }
  }

  @override
  void onWindowBlur() {
    // 失焦时加 1 秒延迟，避免窗口切换过渡期误触发
    _blurTimer?.cancel();
    _blurTimer = Timer(const Duration(seconds: 1), () async {
      final focused = await windowManager.isFocused();
      if (!focused) {
        _enterBackground();
      }
    });
  }

  void _enterBackground() {
    if (_isBackground) return;
    _isBackground = true;
    // 暂停所有视频轨道解码，音频不受影响
    _livekitService.disableAllVideoTracks();
  }

  void _enterForeground() {
    if (!_isBackground) return;
    _isBackground = false;
    // 仅恢复当前主视窗正在显示的视频轨道
    // enableAllVideoTracks 在 LiveKitService 内部仅恢复已订阅的轨道
    _livekitService.enableAllVideoTracks();
  }
}

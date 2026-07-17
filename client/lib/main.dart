import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/models/app_settings.dart';
import 'core/providers/app_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit（HTTP-FLV 直播播放器）
  MediaKit.ensureInitialized();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(900, 600),
    size: Size(1200, 800),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'NexusRoom',
    backgroundColor: Colors.transparent,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    const ProviderScope(
      child: NexusRoomApp(),
    ),
  );
}

/// Consistent desktop scrolling without overscroll bounce.
class _DesktopScrollBehavior extends ScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class NexusRoomApp extends ConsumerStatefulWidget {
  const NexusRoomApp({super.key});

  @override
  ConsumerState<NexusRoomApp> createState() => _NexusRoomAppState();
}

class _NexusRoomAppState extends ConsumerState<NexusRoomApp> {
  @override
  void initState() {
    super.initState();
    ref.read(windowLifecycleServiceProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final colorMode = ref.watch(appSettingsProvider).valueOrNull?.colorMode ??
        AppColorMode.dark;
    final brightness =
        colorMode == AppColorMode.dark ? Brightness.dark : Brightness.light;
    final theme = AppTheme.forBrightness(brightness);

    return MaterialApp.router(
      title: 'NexusRoom',
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeMode: ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 180),
      themeAnimationCurve: Curves.easeOutCubic,
      routerConfig: router,
      scrollBehavior: const _DesktopScrollBehavior(),
    );
  }
}

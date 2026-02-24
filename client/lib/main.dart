import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/providers/app_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化窗口管理器
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(900, 600));
  await windowManager.setTitle('NexusRoom');
  
  runApp(
    const ProviderScope(
      child: NexusRoomApp(),
    ),
  );
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

    return MaterialApp.router(
      title: 'NexusRoom',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}

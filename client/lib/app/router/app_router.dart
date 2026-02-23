import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../features/auth/presentation/pages/server_setup_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/room/presentation/pages/room_list_page.dart';
import '../../features/room/presentation/pages/room_detail_page.dart';
import '../../features/room/presentation/pages/create_room_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final settings = ref.watch(appSettingsProvider);

  return GoRouter(
    initialLocation: '/setup',
    routes: [
      // 服务器配置
      GoRoute(
        path: '/setup',
        builder: (context, state) => const ServerSetupPage(),
      ),
      
      // 登录
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      
      // 注册
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      
      // 房间列表
      GoRoute(
        path: '/home',
        builder: (context, state) => const RoomListPage(),
      ),
      
      // 创建房间
      GoRoute(
        path: '/rooms/create',
        builder: (context, state) => const CreateRoomPage(),
      ),
      
      // 房间详情
      GoRoute(
        path: '/rooms/:id',
        builder: (context, state) {
          final roomId = state.pathParameters['id']!;
          return RoomDetailPage(roomId: roomId);
        },
      ),
    ],
    redirect: (context, state) {
      if (settings.isLoading) {
        return null;
      }

      final value = settings.value;
      final hasServer = value?.hasServerUrl ?? false;
      final hasToken = value?.hasToken ?? false;

      final location = state.uri.toString();

      // 如果在 /setup 页面且已配置服务器，跳转到登录
      if (location == '/setup' && hasServer) {
        return '/login';
      }

      if (!hasServer && location != '/setup') {
        return '/setup';
      }

      if (hasServer && !hasToken &&
          location != '/login' &&
          location != '/register') {
        return '/login';
      }

      if (hasServer && hasToken &&
          (location == '/login' || location == '/register' || location == '/setup')) {
        return '/home';
      }

      return null;
    },
  );
});

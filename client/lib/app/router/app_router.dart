import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../features/auth/presentation/pages/server_setup_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/settings_page.dart';
import '../../features/room/presentation/pages/room_list_page.dart';
import '../../features/room/presentation/pages/room_detail_page.dart';
import '../../features/room/presentation/pages/room_settings_page.dart';
import '../../features/room/presentation/pages/create_room_page.dart';
import '../../features/user/presentation/pages/friends_page.dart';
import '../shell/app_shell.dart';
import '../theme/app_theme.dart';

/// Fade transition page used by all routes inside the shell.
CustomTransitionPage<void> _fadePage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: ValueKey('fade_${key.toString()}'),
    child: child,
    transitionDuration: AppTheme.durationPage,
    reverseTransitionDuration: AppTheme.durationPage,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: AppTheme.curveStandard,
        ),
        child: child,
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final settings = ref.watch(appSettingsProvider);

  return GoRouter(
    initialLocation: '/setup',
    routes: [
      // ─── Auth routes (outside Shell) ───────────────────
      GoRoute(
        path: '/setup',
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const ServerSetupPage(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _fadePage(
          key: state.pageKey,
          child: const RegisterPage(),
        ),
      ),

      // ─── Authenticated Shell ───────────────────────────
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.uri.toString(),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _fadePage(
              key: state.pageKey,
              child: const RoomListPage(),
            ),
          ),
          GoRoute(
            path: '/rooms/create',
            pageBuilder: (context, state) => _fadePage(
              key: state.pageKey,
              child: const CreateRoomPage(),
            ),
          ),
          GoRoute(
            path: '/rooms/:id',
            pageBuilder: (context, state) {
              final roomId = state.pathParameters['id']!;
              return _fadePage(
                key: state.pageKey,
                child: RoomDetailPage(roomId: roomId),
              );
            },
          ),
          GoRoute(
            path: '/rooms/:id/settings',
            pageBuilder: (context, state) {
              final roomId = state.pathParameters['id']!;
              return _fadePage(
                key: state.pageKey,
                child: RoomSettingsPage(roomId: roomId),
              );
            },
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _fadePage(
              key: state.pageKey,
              child: const SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/friends',
            pageBuilder: (context, state) => _fadePage(
              key: state.pageKey,
              child: const FriendsPage(),
            ),
          ),
        ],
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

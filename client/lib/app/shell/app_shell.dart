import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/title_bar.dart';
import 'sidebar.dart';
import 'right_panel.dart';

/// The top-level shell for all authenticated routes.
///
/// Layout:
///   ┌─────────────────────────────────────────┐
///   │ TitleBar (38px, drag-to-move)           │
///   ├──────┬──────────────────────┬───────────┤
///   │ Side │    Main Content      │ RightPanel│
///   │ bar  │    (GoRouter child)  │ (optional)│
///   │220px │    Expanded          │  200px    │
///   └──────┴──────────────────────┴───────────┘
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    // Extract room ID from path like /rooms/123 or /rooms/123/settings
    final roomId = _extractRoomId(location);
    final showRightPanel = roomId != null && !location.endsWith('/settings');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ─── Title bar ───────────────────────────────────
          const TitleBar(title: 'NexusRoom'),

          // ─── Content area ────────────────────────────────
          Expanded(
            child: Row(
              children: [
                // ─── Left sidebar ────────────────────────
                const Sidebar(),

                // ─── Main content ────────────────────────
                // GoRouter's CustomTransitionPage already provides
                // fade transitions. No AnimatedSwitcher here — having
                // both causes old & new pages to coexist in the tree,
                // leading to Duplicate GlobalKey crashes when both
                // reference the same VideoTrackRenderer.
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(location),
                    child: child,
                  ),
                ),

                // ─── Right panel (member list) ───────────
                if (showRightPanel)
                  AnimatedContainer(
                    duration: AppTheme.durationPage,
                    curve: AppTheme.curveMovement,
                    child: RightPanel(roomId: roomId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Extract roomId from routes like `/rooms/42` or `/rooms/42/settings`.
  String? _extractRoomId(String location) {
    final match = RegExp(r'^/rooms/(\d+)').firstMatch(location);
    return match?.group(1);
  }
}

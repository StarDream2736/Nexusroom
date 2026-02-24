import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';

/// Custom macOS-style title bar with traffic-light window controls and drag area.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key, this.title});

  final String? title;

  static const double height = 38.0;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () async {
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
        _checkMaximized();
      },
      child: DragToMoveArea(
        child: Container(
          height: TitleBar.height,
          color: AppColors.titleBar,
          child: Row(
            children: [
              const SizedBox(width: 12),
              // ─── Traffic-light buttons ──────────────────
              _TrafficButton(
                color: AppColors.trafficClose,
                icon: Icons.close,
                onTap: () => windowManager.close(),
              ),
              const SizedBox(width: 8),
              _TrafficButton(
                color: AppColors.trafficMinimize,
                icon: Icons.remove,
                onTap: () => windowManager.minimize(),
              ),
              const SizedBox(width: 8),
              _TrafficButton(
                color: AppColors.trafficMaximize,
                icon: _isMaximized ? Icons.fullscreen_exit : Icons.fullscreen,
                onTap: () async {
                  if (_isMaximized) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                  _checkMaximized();
                },
              ),
              const SizedBox(width: 16),
              // ─── Title ─────────────────────────────────
              if (widget.title != null)
                Text(
                  widget.title!,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small circular "traffic light" window-control button (macOS-style).
class _TrafficButton extends StatefulWidget {
  const _TrafficButton({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_TrafficButton> createState() => _TrafficButtonState();
}

class _TrafficButtonState extends State<_TrafficButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
          child: _hovered
              ? Icon(widget.icon,
                  size: 9, color: Colors.black.withOpacity(0.6))
              : null,
        ),
      ),
    );
  }
}

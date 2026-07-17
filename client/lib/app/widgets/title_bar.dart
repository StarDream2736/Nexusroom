import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Compact desktop title bar with a large drag region and conventional controls.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key, this.title});

  final String? title;

  static const double height = 40;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _refreshWindowState();
  }

  Future<void> _refreshWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  Future<void> _toggleMaximized() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _refreshWindowState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: TitleBar.height,
      decoration: BoxDecoration(
        color: AppColors.titleBar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _toggleMaximized,
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.forum_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        widget.title ?? 'NexusRoom',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _WindowButton(
            icon: Icons.remove,
            tooltip: '最小化',
            onTap: windowManager.minimize,
          ),
          _WindowButton(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            tooltip: _isMaximized ? '还原' : '最大化',
            onTap: _toggleMaximized,
          ),
          _WindowButton(
            icon: Icons.close,
            tooltip: '关闭',
            isClose: true,
            onTap: windowManager.close,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor =
        widget.isClose ? const Color(0xFFC94A52) : AppColors.hoverOverlay;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppTheme.durationHover,
            width: 46,
            height: TitleBar.height,
            color: _hovered ? hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered && widget.isClose
                  ? Colors.white
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

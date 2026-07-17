import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Pointer-aware action surface without layout-shifting scale effects.
class HoverScaleCard extends StatefulWidget {
  const HoverScaleCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.hoverColor,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final EdgeInsetsGeometry? padding;

  @override
  State<HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<HoverScaleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppTheme.radiusButton;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.durationHover,
          curve: AppTheme.curveStandard,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.hoverColor ?? context.colors.hoverOverlay)
                : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: _hovered ? context.colors.border : Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

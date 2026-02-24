import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A wrapper that adds macOS-style hover scale + background brighten effects.
///
/// Wrap any child to get:
///   - Scale 1.02 on hover
///   - Subtle background highlight
///   - 150 ms easeOutCubic animation
class HoverScaleCard extends StatefulWidget {
  const HoverScaleCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.hoverColor,
    this.scaleFactor = 1.02,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final double scaleFactor;
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
        child: AnimatedScale(
          scale: _hovered ? widget.scaleFactor : 1.0,
          duration: AppTheme.durationHover,
          curve: AppTheme.curveStandard,
          child: AnimatedContainer(
            duration: AppTheme.durationHover,
            curve: AppTheme.curveStandard,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.hoverColor ?? AppColors.hoverOverlay)
                  : Colors.transparent,
              borderRadius: radius,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

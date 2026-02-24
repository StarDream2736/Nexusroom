import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A frosted-glass container — wraps its child behind a blur layer.
///
/// Used for the sidebar, floating panels, and auth-page cards.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.color,
    this.opacity = 0.9,
    this.blurSigma = 20.0,
    this.border,
    this.width,
    this.height,
    this.constraints,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double opacity;
  final double blurSigma;
  final BoxBorder? border;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppTheme.radiusStandard;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          constraints: constraints,
          padding: padding,
          decoration: BoxDecoration(
            color: (color ?? AppColors.sidebar).withOpacity(opacity),
            borderRadius: radius,
            border: border ?? Border.all(color: AppColors.border, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

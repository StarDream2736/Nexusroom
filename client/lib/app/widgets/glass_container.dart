import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shared panel surface. The historical name is kept to avoid noisy call-site
/// churn, but the component now renders an opaque, restrained desktop panel.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.color,
    this.border,
    this.width,
    this.height,
    this.constraints,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BoxBorder? border;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppTheme.radiusStandard;

    return Container(
      width: width,
      height: height,
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.cardActive,
        borderRadius: radius,
        border: border ?? Border.all(color: AppColors.border, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

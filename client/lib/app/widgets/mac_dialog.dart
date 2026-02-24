import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A macOS-style dialog that replaces the standard Material [AlertDialog].
///
/// Rounded corners (12), subtle border, dark glass background.
/// Pass [content] for a plain text message, or [contentWidget] for custom UI.
Future<T?> showMacDialog<T>({
  required BuildContext context,
  required String title,
  String? content,
  Widget? contentWidget,
  List<Widget>? actions,
}) {
  return showDialog<T>(
    context: context,
    useRootNavigator: false,
    builder: (context) => _MacDialog(
      title: title,
      content: content,
      contentWidget: contentWidget,
      actions: actions,
    ),
  );
}

class _MacDialog extends StatelessWidget {
  const _MacDialog({
    required this.title,
    this.content,
    this.contentWidget,
    this.actions,
  });

  final String title;
  final String? content;
  final Widget? contentWidget;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebar,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radiusStandard,
        side: AppTheme.subtleBorder,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (content != null) ...[
                const SizedBox(height: 16),
                Text(content!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    )),
              ],
              if (contentWidget != null) ...[
                const SizedBox(height: 16),
                contentWidget!,
              ],
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions![i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

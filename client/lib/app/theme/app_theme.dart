import 'package:flutter/material.dart';

import 'app_colors.dart';

/// NexusRoom — macOS-inspired dark theme.
///
/// Design language: "Deep Gray & Glass", Apple HIG-inspired.
/// All corners rounded, elevation zero, subtle white-opacity borders.
class AppTheme {
  // Legacy references kept for any existing hard-coded usage.
  static const Color primaryColor = AppColors.primary;
  static const Color secondaryColor = AppColors.secondary;
  static const Color accentColor = AppColors.accent;
  static const Color darkBackground = AppColors.background;
  static const Color darkSurface = AppColors.sidebar;
  static const Color darkCard = AppColors.cardActive;
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color success = AppColors.success;
  static const Color warning = AppColors.warning;
  static const Color error = AppColors.error;
  static const Color info = AppColors.info;

  // ─── Border helpers ────────────────────────────────────────
  static BorderSide get subtleBorder =>
      BorderSide(color: AppColors.border, width: 1);

  static Border get subtleBorderAll =>
      Border.all(color: AppColors.border, width: 1);

  // ─── Radius tokens ────────────────────────────────────────
  static final BorderRadius radiusStandard = BorderRadius.circular(12.0);
  static final BorderRadius radiusButton = BorderRadius.circular(8.0);
  static final BorderRadius radiusBubble = BorderRadius.circular(16.0);
  static final BorderRadius radiusSmall = BorderRadius.circular(6.0);

  // ─── Animation constants ──────────────────────────────────
  static const Duration durationPage = Duration(milliseconds: 300);
  static const Duration durationHover = Duration(milliseconds: 150);
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveMovement = Curves.easeOutQuart;

  // ─── Dark Theme ───────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.sidebar,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.sidebar,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),

      // ─── AppBar ──────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: AppColors.textSecondary,
          size: 20,
        ),
      ),

      // ─── Card ────────────────────────────────────────────
      cardTheme: CardTheme(
        color: AppColors.cardActive,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radiusStandard,
          side: subtleBorder,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),

      // ─── Dialog ──────────────────────────────────────────
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.sidebar,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radiusStandard,
          side: subtleBorder,
        ),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ─── Input ───────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: subtleBorder,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),

      // ─── Elevated Button ─────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),

      // ─── Outlined Button ─────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: subtleBorder,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),

      // ─── Text Button ─────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),

      // ─── Icon Button ─────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
        ),
      ),

      // ─── ListTile ────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: radiusButton),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minLeadingWidth: 24,
        tileColor: Colors.transparent,
        textColor: AppColors.textPrimary,
        iconColor: AppColors.textSecondary,
      ),

      // ─── Divider ─────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      // ─── Tooltip ─────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.cardHover,
          borderRadius: radiusSmall,
          border: subtleBorderAll,
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),

      // ─── Snackbar ────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardHover,
        contentTextStyle:
            TextStyle(color: AppColors.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: radiusButton),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ─── Scrollbar ───────────────────────────────────────
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withOpacity(0.25);
          }
          return Colors.white.withOpacity(0.12);
        }),
      ),

      // ─── Tab ─────────────────────────────────────────────
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.circular(1),
        ),
      ),

      // ─── Switch ──────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.cardHover),
        trackOutlineColor:
            WidgetStateProperty.all(Colors.transparent),
      ),

      // ─── Progress Indicator ──────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      // ─── Text Selection ──────────────────────────────────
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withOpacity(0.3),
        selectionHandleColor: AppColors.primary,
      ),
    );
  }

  // ─── Light Theme (fallback — not actively used) ─────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        error: AppColors.error,
      ),
    );
  }
}

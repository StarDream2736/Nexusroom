import 'package:flutter/material.dart';

import 'app_colors.dart';

/// NexusRoom desktop design system: compact controls, layered work surfaces,
/// quiet borders and short motion curves.
class AppTheme {
  static BorderSide subtleBorder(NexusColors colors) =>
      BorderSide(color: colors.border, width: 1);
  static Border subtleBorderAll(NexusColors colors) =>
      Border.all(color: colors.border);

  static final BorderRadius radiusStandard = BorderRadius.circular(10);
  static final BorderRadius radiusButton = BorderRadius.circular(8);
  static final BorderRadius radiusBubble = BorderRadius.circular(12);
  static final BorderRadius radiusSmall = BorderRadius.circular(6);

  static const Duration durationPage = Duration(milliseconds: 180);
  static const Duration durationHover = Duration(milliseconds: 120);
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveMovement = Curves.easeOutQuart;

  static ThemeData forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = NexusColors.forBrightness(brightness);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.secondary,
      onSecondary: colors.onPrimary,
      error: colors.error,
      onError: Colors.white,
      surface: colors.sidebar,
      onSurface: colors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.sidebar,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
      colorScheme: scheme,
      extensions: [colors],
      fontFamily: 'Segoe UI Variable',
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: colors.textPrimary,
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: TextStyle(
          color: colors.textMuted,
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.7,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: colors.textSecondary, size: 20),
      ),
      cardTheme: CardTheme(
        color: colors.cardActive,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radiusStandard,
          side: subtleBorder(colors),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: colors.sidebar,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radiusStandard,
          side: subtleBorder(colors),
        ),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: subtleBorder(colors),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: BorderSide(color: colors.borderFocused, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusButton,
          borderSide: BorderSide(color: colors.error),
        ),
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          disabledBackgroundColor: colors.cardHover,
          disabledForegroundColor: colors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: subtleBorder(colors),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: radiusButton),
        ),
      ),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 18),
      listTileTheme: ListTileThemeData(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: radiusButton),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minLeadingWidth: 24,
        tileColor: Colors.transparent,
        textColor: colors.textPrimary,
        iconColor: colors.textSecondary,
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.cardHover,
          borderRadius: radiusSmall,
          border: subtleBorderAll(colors),
        ),
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.cardHover,
        contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: radiusButton),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.cardActive,
        elevation: 0,
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: radiusStandard,
          side: subtleBorder(colors),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.cardActive),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(subtleBorder(colors)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radiusStandard),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: subtleBorder(colors),
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.primary
                : Colors.transparent),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.cardHover,
        selectedColor: colors.selectedOverlay,
        disabledColor: colors.cardHover,
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
        secondaryLabelStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
        side: subtleBorder(colors),
        shape: RoundedRectangleBorder(borderRadius: radiusButton),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final opacity = states.contains(WidgetState.hovered) ? 0.28 : 0.14;
          return (dark ? Colors.white : Colors.black).withOpacity(opacity);
        }),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textSecondary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colors.textPrimary, width: 2),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.onPrimary
                : colors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? colors.primary
                : colors.cardHover),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? colors.primary
                  : colors.inputFill),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? colors.onPrimary
                  : colors.textSecondary),
          side: WidgetStateProperty.all(subtleBorder(colors)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: radiusButton),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.textPrimary,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.textPrimary,
        selectionColor: colors.textPrimary.withOpacity(0.25),
        selectionHandleColor: colors.textPrimary,
      ),
    );
  }
}

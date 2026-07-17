import 'package:flutter/material.dart';

/// Theme-scoped color tokens. Widgets resolve these through [BuildContext],
/// which guarantees that every mounted component reacts to a theme change.
@immutable
class NexusColors extends ThemeExtension<NexusColors> {
  const NexusColors({
    required this.background,
    required this.sidebar,
    required this.cardActive,
    required this.cardHover,
    required this.titleBar,
    required this.inputFill,
    required this.border,
    required this.borderFocused,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryHover,
    required this.secondary,
    required this.accent,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.selectedOverlay,
    required this.shadow,
  });

  final Color background;
  final Color sidebar;
  final Color cardActive;
  final Color cardHover;
  final Color titleBar;
  final Color inputFill;
  final Color border;
  final Color borderFocused;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color primary;
  final Color primaryHover;
  final Color secondary;
  final Color accent;
  final Color onPrimary;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color hoverOverlay;
  final Color pressedOverlay;
  final Color selectedOverlay;
  final Color shadow;

  static const dark = NexusColors(
    background: Color(0xFF0E0E0E),
    sidebar: Color(0xFF141414),
    cardActive: Color(0xFF191919),
    cardHover: Color(0xFF222222),
    titleBar: Color(0xFF111111),
    inputFill: Color(0xFF171717),
    border: Color(0xFF2B2B2B),
    borderFocused: Color(0xFF686868),
    textPrimary: Color(0xFFF4F4F4),
    textSecondary: Color(0xFFB8B8B8),
    textMuted: Color(0xFF7C7C7C),
    primary: Color(0xFFF2F2F2),
    primaryHover: Color(0xFFD8D8D8),
    secondary: Color(0xFFA8A8A8),
    accent: Color(0xFFF2F2F2),
    onPrimary: Color(0xFF111111),
    success: Color(0xFF37A36A),
    warning: Color(0xFFC58A2A),
    error: Color(0xFFD65C65),
    info: Color(0xFFA8A8A8),
    hoverOverlay: Color(0x0FFFFFFF),
    pressedOverlay: Color(0x18FFFFFF),
    selectedOverlay: Color(0x20FFFFFF),
    shadow: Color(0x66000000),
  );

  static const light = NexusColors(
    background: Color(0xFFF5F5F3),
    sidebar: Color(0xFFFAFAF9),
    cardActive: Color(0xFFFFFFFF),
    cardHover: Color(0xFFEFEFEC),
    titleBar: Color(0xFFFAFAF9),
    inputFill: Color(0xFFFFFFFF),
    border: Color(0xFFDCDCD8),
    borderFocused: Color(0xFF777773),
    textPrimary: Color(0xFF181817),
    textSecondary: Color(0xFF565653),
    textMuted: Color(0xFF858580),
    primary: Color(0xFF1B1B1A),
    primaryHover: Color(0xFF353533),
    secondary: Color(0xFF666662),
    accent: Color(0xFF1B1B1A),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF278457),
    warning: Color(0xFFA86D18),
    error: Color(0xFFC44850),
    info: Color(0xFF666662),
    hoverOverlay: Color(0x0A000000),
    pressedOverlay: Color(0x14000000),
    selectedOverlay: Color(0x10000000),
    shadow: Color(0x18000000),
  );

  static NexusColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  NexusColors copyWith() => this;

  @override
  NexusColors lerp(covariant NexusColors? other, double t) {
    if (other == null) return this;
    return NexusColors(
      background: Color.lerp(background, other.background, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      cardActive: Color.lerp(cardActive, other.cardActive, t)!,
      cardHover: Color.lerp(cardHover, other.cardHover, t)!,
      titleBar: Color.lerp(titleBar, other.titleBar, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocused: Color.lerp(borderFocused, other.borderFocused, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryHover: Color.lerp(primaryHover, other.primaryHover, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
      pressedOverlay: Color.lerp(pressedOverlay, other.pressedOverlay, t)!,
      selectedOverlay: Color.lerp(selectedOverlay, other.selectedOverlay, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension NexusThemeContext on BuildContext {
  NexusColors get colors =>
      Theme.of(this).extension<NexusColors>() ?? NexusColors.dark;
}

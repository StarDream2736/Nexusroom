import 'package:flutter/material.dart';

/// Restrained dark palette used across the desktop client.
class AppColors {
  AppColors._();

  // ─── Backgrounds ───────────────────────────────────────────
  static const Color background = Color(0xFF0F1115);
  static const Color sidebar = Color(0xFF15181E);
  static const Color cardActive = Color(0xFF1A1E25);
  static const Color cardHover = Color(0xFF20252D);
  static const Color titleBar = Color(0xFF12151A);
  static const Color inputFill = Color(0xFF171B21);

  // ─── Borders & Separators ─────────────────────────────────
  static Color border = const Color(0xFF2A3039);
  static Color borderFocused = const Color(0xFF3A4553);

  // ─── Text ─────────────────────────────────────────────────
  static Color textPrimary = const Color(0xFFF2F4F7);
  static Color textSecondary = const Color(0xFFADB5C2);
  static Color textMuted = const Color(0xFF737D8C);

  // ─── Accent / Brand ───────────────────────────────────────
  static const Color primary = Color(0xFF5B8DEF);
  static const Color primaryHover = Color(0xFF76A0F2);
  static const Color secondary = Color(0xFF7A93C7);
  static const Color accent = Color(0xFF5B8DEF);

  // ─── Semantic ─────────────────────────────────────────────
  static const Color success = Color(0xFF56B887);
  static const Color warning = Color(0xFFD9A441);
  static const Color error = Color(0xFFE36D75);
  static const Color info = Color(0xFF6D9EEB);

  // ─── Hover / Interaction Overlays ─────────────────────────
  static Color hoverOverlay = const Color(0x0FFFFFFF);
  static Color pressedOverlay = const Color(0x17FFFFFF);
  static Color selectedOverlay = const Color(0x1A5B8DEF);
}

import 'package:flutter/material.dart';

/// NexusRoom macOS-style color palette — "Deep Gray & Glass"
class AppColors {
  AppColors._();

  // ─── Backgrounds ───────────────────────────────────────────
  static const Color background = Color(0xFF1E1E1E);
  static const Color sidebar = Color(0xFF252525);
  static const Color cardActive = Color(0xFF2C2C2C);
  static const Color cardHover = Color(0xFF323232);
  static const Color titleBar = Color(0xFF252525);
  static const Color inputFill = Color(0xFF2C2C2C);

  // ─── Borders & Separators ─────────────────────────────────
  static Color border = Colors.white.withOpacity(0.06);
  static Color borderFocused = Colors.white.withOpacity(0.12);

  // ─── Text ─────────────────────────────────────────────────
  static Color textPrimary = Colors.white.withOpacity(0.9);
  static Color textSecondary = Colors.white.withOpacity(0.6);
  static Color textMuted = Colors.white.withOpacity(0.35);

  // ─── Accent / Brand ───────────────────────────────────────
  static const Color primary = Color(0xFF6366F1);        // Indigo
  static const Color primaryHover = Color(0xFF818CF8);
  static const Color secondary = Color(0xFF8B5CF6);      // Violet
  static const Color accent = Color(0xFFEC4899);          // Pink

  // ─── Semantic ─────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── Hover / Interaction Overlays ─────────────────────────
  static Color hoverOverlay = Colors.white.withOpacity(0.05);
  static Color pressedOverlay = Colors.white.withOpacity(0.08);
  static Color selectedOverlay = Colors.white.withOpacity(0.10);

  // ─── macOS Traffic Light Colors ───────────────────────────
  static const Color trafficClose = Color(0xFFFF5F57);
  static const Color trafficMinimize = Color(0xFFFFBD2E);
  static const Color trafficMaximize = Color(0xFF28C840);
}

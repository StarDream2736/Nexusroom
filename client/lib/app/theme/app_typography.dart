import 'package:flutter/material.dart';

import 'app_colors.dart';

/// NexusRoom typography — system font, Apple HIG-inspired weights.
class AppTypography {
  AppTypography._();

  // ─── Sizes ────────────────────────────────────────────────
  static const double sizeH1 = 22.0;
  static const double sizeH2 = 18.0;
  static const double sizeH3 = 15.0;
  static const double sizeBody = 13.0;
  static const double sizeCaption = 11.0;
  static const double sizeMini = 10.0;

  // ─── Weights ──────────────────────────────────────────────
  static const FontWeight weightHeading = FontWeight.w600;
  static const FontWeight weightBody = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;

  // ─── Pre-built Styles ─────────────────────────────────────
  static TextStyle get h1 => TextStyle(
        fontSize: sizeH1,
        fontWeight: weightHeading,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      );

  static TextStyle get h2 => TextStyle(
        fontSize: sizeH2,
        fontWeight: weightHeading,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      );

  static TextStyle get h3 => TextStyle(
        fontSize: sizeH3,
        fontWeight: weightMedium,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => TextStyle(
        fontSize: sizeBody,
        fontWeight: weightBody,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodySecondary => TextStyle(
        fontSize: sizeBody,
        fontWeight: weightBody,
        color: AppColors.textSecondary,
      );

  static TextStyle get caption => TextStyle(
        fontSize: sizeCaption,
        fontWeight: weightBody,
        color: AppColors.textSecondary,
      );

  static TextStyle get sectionHeader => TextStyle(
        fontSize: sizeMini,
        fontWeight: weightHeading,
        color: AppColors.textMuted,
        letterSpacing: 0.8,
      );
}

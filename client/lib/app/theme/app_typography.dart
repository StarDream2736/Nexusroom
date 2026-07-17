import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  static const double sizeH1 = 24;
  static const double sizeH2 = 18;
  static const double sizeH3 = 14;
  static const double sizeBody = 13;
  static const double sizeCaption = 11;
  static const double sizeMini = 10;

  static const FontWeight weightHeading = FontWeight.w600;
  static const FontWeight weightBody = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;

  static TextStyle h1(BuildContext context) =>
      Theme.of(context).textTheme.headlineLarge!;
  static TextStyle h2(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!;
  static TextStyle h3(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!;
  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;
  static TextStyle bodySecondary(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: context.colors.textSecondary,
          );
  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;
  static TextStyle sectionHeader(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!;
}

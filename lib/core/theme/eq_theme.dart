import 'package:flutter/material.dart';

import 'eq_colours.dart';
import 'eq_typography.dart';

abstract class EqTheme {
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: EqTypography.fontFamily,
    scaffoldBackgroundColor: EqColours.white,
    primaryColor: EqColours.sky,
    colorScheme: const ColorScheme.light(
      primary: EqColours.sky,
      secondary: EqColours.deep,
      error: EqColours.error,
      surface: EqColours.white,
      onPrimary: EqColours.white,
      onSecondary: EqColours.white,
      onSurface: EqColours.ink,
      onError: EqColours.white,
    ),
    textTheme: const TextTheme(
      displayLarge: EqTypography.headingXL,
      headlineLarge: EqTypography.headingL,
      headlineMedium: EqTypography.headingM,
      bodyLarge: EqTypography.bodyL,
      bodyMedium: EqTypography.bodyM,
      labelMedium: EqTypography.label,
    ),
  );
}

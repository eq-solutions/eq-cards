import 'package:flutter/material.dart';

import 'eq_colours.dart';
import 'eq_typography.dart';

abstract class EqTheme {
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: EqTypography.fontFamily,
    scaffoldBackgroundColor: EqColours.bg,
    primaryColor: EqColours.sky,
    colorScheme: const ColorScheme.light(
      primary: EqColours.sky,
      secondary: EqColours.deep,
      error: EqColours.error,
      surface: EqColours.bg,
      onPrimary: EqColours.white,
      onSecondary: EqColours.white,
      onSurface: EqColours.ink,
      onError: EqColours.white,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
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

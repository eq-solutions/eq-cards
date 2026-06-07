import 'package:flutter/material.dart';

import 'eq_colours.dart';
import 'eq_tokens.dart';

abstract class EqTypography {
  static const String fontFamily = EqFontTokens.fontFamily;

  static const TextStyle headingXL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: EqFontTokens.bold,
    color: EqColours.ink,
  );

  static const TextStyle headingL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: EqFontTokens.bold,
    color: EqColours.ink,
  );

  static const TextStyle headingM = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: EqFontTokens.semi,
    color: EqColours.ink,
  );

  static const TextStyle bodyL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: EqFontTokens.regular,
    color: EqColours.ink,
    height: 1.4,
  );

  static const TextStyle bodyM = TextStyle(
    fontFamily: fontFamily,
    fontSize: EqFontTokens.md,
    fontWeight: EqFontTokens.regular,
    color: EqColours.ink,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: EqFontTokens.medium,
    color: EqColours.grey,
  );
}

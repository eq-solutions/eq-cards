import 'package:flutter/material.dart';

import 'eq_colours.dart';

abstract class EqTypography {
  static const fontFamily = 'PlusJakartaSans';

  static const TextStyle headingXL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: EqColours.ink,
  );

  static const TextStyle headingL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: EqColours.ink,
  );

  static const TextStyle headingM = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: EqColours.ink,
  );

  static const TextStyle bodyL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: EqColours.ink,
    height: 1.4,
  );

  static const TextStyle bodyM = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: EqColours.ink,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: EqColours.grey,
  );
}

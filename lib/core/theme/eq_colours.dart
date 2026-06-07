import 'package:flutter/material.dart';

import 'eq_tokens.dart';

// EqColours — Cards-facing colour API. Values delegate to the canonical
// EqColors constants in eq_tokens.dart (vendored from @eq-solutions/tokens).
// Keep this file as the single import across Cards; update eq_tokens.dart
// when the tokens package cuts a new release.
abstract class EqColours {
  // Brand
  static const Color sky   = EqColors.sky;
  static const Color deep  = EqColors.deep;
  static const Color ice   = EqColors.ice;
  static const Color ink   = EqColors.ink;
  static const Color grey  = EqColors.grey;
  static const Color white = EqColors.white;

  // Border
  static const Color border = EqColors.gray200;

  // Neutral
  static const Color gray200 = EqColors.gray200;

  // Status — text-weight canonical colours
  static const Color error   = EqColors.errorText;
  static const Color warning = EqColors.warningText;
  static const Color success = EqColors.successText;

  // Status backgrounds
  static const Color errorBg   = EqColors.errorBg;
  static const Color successBg = EqColors.successBg;
  static const Color warningBg = EqColors.warningBg;

  // Overlay
  static const Color overlayDark = EqColors.overlayDark;
}

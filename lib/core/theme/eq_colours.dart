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

  // Warm-sand surfaces (Direction D)
  static const Color bg          = EqColors.gray50;   // #F6F3EE — page bg
  static const Color surface     = EqColors.gray100;  // #EFEAE1 — elevated surface
  static const Color outlineSoft = EqColors.gray200;  // #E4DDD2 — card tile border
  static const Color outline     = EqColors.gray300;  // #D4CCBE — input border

  // Text greys
  static const Color g500 = EqColors.gray500;  // #6B7280 — secondary text
  static const Color g600 = EqColors.gray600;  // #4B5563 — primary text

  // Border (legacy alias — prefer outlineSoft for new code)
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

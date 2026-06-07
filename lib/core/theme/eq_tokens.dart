// Generated from @eq-solutions/tokens v1.3.1 (eq-design-tokens/tokens.dart).
// Do not edit manually — regenerate by running `npm run build` in the
// eq-design-tokens repo and copying the output here.
//
// TODO(royce): eq-design-tokens now has a pubspec.yaml — migrate to proper Flutter git dep:
//   eq_design_tokens:
//     git:
//       url: https://github.com/eq-solutions/eq-design-tokens
//       ref: v1.3.2
//
// Path A consolidation (2026-05-30):
// EqSpacingTokens and EqTypographyTokens were dead code (zero callsites outside
// this file). Removed. EqColors retained — eq_colours.dart delegates to it.
// EqRadius retained — no hand-written equivalent; adds genuine value.
// Barrel exports added so this file is the single theme import entry point.
// Typography consolidation is explicitly deferred — see cards-token-consolidation-2026-05-30.md.

import 'package:flutter/material.dart';

// Barrel export — hand-written spacing tokens (source of truth for app callsites).
// eq_spacing.dart has no imports so this is cycle-free.
export 'eq_spacing.dart';
// TODO(barrel): eq_typography.dart cannot be exported here — it imports eq_colours.dart
// which imports eq_tokens.dart, creating a circular export. Feature files must continue
// to import eq_typography.dart directly until that cycle is resolved (e.g. by removing
// the eq_colours.dart → eq_tokens.dart import and inlining EqColors into eq_colours.dart).

class EqColors {
  EqColors._();

  // Brand
  static const Color sky     = Color(0xFF3DA8D8);
  static const Color deep    = Color(0xFF2986B4);
  static const Color skyDeep = Color(0xFF2986B4);
  static const Color ice     = Color(0xFFEAF5FB);
  static const Color ink     = Color(0xFF1A1A2E);
  static const Color grey    = Color(0xFF666666);
  static const Color white   = Color(0xFFFFFFFF);
  static const Color amber     = Color(0xFFF59E0B);
  static const Color amberDeep = Color(0xFFB45309);
  static const Color slate     = Color(0xFF94A3B8);
  static const Color live      = Color(0xFF38BDF8);

  // Overlay
  static const Color overlayDark = Color(0xCC000000);

  // Accent — secondary warmth (clay). Brand decoration only (~5%), never status.
  static const Color clay     = Color(0xFFA8572B);
  static const Color clayDeep = Color(0xFF8A4521);
  static const Color clayBg   = Color(0xFFFBF1E9);

  // Neutral scale — Direction D warm-sand surfaces (50-300); text greys (400-600) stay neutral.
  static const Color gray50  = Color(0xFFF6F3EE);
  static const Color gray100 = Color(0xFFEFEAE1);
  static const Color gray200 = Color(0xFFE4DDD2);
  static const Color gray300 = Color(0xFFD4CCBE);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);

  // Status
  static const Color successBg   = Color(0xFFF0FDF4);
  static const Color successText = Color(0xFF15803D);
  static const Color warningBg   = Color(0xFFFFFBEB);
  static const Color warningText = Color(0xFFB45309);
  static const Color errorBg     = Color(0xFFFEF2F2);
  static const Color errorText   = Color(0xFFB91C1C);
}

class EqRadius {
  EqRadius._();
  static const double chip  = 4;
  static const double input = 6;
  static const double card  = 8;
  static const double shell = 12;
  static const double pill  = 9999;
}

// Font constants — size scale and weight aliases.
// Named EqFontTokens to avoid collision with abstract class EqTypography
// in eq_typography.dart (which provides named TextStyles for app callsites).
// Size steps don't align to the app's heading scale (32/24/20/17/15/13px)
// by design — alignment requires a design sign-off (deferred, 2026-05-30).
class EqFontTokens {
  EqFontTokens._();
  static const String fontFamily = 'PlusJakartaSans';
  static const double xs   = 11;
  static const double sm   = 12;
  static const double base = 14;
  static const double md   = 15;
  static const double lg   = 18;
  static const double xl   = 22;
  static const double xl2  = 28;
  static const double xl3  = 36;
  static const double xl4  = 48;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium  = FontWeight.w500;
  static const FontWeight semi    = FontWeight.w600;
  static const FontWeight bold    = FontWeight.w700;
  static const FontWeight black   = FontWeight.w800;
}

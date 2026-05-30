// Generated from @eq-solutions/tokens v1.0.0 (eq-design-tokens/tokens.dart).
// Do not edit manually — regenerate by running `npm run build` in the
// eq-design-tokens repo and copying the output here.
//
// ignore: flutter_style_todos
// TODO: once eq-design-tokens gains a pubspec.yaml, wire this as a proper Flutter git dep.
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
  static const Color sky   = Color(0xFF3DA8D8);
  static const Color deep  = Color(0xFF2986B4);
  static const Color ice   = Color(0xFFEAF5FB);
  static const Color ink   = Color(0xFF1A1A2E);
  static const Color grey  = Color(0xFF666666);
  static const Color white = Color(0xFFFFFFFF);

  // Neutral scale
  static const Color gray50  = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
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

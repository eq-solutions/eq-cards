import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analytics/analytics_service.dart';
import '../theme/eq_colours.dart';

/// **The wedge.** Every "Copy" action in the app goes through this function —
/// every field row on Profile and Licence detail screens, the bulk
/// "Copy all profile fields" button, every metadata row.
///
/// Three things happen in lockstep, atomic from the user's perspective:
///
/// 1. The value is written to the system clipboard.
/// 2. A light haptic tap fires (no-op on web — browsers don't expose haptics).
/// 3. A 1.2 s "{label} copied" snackbar appears at the bottom of the screen.
///
/// A `copy_field` analytics event is dispatched (fire-and-forget) with the
/// label as a property — this is the headline metric in §10.2 of the
/// architecture (≥ 5 copies / week / user is the "wedge works" signal).
///
/// **Do not write your own copy logic.** Consistency is the product here. If
/// this function needs to change (different toast duration, a different
/// haptic, an event name), it changes here once.
Future<void> copyWithFeedback({
  required BuildContext context,
  required String value,
  required String label,
}) async {
  bool copied = true;
  try {
    await Clipboard.setData(ClipboardData(text: value));
  } on PlatformException {
    copied = false;
  }
  await HapticFeedback.lightImpact();
  unawaited(AnalyticsService.track('copy_field', {'label': label}));

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(copied ? '$label copied' : 'Copy failed — try again'),
      duration: const Duration(milliseconds: 1200),
      behavior: SnackBarBehavior.floating,
      backgroundColor: EqColours.ink,
    ),
  );
}

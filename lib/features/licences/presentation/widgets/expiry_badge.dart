import 'package:flutter/material.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/utils/date_utils.dart';

/// Coloured pill that conveys licence-expiry urgency at a glance.
///
/// Visual bands match `AlertsScheduler` and architecture §10.2:
///
/// - Past expiry → red, "Expired"
/// - 0–7 days → red, "X days left"
/// - 8–30 days → orange, "X days left"
/// - 31–90 days → orange, "X days left"
/// - 91+ days → green, "Valid"
///
/// Accessibility: the visual colour band is meaningless to a screen reader,
/// so we set an explicit semantic label that surfaces the urgency in words.
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge({super.key, required this.expiry});

  final DateTime expiry;

  @override
  Widget build(BuildContext context) {
    final days = EqDates.daysUntil(expiry);
    final (background, label) = _styleFor(days);
    return Semantics(
      label: _semanticLabelFor(days),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.sm,
          vertical: EqSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: background.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: EqTypography.label.copyWith(
            color: background,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static (Color, String) _styleFor(int days) {
    if (days < 0) return (EqColours.error, 'Expired');
    if (days <= 7) return (EqColours.error, '$days days left');
    if (days <= 30) return (EqColours.warning, '$days days left');
    if (days <= 90) return (EqColours.warning, '$days days left');
    return (EqColours.success, 'Valid');
  }

  static String _semanticLabelFor(int days) {
    if (days < 0) return 'Licence expired';
    if (days == 0) return 'Licence expires today';
    if (days == 1) return 'Licence expires tomorrow';
    if (days <= 90) return 'Licence expires in $days days';
    return 'Licence valid';
  }
}

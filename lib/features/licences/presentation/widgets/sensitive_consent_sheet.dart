import 'package:flutter/material.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../data/sensitive_licence_types.dart';

/// Modal bottom sheet shown when a user selects a licence type that contains
/// sensitive information under the Australian Privacy Act 1988. Returns true
/// if the user consented, false/null if they cancelled.
class SensitiveConsentSheet extends StatelessWidget {
  const SensitiveConsentSheet({super.key, required this.category});

  final SensitiveCategory category;

  static Future<bool?> show(
      BuildContext context, SensitiveCategory category) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => SensitiveConsentSheet(category: category),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EqSpacing.md,
          EqSpacing.lg,
          EqSpacing.md,
          EqSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, color: EqColours.sky, size: 20),
                const SizedBox(width: EqSpacing.sm),
                Text('Sensitive information', style: EqTypography.headingM),
              ],
            ),
            const SizedBox(height: EqSpacing.xs),
            Text(
              category.displayName,
              style: EqTypography.label.copyWith(color: EqColours.sky),
            ),
            const SizedBox(height: EqSpacing.md),
            Text(
              category.consentDescription,
              style: EqTypography.bodyM.copyWith(height: 1.55),
            ),
            const SizedBox(height: EqSpacing.sm),
            Text(
              category.whatWeStore,
              style: EqTypography.bodyM.copyWith(
                color: const Color(0xFF555555),
                height: 1.55,
              ),
            ),
            const SizedBox(height: EqSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: EqColours.sky,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: EqSpacing.sm + 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('I understand and consent'),
            ),
            const SizedBox(height: EqSpacing.sm),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: EqSpacing.sm + 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: const BorderSide(color: EqColours.border),
                foregroundColor: EqColours.ink,
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

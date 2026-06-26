import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../presentation/screens/licence_edit_screen.dart';

const _kSiteEssentials = [
  _Suggestion('white_card', 'White Card'),
  _Suggestion('driver_licence', 'Driver Licence'),
  _Suggestion('working_at_heights', 'Working at Heights'),
  _Suggestion('first_aid', 'First Aid'),
  _Suggestion('forklift_hrwl', 'Forklift / HRWL'),
];

class _Suggestion {
  const _Suggestion(this.code, this.label);
  final String code;
  final String label;
}

/// Shows "Add to your site profile" chips for common credentials the worker
/// doesn't yet have. Hidden once the wallet has 6+ items or all 5 essentials.
class WalletCompletionNudge extends StatelessWidget {
  const WalletCompletionNudge({super.key, required this.existingTypeCodes});

  final Set<String> existingTypeCodes;

  @override
  Widget build(BuildContext context) {
    final missing = _kSiteEssentials
        .where((s) => !existingTypeCodes.contains(s.code))
        .toList();

    if (missing.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: EqSpacing.xs, bottom: EqSpacing.sm),
          child: Text('Add to your site profile', style: EqTypography.label),
        ),
        Wrap(
          spacing: EqSpacing.sm,
          runSpacing: EqSpacing.sm,
          children: missing
              .map((s) => _SuggestionChip(suggestion: s))
              .toList(),
        ),
        const SizedBox(height: EqSpacing.md),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion});
  final _Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(
        Routes.licenceCreate,
        extra: LicencePrefill(typeCode: suggestion.code),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.sm + 4,
          vertical: EqSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: EqColours.ice,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: EqColours.sky.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              suggestion.label,
              style: EqTypography.bodyS.copyWith(
                color: EqColours.deep,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.add, size: 14, color: EqColours.deep),
          ],
        ),
      ),
    );
  }
}

/// Inline suggestion tiles for the completely empty wallet.
/// Shown below the main CTA so the scan/upload flow stays primary.
class WalletEmptySuggestions extends StatelessWidget {
  const WalletEmptySuggestions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: EqSpacing.lg),
        Padding(
          padding: const EdgeInsets.only(bottom: EqSpacing.sm),
          child: Text(
            'Common for site workers',
            style: EqTypography.label,
            textAlign: TextAlign.center,
          ),
        ),
        ..._kSiteEssentials.take(4).map(
              (s) => _EmptySuggestionTile(suggestion: s),
            ),
      ],
    );
  }
}

class _EmptySuggestionTile extends StatelessWidget {
  const _EmptySuggestionTile({required this.suggestion});
  final _Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(
        Routes.licenceCreate,
        extra: LicencePrefill(typeCode: suggestion.code),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: EqSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.md,
          vertical: EqSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: EqColours.sky.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Text(
              suggestion.label,
              style: EqTypography.bodyS.copyWith(
                color: EqColours.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.arrow_forward,
              size: 14,
              color: EqColours.sky,
            ),
          ],
        ),
      ),
    );
  }
}

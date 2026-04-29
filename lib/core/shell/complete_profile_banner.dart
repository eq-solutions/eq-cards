import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/profile/profile.dart';
import '../router/routes.dart';
import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';

/// Shows a CTA banner when the current user's profile is missing or incomplete.
/// Lives in `core/shell/` because it composes information across features
/// (used on the Licences tab to point at the Profile tab).
class CompleteProfileBanner extends ConsumerWidget {
  const CompleteProfileBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(profileNotifierProvider);
    final shouldShow = asyncProfile.maybeWhen(
      data: (p) => p == null || !p.isComplete,
      orElse: () => false,
    );
    if (!shouldShow) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(EqSpacing.md),
      padding: const EdgeInsets.all(EqSpacing.md),
      decoration: BoxDecoration(
        color: EqColours.ice,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EqColours.sky, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: EqColours.deep),
          const SizedBox(width: EqSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your profile',
                  style: EqTypography.bodyL.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: EqSpacing.xs),
                Text(
                  'Tap-to-copy works once you have name, DOB, mobile, address and emergency contact saved.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.go(Routes.profileEdit),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }
}

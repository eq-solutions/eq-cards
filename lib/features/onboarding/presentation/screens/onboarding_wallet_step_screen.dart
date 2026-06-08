import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/invite/invite_context_provider.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../certificates/certificates.dart';
import '../../../licences/licences.dart';
import '../widgets/wizard_shell.dart';

class OnboardingWalletStepScreen extends ConsumerWidget {
  const OnboardingWalletStepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgName = ref.watch(initialOrgNameProvider);
    final licenceCount = ref.watch(licencesListNotifierProvider).value?.length ?? 0;
    final certCount = ref.watch(certificatesListNotifierProvider).value?.length ?? 0;
    final total = licenceCount + certCount;

    final bodyText = orgName != null
        ? 'Add your licences and certificates so $orgName has them on file. You can add more any time.'
        : 'Add your licences and certificates. You can always add more later.';

    return WizardShell(
      step: 3,
      totalSteps: 4,
      actionLabel: 'Continue',
      onAction: () => context.go(Routes.onboardingReview),
      onBack: () => context.go(Routes.onboardingProfile),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          EqSpacing.xl, EqSpacing.lg, EqSpacing.xl, EqSpacing.lg,
        ),
        children: [
          Text('Your wallet', style: EqTypography.headingL),
          const SizedBox(height: EqSpacing.sm),
          Text(bodyText, style: EqTypography.bodyM.copyWith(color: EqColours.g500)),
          const SizedBox(height: EqSpacing.xl),
          if (total > 0) ...[
            Text(
              '$total item${total == 1 ? '' : 's'} already in your wallet',
              style: EqTypography.label.copyWith(color: EqColours.g500),
            ),
            const SizedBox(height: EqSpacing.md),
          ],
          _AddTile(
            icon: Icons.credit_card_outlined,
            label: 'Add a licence',
            onTap: () {
              unawaited(context.push(Routes.licenceCreate));
            },
          ),
          const SizedBox(height: EqSpacing.sm),
          _AddTile(
            icon: Icons.workspace_premium_outlined,
            label: 'Add a certificate',
            onTap: () {
              unawaited(context.push(Routes.certificateCreate));
            },
          ),
          const SizedBox(height: EqSpacing.lg),
          Text(
            "You can skip this for now and add items from the Wallet screen once you're set up.",
            style: EqTypography.label.copyWith(color: EqColours.g500),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: EqSpacing.md,
          vertical: EqSpacing.md,
        ),
        decoration: BoxDecoration(
          color: EqColours.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EqColours.outlineSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: EqColours.ice,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: EqColours.sky),
            ),
            const SizedBox(width: EqSpacing.md),
            Expanded(
              child: Text(
                label,
                style: EqTypography.bodyM.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: EqColours.g500),
          ],
        ),
      ),
    );
  }
}

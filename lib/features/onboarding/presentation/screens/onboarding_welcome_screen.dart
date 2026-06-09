import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/invite/invite_context_provider.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../profile/presentation/notifiers/profile_notifier.dart';
import '../widgets/wizard_shell.dart';

class OnboardingWelcomeScreen extends ConsumerWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgName = ref.watch(initialOrgNameProvider);
    final firstName = ref
        .watch(profileNotifierProvider)
        .value
        ?.fullName
        ?.split(' ')
        .firstOrNull;

    final headline = firstName != null
        ? 'Welcome aboard,\n$firstName.'
        : orgName != null
            ? 'Welcome to $orgName'
            : 'Welcome to EQ Cards';

    final subline = orgName != null
        ? "Let's get your profile set up so $orgName has what they need."
        : 'Takes about 2 minutes — fill in once, tap to copy onto any induction form.';

    return WizardShell(
      step: 1,
      totalSteps: 4,
      actionLabel: 'Get started',
      onAction: () => context.go(Routes.onboardingProfile),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EqSpacing.xl,
            vertical: EqSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(headline, style: EqTypography.headingXL),
              const SizedBox(height: EqSpacing.md),
              Text(
                subline,
                style: EqTypography.bodyL.copyWith(color: EqColours.g500),
              ),
              const SizedBox(height: EqSpacing.xl),
              _ValueProp(
                icon: Icons.person_outline_rounded,
                text: 'Fill in your details once',
              ),
              const SizedBox(height: EqSpacing.md),
              _ValueProp(
                icon: Icons.wallet_outlined,
                text: 'Add your licences and certificates',
              ),
              const SizedBox(height: EqSpacing.md),
              _ValueProp(
                icon: Icons.verified_outlined,
                text: 'Share verifiable records with site managers',
              ),
              const SizedBox(height: EqSpacing.xl),
              _DataDisclosure(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueProp extends StatelessWidget {
  const _ValueProp({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: EqColours.ice,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: EqColours.sky),
        ),
        const SizedBox(width: EqSpacing.md),
        Expanded(
          child: Text(text, style: EqTypography.bodyM),
        ),
      ],
    );
  }
}

/// Lightweight data disclosure shown before onboarding starts.
/// Satisfies Australian Privacy Act obligations around overseas disclosure.
class _DataDisclosure extends StatelessWidget {
  const _DataDisclosure();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your data is stored in Australia. Analytics and error '
          'reporting may use services in the EU.',
          style: EqTypography.label.copyWith(color: EqColours.g500),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => context.push(Routes.privacyPolicy),
          child: Text(
            'Privacy Policy',
            style: EqTypography.label.copyWith(
              color: EqColours.sky,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

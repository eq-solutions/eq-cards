import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../profile/presentation/notifiers/profile_notifier.dart';

class OnboardingDoneScreen extends ConsumerWidget {
  const OnboardingDoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = ref
        .watch(profileNotifierProvider)
        .value
        ?.fullName
        ?.split(' ')
        .firstOrNull;

    final headline =
        firstName != null ? "You're all set, $firstName." : "You're all set.";

    return Scaffold(
      backgroundColor: EqColours.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.lg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Confirmation mark
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: EqColours.ice,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 44,
                      color: EqColours.sky,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  Text(
                    headline,
                    style: EqTypography.headingXL,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  Text(
                    'Your profile is complete. Head to your wallet to add more licences and certificates any time.',
                    style: EqTypography.bodyL.copyWith(color: EqColours.g500),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  EqButton(
                    label: 'Go to my wallet',
                    onPressed: () => context.go(Routes.licencesList),
                    fullWidth: true,
                  ),
                  const SizedBox(height: EqSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

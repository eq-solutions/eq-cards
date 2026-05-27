import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';

class OnboardingDoneScreen extends StatelessWidget {
  const OnboardingDoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.white,
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
                  // Check circle
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
                    "You're all set",
                    style: EqTypography.headingXL,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  Text(
                    'Your profile is complete. Add your licences and certificates to build your wallet.',
                    style: EqTypography.bodyL.copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  EqButton(
                    label: 'Add my first licence',
                    onPressed: () => context.go(Routes.licencesList),
                    fullWidth: true,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => context.go(Routes.licencesList),
                      child: Text(
                        'Go to my wallet',
                        style: EqTypography.bodyM.copyWith(
                          color: EqColours.grey,
                        ),
                      ),
                    ),
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

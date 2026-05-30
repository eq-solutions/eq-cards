import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/invite/invite_context_provider.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';

class OnboardingWelcomeScreen extends ConsumerWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgName = ref.watch(initialOrgNameProvider);

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // EQ mark — small brand anchor at top
                  Image.asset(
                    'assets/icon/launcher_foreground.png',
                    width: 40,
                    height: 40,
                    color: EqColours.sky,
                    colorBlendMode: BlendMode.srcIn,
                    errorBuilder: (_, _, _) => Text(
                      'EQ',
                      style: EqTypography.headingM.copyWith(
                        color: EqColours.sky,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Headline — org-branded when invite context present
                  Text(
                    orgName != null
                        ? '$orgName wants you to set up your wallet'
                        : 'Welcome to EQ Cards',
                    style: EqTypography.headingXL,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  Text(
                    orgName != null
                        ? 'Sign in with the email address they have on file and your details will connect automatically.'
                        : 'Fill your details once. Tap to copy them onto any induction form.',
                    style: EqTypography.bodyL.copyWith(color: EqColours.grey),
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  // Value props — only shown on generic (non-invite) welcome
                  if (orgName == null) ...[
                    _ValueProp(
                      icon: Icons.wallet_outlined,
                      text: 'Licences and certificates in one place',
                    ),
                    const SizedBox(height: EqSpacing.md),
                    _ValueProp(
                      icon: Icons.flash_on_outlined,
                      text: 'One-tap copy onto any induction form',
                    ),
                    const SizedBox(height: EqSpacing.md),
                    _ValueProp(
                      icon: Icons.verified_outlined,
                      text: 'Share verifiable records with site managers',
                    ),
                    const SizedBox(height: EqSpacing.xl),
                  ],
                  const Spacer(),
                  EqButton(
                    label: 'Get started',
                    onPressed: () => context.go(Routes.onboardingProfile),
                    fullWidth: true,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => context.go(Routes.licencesList),
                      child: Text(
                        "I'll do this later",
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

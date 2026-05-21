import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({super.key});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final _controller = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim().toLowerCase();
    final err = validateEmail(raw);
    if (raw.isEmpty || err != null) {
      setState(() => _validationError = err ?? 'Enter your email address');
      return;
    }
    setState(() => _validationError = null);

    final notifier = ref.read(authFlowNotifierProvider.notifier);
    await notifier.sendOtp(raw);

    if (!mounted) return;
    final state = ref.read(authFlowNotifierProvider);
    if (state is AuthFlowAwaitingOtp) {
      unawaited(context.push(Routes.otp, extra: raw));
    }
  }

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(authFlowNotifierProvider);
    final isLoading = flowState is AuthFlowSendingOtp;
    final errorText = flowState is AuthFlowError
        ? flowState.message
        : _validationError;

    return Scaffold(
      backgroundColor: EqColours.white,
      // Use a scrolling layout so the form survives a software keyboard
      // popping up on short phones and the collection-notice doesn't tip
      // the Column past the viewport on the smallest test/iPhone SE sizes.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(EqSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: EqSpacing.xxl),
              // EQ launcher mark — first-impression branding on the only
              // screen an unsigned-in user sees.
              Center(
                child: Image.asset(
                  'assets/icon/launcher.png',
                  width: 80,
                  height: 80,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: EqSpacing.md),
              Center(
                child: Text(
                  'EQ Cards',
                  style: EqTypography.headingL.copyWith(
                    fontWeight: FontWeight.w700,
                    color: EqColours.deep,
                  ),
                ),
              ),
              const SizedBox(height: EqSpacing.xs),
              Center(
                child: Text(
                  'Your tradie wallet.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                ),
              ),
              const SizedBox(height: EqSpacing.xxl),
              Text("What's your email?", style: EqTypography.headingL),
              const SizedBox(height: EqSpacing.sm),
              Text(
                "We'll send you a 6-digit code to sign in. New accounts are "
                'created on first sign-in.',
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
              const SizedBox(height: EqSpacing.xl),
              EqTextField(
                controller: _controller,
                label: 'Email address',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                errorText: errorText,
                autofocus: true,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (!isLoading) unawaited(_submit());
                },
              ),
              const SizedBox(height: EqSpacing.xl),
              EqButton(
                label: 'Send code',
                onPressed: isLoading ? null : _submit,
                isLoading: isLoading,
                fullWidth: true,
              ),
              const SizedBox(height: EqSpacing.md),
              // Privacy Act collection notice — surfaced at the point of
              // sign-up so the user can review what we collect and what
              // we do with it before creating an account.
              Center(
                child: _LegalLinks(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = EqTypography.label.copyWith(color: EqColours.grey);
    final link = EqTypography.label.copyWith(
      color: EqColours.deep,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'By continuing you agree to our ', style: base),
          TextSpan(
            text: 'Privacy Policy',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push(Routes.privacyPolicy),
          ),
          TextSpan(text: ' and ', style: base),
          TextSpan(
            text: 'Terms of Use',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => context.push(Routes.termsOfUse),
          ),
          TextSpan(text: '.', style: base),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

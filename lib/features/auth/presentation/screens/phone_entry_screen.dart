import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../data/aus_phone.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _controller = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _controller.text;
    final normalised = normaliseAusMobile(raw);
    if (normalised == null || !isValidAusMobile(normalised)) {
      setState(() => _validationError = 'Enter a valid Australian mobile');
      return;
    }
    setState(() => _validationError = null);

    final notifier = ref.read(authFlowNotifierProvider.notifier);
    await notifier.sendOtp(normalised);

    if (!mounted) return;
    final state = ref.read(authFlowNotifierProvider);
    if (state is AuthFlowAwaitingOtp) {
      unawaited(context.push(Routes.otp, extra: normalised));
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
      body: SafeArea(
        child: Padding(
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
              Text("What's your mobile?", style: EqTypography.headingL),
              const SizedBox(height: EqSpacing.sm),
              Text(
                "We'll send you a code to sign in.",
                style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              ),
              const SizedBox(height: EqSpacing.xl),
              EqTextField(
                controller: _controller,
                label: 'Mobile number',
                hint: '0412 345 678',
                keyboardType: TextInputType.phone,
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
            ],
          ),
        ),
      ),
    );
  }
}

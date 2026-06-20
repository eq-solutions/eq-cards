import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../data/aus_phone.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({super.key});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  bool _useEmail = false;
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitPhone() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final phone = normaliseAusMobile(_phoneController.text.trim())!;
    await ref.read(authFlowNotifierProvider.notifier).sendPhoneOtp(phone);
  }

  Future<void> _submitEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    await ref
        .read(authFlowNotifierProvider.notifier)
        .sendOtp(_emailController.text.trim());
  }

  void _toggleMode() {
    setState(() => _useEmail = !_useEmail);
    ref.read(authFlowNotifierProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authFlowNotifierProvider, (_, next) {
      if (next is AuthFlowAwaitingOtp) {
        unawaited(context.push(Routes.otp));
      }
    });

    final flowState = ref.watch(authFlowNotifierProvider);
    final isLoading = flowState is AuthFlowSendingOtp;
    final error = flowState is AuthFlowError ? flowState.message : null;

    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: EqSpacing.xl),

                  // ── Brand ────────────────────────────────────────────────
                  Image.asset(
                    'assets/icon/launcher.png',
                    width: 80,
                    height: 80,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    'Sign in to EQ Cards',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.xs),
                  Text(
                    _useEmail
                        ? "We'll send a code to your email address."
                        : "We'll send a code to your mobile number.",
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  ),

                  const SizedBox(height: EqSpacing.xl),

                  // ── Input ────────────────────────────────────────────────
                  if (!_useEmail)
                    Form(
                      key: _phoneFormKey,
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        autocorrect: false,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => unawaited(_submitPhone()),
                        decoration: const InputDecoration(
                          labelText: 'Mobile number',
                          hintText: '0412 345 678',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter your mobile number';
                          }
                          final phone = normaliseAusMobile(v.trim());
                          if (phone == null || !isValidAusMobile(phone)) {
                            return 'Enter a valid Australian mobile number';
                          }
                          return null;
                        },
                      ),
                    )
                  else
                    Form(
                      key: _emailFormKey,
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => unawaited(_submitEmail()),
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          hintText: 'you@example.com',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter your email address';
                          }
                          return validateEmail(v);
                        },
                      ),
                    ),

                  // ── Error ────────────────────────────────────────────────
                  if (error != null) ...[
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      error,
                      style:
                          EqTypography.label.copyWith(color: EqColours.error),
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    const SizedBox(height: EqSpacing.sm),

                  // ── Send code ────────────────────────────────────────────
                  FilledButton(
                    onPressed: isLoading
                        ? null
                        : () => unawaited(
                              _useEmail ? _submitEmail() : _submitPhone(),
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: EqColours.sky,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: isLoading
                        ? const _LoadingSpinner()
                        : const Text('Send code'),
                  ),

                  const SizedBox(height: EqSpacing.lg),

                  // ── Mode toggle ──────────────────────────────────────────
                  Center(
                    child: TextButton(
                      onPressed: _toggleMode,
                      child: Text(
                        _useEmail
                            ? 'Use mobile instead'
                            : 'Use email instead',
                        style:
                            EqTypography.bodyM.copyWith(color: EqColours.sky),
                      ),
                    ),
                  ),

                  const SizedBox(height: EqSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
}

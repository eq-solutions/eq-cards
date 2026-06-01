import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Captured from the first AuthFlowAwaitingOtp state we see.
  // Preserved through error/verifying transitions so retries don't
  // call verifyOtp with an empty identifier.
  String _identifier = '';
  bool _isPhone = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authFlowNotifierProvider.notifier);
    if (_isPhone) {
      await notifier.verifyPhoneOtp(_identifier, _codeController.text);
    } else {
      await notifier.verifyOtp(_identifier, _codeController.text);
    }
  }

  Future<void> _resend() async {
    _codeController.clear();
    final notifier = ref.read(authFlowNotifierProvider.notifier);
    if (_isPhone) {
      await notifier.sendPhoneOtp(_identifier);
    } else {
      await notifier.sendOtp(_identifier);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(authFlowNotifierProvider);

    // Capture identifier the moment we land in awaiting state — persists through
    // error/verifying so retries always have the correct address.
    if (flowState is AuthFlowAwaitingOtp && _identifier.isEmpty) {
      _identifier = flowState.displayTarget;
      _isPhone = flowState.isPhone;
    }

    // Clear code exactly once on error transition.
    ref.listen<AuthFlowState>(authFlowNotifierProvider, (_, next) {
      if (next is AuthFlowError) _codeController.clear();
    });


    // Safety: if state is no longer in an OTP-related phase (e.g. stale
    // navigation after app restart), go back to email entry.
    if (flowState is! AuthFlowAwaitingOtp &&
        flowState is! AuthFlowVerifying &&
        flowState is! AuthFlowError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.email);
      });
      return const Scaffold(backgroundColor: EqColours.white);
    }

    final isLoading = flowState is AuthFlowVerifying;
    final error = flowState is AuthFlowError ? flowState.message : null;
    final isSending = flowState is AuthFlowSendingOtp;

    return Scaffold(
      backgroundColor: EqColours.white,
      appBar: AppBar(
        backgroundColor: EqColours.white,
        elevation: 0,
        leading: BackButton(
          color: EqColours.ink,
          onPressed: () {
            ref.read(authFlowNotifierProvider.notifier).reset();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(EqSpacing.xl),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Enter your code',
                      style: EqTypography.headingL.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EqColours.deep,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      _identifier.isNotEmpty
                          ? 'We sent a 6-digit code to $_identifier.'
                          : 'We sent you a 6-digit sign-in code.',
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.xl),
                    TextFormField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      style: EqTypography.headingM.copyWith(
                        letterSpacing: 8,
                        color: EqColours.ink,
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Sign-in code',
                        hintText: '000000',
                        hintStyle: TextStyle(letterSpacing: 8),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter the 6-digit code we sent you';
                        }
                        if (v.trim().length != 6) {
                          return 'Code is 6 digits';
                        }
                        return null;
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: EqSpacing.md),
                      Text(
                        error,
                        style: EqTypography.label.copyWith(
                          color: EqColours.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: EqSpacing.lg),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: EqColours.sky,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Verify'),
                    ),
                    const SizedBox(height: EqSpacing.md),
                    TextButton(
                      onPressed: (isLoading || isSending || _identifier.isEmpty)
                          ? null
                          : _resend,
                      child: Text(
                        isSending ? 'Sending…' : 'Resend code',
                        style: EqTypography.bodyM.copyWith(
                          color: EqColours.sky,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

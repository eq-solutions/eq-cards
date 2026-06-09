import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';
import '../notifiers/join_context_notifier.dart';
import '../notifiers/provision_context_notifier.dart';

// How long the resend button is disabled after sending a code.
const _kResendCooldown = Duration(seconds: 30);

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Captured from the first AuthFlowAwaitingOtp state we see.
  // Preserved through error/verifying transitions so retries always work.
  String _identifier = ''; // email address or E.164 phone number
  bool _isPhone = false;

  // Resend cooldown
  Timer? _cooldownTimer;
  int _cooldownSeconds = _kResendCooldown.inSeconds;

  @override
  void initState() {
    super.initState();
    // Start cooldown immediately — the code was just sent to land here.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _kResendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) t.cancel();
      });
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authFlowNotifierProvider.notifier);
    final provisionCtx = ref.read(provisionContextNotifierProvider);
    final joinCtx = ref.read(joinContextNotifierProvider);
    if (_isPhone && provisionCtx != null) {
      await notifier.provisionTenant(
        _identifier,
        _codeController.text,
        provisionCtx.provisionToken,
      );
    } else if (_isPhone && joinCtx != null) {
      await notifier.joinTenant(
        _identifier,
        _codeController.text,
        joinCtx.tenantSlug,
      );
    } else if (_isPhone) {
      await notifier.verifyPhoneOtp(_identifier, _codeController.text);
    } else {
      await notifier.verifyOtp(_identifier, _codeController.text);
    }
  }

  Future<void> _resend() async {
    _codeController.clear();
    _startCooldown();
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

    // Capture identifier + channel the moment we land in awaiting state.
    // Preserved through error/verifying so retries always have it.
    if (flowState is AuthFlowAwaitingOtp && _identifier.isEmpty) {
      _identifier = flowState.displayTarget;
      _isPhone = flowState.isPhone;
    }

    // Clear code on error transition; handle provision completion.
    ref.listen<AuthFlowState>(authFlowNotifierProvider, (_, next) {
      if (next is AuthFlowError) {
        _codeController.clear();
      } else if (next is AuthFlowProvisionComplete) {
        // Workspace created — clear context, open Shell, return to sign-in.
        // If the server returned an access_token, append it as #sh=<token>
        // so Shell's SessionProvider can auto-log the admin in via
        // shell-handoff-provision (no second OTP required).
        ref.read(provisionContextNotifierProvider.notifier).clear();
        final slug = next.tenantSlug;
        if (slug.isNotEmpty) {
          final token = next.accessToken;
          final fragment = (token != null && token.isNotEmpty)
              ? '#sh=${Uri.encodeComponent(token)}'
              : '';
          unawaited(launchUrl(
            Uri.parse('https://core.eq.solutions/$slug$fragment'),
            mode: LaunchMode.externalApplication,
          ));
        }
        if (mounted) context.go(Routes.email);
      }
    });

    // Safety: stale navigation after app restart → back to entry screen.
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
    final canResend = !isLoading && !isSending && _identifier.isNotEmpty &&
        _cooldownSeconds <= 0;

    final subtitle = _identifier.isNotEmpty
        ? 'We sent a 6-digit code to $_identifier.'
        : 'We sent a 6-digit code.';

    return Scaffold(
      backgroundColor: EqColours.white,
      appBar: AppBar(
        backgroundColor: EqColours.white,
        elevation: 0,
        leading: BackButton(
          color: EqColours.ink,
          onPressed: () {
            ref.read(authFlowNotifierProvider.notifier).reset();
            ref.read(joinContextNotifierProvider.notifier).clear();
            ref.read(provisionContextNotifierProvider.notifier).clear();
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
                      subtitle,
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.xl),
                    AutofillGroup(
                      child: TextFormField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
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
                      onFieldSubmitted: (_) => unawaited(_submit()),
                      decoration: const InputDecoration(
                        labelText: 'Sign-in code',
                        hintText: '000000',
                        hintStyle: TextStyle(letterSpacing: 8),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter the 6-digit code';
                        }
                        if (v.trim().length != 6) return 'Code is 6 digits';
                        return null;
                      },
                    ),
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
                      onPressed: isLoading ? null : () => unawaited(_submit()),
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
                      onPressed: canResend ? () => unawaited(_resend()) : null,
                      child: Text(
                        isSending
                            ? 'Sending…'
                            : _cooldownSeconds > 0
                                ? 'Resend code (${_cooldownSeconds}s)'
                                : 'Resend code',
                        style: EqTypography.bodyM.copyWith(
                          color: canResend ? EqColours.sky : EqColours.grey,
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

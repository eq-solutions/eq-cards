import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../../core/widgets/eq_text_field.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  /// Set to `true` via `--dart-define=PILOT_MODE=true` during the closed
  /// SKS pilot. Shows a banner explaining the code is relayed by Royce
  /// rather than arriving by SMS. Auto-disappears when Twilio production
  /// is wired and the dart-define is dropped.
  static const _pilotMode =
      bool.fromEnvironment('PILOT_MODE', defaultValue: false);

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();

  // 30s (was 60s). Per Agent 2 UX audit — 60s feels broken when the
  // user is expecting a real SMS. 30s is the modern OTP-app norm.
  static const _resendCooldownSeconds = 30;
  int _secondsLeft = _resendCooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _secondsLeft = _resendCooldownSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 0) {
        _timer?.cancel();
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) return;
    await ref
        .read(authFlowNotifierProvider.notifier)
        .verifyOtp(widget.phone, code);
    // Success path: authStateChangesProvider fires, router redirects to /home.
  }

  Future<void> _resend() async {
    await ref.read(authFlowNotifierProvider.notifier).sendOtp(widget.phone);
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final flowState = ref.watch(authFlowNotifierProvider);
    final isVerifying = flowState is AuthFlowVerifying;
    final isResending = flowState is AuthFlowSendingOtp;
    final errorText = flowState is AuthFlowError ? flowState.message : null;

    return Scaffold(
      backgroundColor: EqColours.white,
      appBar: AppBar(
        backgroundColor: EqColours.white,
        foregroundColor: EqColours.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter code', style: EqTypography.headingXL),
              const SizedBox(height: EqSpacing.sm),
              Text(
                OtpScreen._pilotMode
                    ? 'Pilot users: your code comes from Royce directly, '
                        'not by SMS. Check your messages from him.'
                    : 'Sent to ${widget.phone}',
                style: EqTypography.bodyM.copyWith(
                  color: OtpScreen._pilotMode
                      ? EqColours.deep
                      : EqColours.grey,
                ),
              ),
              const SizedBox(height: EqSpacing.xl),
              EqTextField(
                controller: _controller,
                label: '6-digit code',
                keyboardType: TextInputType.number,
                errorText: errorText,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (value) {
                  if (value.length == 6) _verify();
                },
                onSubmitted: (_) {
                  if (!isVerifying) unawaited(_verify());
                },
              ),
              const SizedBox(height: EqSpacing.xl),
              EqButton(
                label: 'Verify',
                onPressed: isVerifying ? null : _verify,
                isLoading: isVerifying,
                fullWidth: true,
              ),
              const SizedBox(height: EqSpacing.md),
              Center(
                child: TextButton(
                  onPressed:
                      (_secondsLeft == 0 && !isResending) ? _resend : null,
                  child: Text(
                    _secondsLeft == 0
                        ? 'Resend code'
                        : 'Resend in ${_secondsLeft}s',
                    style: EqTypography.bodyM.copyWith(
                      color:
                          _secondsLeft == 0 ? EqColours.sky : EqColours.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

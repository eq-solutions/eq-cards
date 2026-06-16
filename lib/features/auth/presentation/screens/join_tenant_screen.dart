import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../data/aus_phone.dart';
import '../../domain/auth_flow_state.dart';
import '../../domain/join_context.dart';
import '../notifiers/auth_flow_notifier.dart';
import '../notifiers/join_context_notifier.dart';

/// Shown when a worker navigates to /join?tenant={slug} — either by scanning
/// a QR code or by tapping "Join with a join code" on the sign-in screen and
/// entering the slug in the bottom sheet.
///
/// The worker enters their mobile number, the screen stores a [JoinContext],
/// sends the phone OTP, then navigates to /auth/otp. The OTP screen reads the
/// [JoinContext] and routes verification through [AuthFlowNotifier.joinTenant]
/// instead of the normal `verifyPhoneOtp` path.
class JoinTenantScreen extends ConsumerStatefulWidget {
  const JoinTenantScreen({
    super.key,
    required this.tenantSlug,
    this.tenantName,
  });

  final String tenantSlug;
  final String? tenantName;

  @override
  ConsumerState<JoinTenantScreen> createState() => _JoinTenantScreenState();
}

class _JoinTenantScreenState extends ConsumerState<JoinTenantScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _displayName {
    final ctx = JoinContext(
      tenantSlug: widget.tenantSlug,
      tenantName: widget.tenantName,
    );
    return ctx.displayName;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normaliseAusMobile(_phoneController.text.trim())!;

    // Store the join context so OtpScreen can route through joinTenant.
    ref.read(joinContextNotifierProvider.notifier).setContext(
          JoinContext(
            tenantSlug: widget.tenantSlug,
            tenantName: widget.tenantName,
          ),
        );

    await ref.read(authFlowNotifierProvider.notifier).sendPhoneOtp(phone);
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
      appBar: AppBar(
        backgroundColor: EqColours.white,
        elevation: 0,
        leading: BackButton(
          color: EqColours.ink,
          onPressed: () {
            ref.read(authFlowNotifierProvider.notifier).reset();
            ref.read(joinContextNotifierProvider.notifier).clear();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.xl,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: EqSpacing.xl),

                    // ── Brand icon ───────────────────────────────────────────
                    Image.asset(
                      'assets/icon/launcher.png',
                      width: 80,
                      height: 80,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: EqSpacing.lg),

                    // ── Header ───────────────────────────────────────────────
                    Text(
                      'Join $_displayName',
                      style: EqTypography.headingL.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EqColours.deep,
                      ),
                    ),
                    const SizedBox(height: EqSpacing.xs),
                    Text(
                      'Enter the mobile number registered with your account.',
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.grey,
                      ),
                    ),

                    const SizedBox(height: EqSpacing.xl),

                    // ── Phone field ──────────────────────────────────────────
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      autocorrect: false,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => unawaited(_submit()),
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

                    // ── Error ────────────────────────────────────────────────
                    if (error != null) ...[
                      const SizedBox(height: EqSpacing.sm),
                      Text(
                        error,
                        style: EqTypography.label.copyWith(
                          color: EqColours.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ] else
                      const SizedBox(height: EqSpacing.sm),

                    // ── Send code button ─────────────────────────────────────
                    FilledButton(
                      onPressed:
                          isLoading ? null : () => unawaited(_submit()),
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
                          : const Text('Send code'),
                    ),

                    const SizedBox(height: EqSpacing.xl),
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

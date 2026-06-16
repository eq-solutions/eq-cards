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
import '../../domain/provision_context.dart';
import '../notifiers/auth_flow_notifier.dart';
import '../notifiers/provision_context_notifier.dart';

/// Shown when an org admin navigates to /provision?token={uuid}&name={orgName}.
///
/// The admin enters their mobile number, EQ Cards sends a phone OTP, and OTP
/// verification routes through [AuthFlowNotifier.provisionTenant] which
/// atomically creates the workspace via shell-provision-tenant. On success
/// the admin is directed to Shell (core.eq.solutions) to log in.
class ProvisionTenantScreen extends ConsumerStatefulWidget {
  const ProvisionTenantScreen({
    super.key,
    required this.provisionToken,
    this.orgName,
  });

  /// One-time UUID from shell_control.provision_tokens.
  final String provisionToken;

  /// Optional display name from the ?name= URL param.
  final String? orgName;

  @override
  ConsumerState<ProvisionTenantScreen> createState() =>
      _ProvisionTenantScreenState();
}

class _ProvisionTenantScreenState
    extends ConsumerState<ProvisionTenantScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _displayName {
    return ProvisionContext(
      provisionToken: widget.provisionToken,
      orgName: widget.orgName,
    ).displayName;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normaliseAusMobile(_phoneController.text.trim())!;

    ref.read(provisionContextNotifierProvider.notifier).setContext(
          ProvisionContext(
            provisionToken: widget.provisionToken,
            orgName: widget.orgName,
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
            ref.read(provisionContextNotifierProvider.notifier).clear();
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

                    // ── Brand icon ────────────────────────────────────────────
                    Image.asset(
                      'assets/icon/launcher.png',
                      width: 80,
                      height: 80,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: EqSpacing.lg),

                    // ── Header ────────────────────────────────────────────────
                    Text(
                      'Set up $_displayName',
                      style: EqTypography.headingL.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EqColours.deep,
                      ),
                    ),
                    const SizedBox(height: EqSpacing.xs),
                    Text(
                      'Create your EQ workspace. Enter your mobile number to get started.',
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.grey,
                      ),
                    ),

                    const SizedBox(height: EqSpacing.xl),

                    // ── Phone field ───────────────────────────────────────────
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

                    // ── Error ─────────────────────────────────────────────────
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

                    // ── Submit button ─────────────────────────────────────────
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
                          : const Text('Continue'),
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

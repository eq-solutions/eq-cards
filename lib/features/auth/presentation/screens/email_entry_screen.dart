import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../domain/auth_flow_state.dart';
import '../notifiers/auth_flow_notifier.dart';

class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({super.key});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authFlowNotifierProvider.notifier)
        .sendOtp(_emailController.text);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authFlowNotifierProvider, (_, next) {
      if (next is AuthFlowAwaitingOtp) {
        context.push(Routes.otp);
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
            child: Padding(
              padding: const EdgeInsets.all(EqSpacing.xl),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/icon/launcher.png',
                      width: 64,
                      height: 64,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: EqSpacing.lg),
                    Text(
                      'Sign in to EQ Cards',
                      style: EqTypography.headingL.copyWith(
                        fontWeight: FontWeight.w700,
                        color: EqColours.deep,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      "Enter your email and we'll send you a sign-in code.",
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: EqSpacing.xl),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
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
                          : const Text('Send code'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/validators/input_validators.dart';
import '../../data/auth_repository.dart';
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
  bool _googleLoading = false;

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

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // On web this redirects the page — setState after is a no-op.
    } catch (_) {
      if (mounted) setState(() => _googleLoading = false);
    }
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
                  const SizedBox(height: EqSpacing.xl),

                  // ── Google sign-in ──────────────────────────────────────
                  _GoogleSignInButton(
                    loading: _googleLoading,
                    onTap: _googleLoading ? null : _signInWithGoogle,
                  ),

                  // ── Divider ─────────────────────────────────────────────
                  const SizedBox(height: EqSpacing.lg),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: EqSpacing.md),
                        child: Text(
                          'or',
                          style: EqTypography.label
                              .copyWith(color: EqColours.grey),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: EqSpacing.lg),

                  // ── Email OTP ────────────────────────────────────────────
                  Text(
                    "Enter your email and we'll send you a sign-in code.",
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofocus: false,
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
                            style: EqTypography.label
                                .copyWith(color: EqColours.error),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: EqColours.border),
        backgroundColor: EqColours.white,
        foregroundColor: EqColours.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: EqColours.grey,
                strokeWidth: 2,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoogleLogo(),
                const SizedBox(width: EqSpacing.sm),
                Text(
                  'Continue with Google',
                  style: EqTypography.bodyL.copyWith(
                    fontWeight: FontWeight.w500,
                    color: EqColours.ink,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Google "G" logo rendered as a pure Flutter widget — no assets needed.
class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Background circle (white)
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = Colors.white,
    );

    // Four colour arcs — simplified Google G shape
    final arcs = [
      (-0.26, 1.83, const Color(0xFF4285F4)), // blue
      (1.57,  1.05, const Color(0xFF34A853)), // green
      (2.62,  0.52, const Color(0xFFFBBC05)), // yellow
      (3.14,  1.10, const Color(0xFFEA4335)), // red
    ];

    for (final (start, sweep, color) in arcs) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.28;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.6),
        start,
        sweep,
        false,
        paint,
      );
    }

    // White cutout for the horizontal bar of the G
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.14, r * 0.65, size.height * 0.28),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

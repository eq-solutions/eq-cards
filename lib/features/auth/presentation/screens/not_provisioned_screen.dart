import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../data/auth_repository.dart';

/// Shown when a user has authenticated (valid Supabase session) but has no
/// tenant_id in their JWT — no shell_control.users row exists yet.
///
/// Two paths:
///   1. Standalone tradie — "Start my personal wallet" calls
///      eq_cards_auto_provision() then refreshSession(). The hook injects
///      tenant_id into the new JWT and the router routes to the wallet.
///   2. Employer code — enter a join code (tenant slug) and navigate to
///      the join-tenant flow where the worker's phone is matched to an invite.
class NotProvisionedScreen extends ConsumerStatefulWidget {
  const NotProvisionedScreen({super.key});

  @override
  ConsumerState<NotProvisionedScreen> createState() =>
      _NotProvisionedScreenState();
}

class _NotProvisionedScreenState extends ConsumerState<NotProvisionedScreen> {
  bool _provisioning = false;
  String? _error;
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startPersonalWallet() async {
    setState(() {
      _provisioning = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).autoProvision();
      if (!mounted) return;
      // Navigate explicitly to the wallet. Relying only on the auth-state
      // listener to re-route left first-time tradies stuck on the spinner when
      // the token-refresh event didn't re-fire the redirect. The JWT now
      // carries the personal tenant_id, so the provisioning gate lets us in.
      context.go(Routes.licencesList);
    } catch (_) {
      if (mounted) {
        setState(() {
          _provisioning = false;
          _error = 'Could not set up your wallet. Please try again.';
        });
      }
    }
  }

  void _joinWithCode() {
    final code = _codeController.text.trim().toLowerCase();
    if (code.isEmpty) return;
    context.go('${Routes.join}?tenant=$code');
  }

  @override
  Widget build(BuildContext context) {
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
                  const Icon(
                    Icons.badge_outlined,
                    size: 56,
                    color: EqColours.sky,
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    'Welcome to EQ Cards',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Text(
                    'Your digital wallet for licences, certificates and your employment record.',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  FilledButton(
                    onPressed: _provisioning ? null : _startPersonalWallet,
                    style: FilledButton.styleFrom(
                      backgroundColor: EqColours.sky,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _provisioning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Start my personal wallet'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      _error!,
                      style: EqTypography.label.copyWith(
                        color: EqColours.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: EqSpacing.xl),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: EqSpacing.md,
                        ),
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
                  Text(
                    'Have a code from your employer?',
                    style: EqTypography.label.copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          decoration: const InputDecoration(
                            hintText: 'Enter join code',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          onSubmitted: (_) => _joinWithCode(),
                        ),
                      ),
                      const SizedBox(width: EqSpacing.sm),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _joinWithCode,
                          style: FilledButton.styleFrom(
                            backgroundColor: EqColours.deep,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  TextButton(
                    onPressed: () =>
                        ref.read(authRepositoryProvider).signOut(),
                    child: Text(
                      'Back to sign in',
                      style: EqTypography.label.copyWith(color: EqColours.grey),
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

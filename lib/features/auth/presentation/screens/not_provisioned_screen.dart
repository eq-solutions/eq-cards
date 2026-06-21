import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      // Verify the JWT refresh actually embedded the tenant_id. If the refresh
      // token was stale (Refresh token is not valid — EQ-CARDS-D) the silent
      // catch in autoProvision() leaves tenant_id absent, causing the router to
      // bounce straight back here. Detect that and sign out so the next sign-in
      // starts with a fresh session and the hook embeds tenant_id correctly.
      final tenantId = Supabase.instance.client.auth.currentSession
          ?.user.appMetadata['tenant_id'];
      if (tenantId != null) {
        context.go(Routes.card);
      } else {
        await ref.read(authRepositoryProvider).signOut();
        if (mounted) {
          context.go(Routes.email);
          // Show a brief snackbar so the user understands why they're back at
          // sign-in rather than silently looping.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Wallet created — sign in again to open it.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
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
    // /claim?tenant= finds the worker's existing invite by phone (ClaimByPhoneScreen).
    // /join?tenant= is open enrollment — creates a blank account and bypasses
    // pre-loaded invite credentials. Never use /join for employer-code entry.
    context.go('${Routes.claim}?tenant=$code');
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

import 'dart:async';

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
/// Auto-provisions a personal wallet immediately. Company access is granted
/// separately via the access-request flow (sign up → tap company → Royce
/// approves). No invite tokens, no manual lookup needed.
class NotProvisionedScreen extends ConsumerStatefulWidget {
  const NotProvisionedScreen({super.key});

  @override
  ConsumerState<NotProvisionedScreen> createState() =>
      _NotProvisionedScreenState();
}

class _NotProvisionedScreenState extends ConsumerState<NotProvisionedScreen> {
  bool _provisioning = false;
  String? _provisionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startPersonalWallet());
    });
  }

  Future<void> _startPersonalWallet() async {
    setState(() {
      _provisioning = true;
      _provisionError = null;
    });
    try {
      await ref.read(authRepositoryProvider).autoProvision();
      if (!mounted) return;

      // Verify the JWT refresh actually embedded the tenant_id.
      // Retry up to 3 times with 1s gaps — the provision committed but the
      // hook may need a moment to propagate. Never sign the user out here:
      // the wallet row exists and they're authenticated; a sign-out would
      // force a second OTP entry for no reason.
      String? tenantId() => Supabase.instance.client.auth.currentSession
          ?.user.appMetadata['tenant_id'] as String?;
      for (var i = 0; i < 3 && tenantId() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        try {
          await Supabase.instance.client.auth
              .refreshSession()
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      if (!mounted) return;
      if (tenantId() != null) {
        context.go(Routes.card);
      } else {
        // All retries exhausted. Wallet is provisioned but the JWT hasn't
        // caught up — show a tap-to-retry so the user can try again
        // without losing their session (no sign-out).
        setState(() {
          _provisioning = false;
          _provisionError = 'Your wallet is ready — tap to open it.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _provisioning = false;
          _provisionError = 'Could not set up your wallet. Please try again.';
        });
      }
    }
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
                        : const Text('Open my wallet'),
                  ),
                  if (_provisionError != null) ...[
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      _provisionError!,
                      style: EqTypography.label.copyWith(
                        color: EqColours.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: EqSpacing.xl),
                  TextButton(
                    onPressed: () =>
                        ref.read(authRepositoryProvider).signOut(),
                    child: Text(
                      'Back to sign in',
                      style:
                          EqTypography.label.copyWith(color: EqColours.grey),
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

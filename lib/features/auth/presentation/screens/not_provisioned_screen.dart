import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../data/auth_repository.dart';

/// Shown when a user has authenticated successfully (valid Supabase session)
/// but their account has not been provisioned to any EQ workspace — i.e.
/// app_metadata.tenant_id is absent from the JWT.
///
/// For phone OTP: AuthRepository.verifyPhoneOtp() calls the Shell's
/// shell-login-phone-otp function to get a tenant-aware JWT. This screen is
/// reached only when that exchange fails (user not in shell_control.users,
/// Shell misconfigured, or network error). The fix is for their manager to
/// provision them in the Shell admin, then ask the user to sign in again.
///
/// For email OTP / Google OAuth: the custom_access_token_hook on eq-canonical
/// is not yet enabled, so those sessions never carry tenant_id. See
/// docs/cards-canonical-api-rewire.md §5 for the hook enablement plan.
class NotProvisionedScreen extends ConsumerStatefulWidget {
  const NotProvisionedScreen({super.key});

  @override
  ConsumerState<NotProvisionedScreen> createState() =>
      _NotProvisionedScreenState();
}

class _NotProvisionedScreenState extends ConsumerState<NotProvisionedScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
    // GoRouter's auth listener picks up the signOut and redirects to email.
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
                    Icons.lock_outline,
                    size: 56,
                    color: EqColours.grey,
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    'No workspace access',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Text(
                    "We couldn't link you to an EQ workspace. "
                    'Sign out and try again — if the problem continues, '
                    'ask your manager to check your account access.',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  FilledButton(
                    onPressed: _signingOut ? null : _signOut,
                    style: FilledButton.styleFrom(
                      backgroundColor: EqColours.sky,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _signingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Sign out and try again'),
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

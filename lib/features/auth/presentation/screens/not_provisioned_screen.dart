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
/// This happens when a user self-registers via phone or email OTP without
/// going through an invite link. The fix is for their manager to send them
/// an invite link, which provisions them and sets tenant_id on next sign-in.
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
                    "Your account isn't linked to an EQ workspace yet. "
                    'Ask your manager to send you an invite link.',
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
                        : const Text('Sign out'),
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  TextButton(
                    onPressed: _signingOut ? null : _signOut,
                    child: Text(
                      'Already have an account? Sign in with email instead',
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.sky,
                      ),
                      textAlign: TextAlign.center,
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

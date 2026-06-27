import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/pending_claim.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../workers/data/worker_self_repository.dart';
import '../../data/auth_repository.dart';

/// Shown when a user has authenticated (valid Supabase session) but has no
/// tenant_id in their JWT — no shell_control.users row exists yet.
///
/// Two paths:
///   1. Standalone tradie — "Start my personal wallet" calls
///      eq_cards_auto_provision() then refreshSession(). The hook injects
///      tenant_id into the new JWT and the router routes to the wallet.
///   2. Company account — "Find my company account" calls
///      eq_cards_find_invites_by_phone() (authenticated, no code needed).
///      Single match → straight to /claim?token=. Multiple → picker sheet.
class NotProvisionedScreen extends ConsumerStatefulWidget {
  const NotProvisionedScreen({super.key});

  @override
  ConsumerState<NotProvisionedScreen> createState() =>
      _NotProvisionedScreenState();
}

enum _FindPhase { idle, searching, noneFound, error }

class _NotProvisionedScreenState extends ConsumerState<NotProvisionedScreen> {
  bool _provisioning = false;
  String? _provisionError;

  _FindPhase _findPhase = _FindPhase.idle;
  String? _findError;

  @override
  void initState() {
    super.initState();
    // Reach here only in edge cases (e.g. autoProvision already ran in
    // _resolveAndLand but refreshSession returned no tenant_id due to a stale
    // refresh token). If there's no pending invite to activate, provision
    // immediately rather than making the user press a button.
    if (PendingClaim.token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startPersonalWallet());
      });
    }
  }

  Future<void> _startPersonalWallet() async {
    setState(() {
      _provisioning = true;
      _provisionError = null;
    });
    try {
      await ref.read(authRepositoryProvider).autoProvision();
      if (!mounted) return;

      // Verify the JWT refresh actually embedded the tenant_id. If the refresh
      // token was stale the silent catch in autoProvision() leaves tenant_id
      // absent, causing the router to bounce straight back here. Sign out so
      // the next sign-in starts with a fresh session.
      final tenantId = Supabase.instance.client.auth.currentSession
          ?.user.appMetadata['tenant_id'];
      if (tenantId != null) {
        context.go(Routes.card);
      } else {
        await ref.read(authRepositoryProvider).signOut();
        if (mounted) {
          context.go(Routes.email);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wallet created — sign in again to open it.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
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

  Future<void> _findCompanyAccount() async {
    setState(() {
      _findPhase = _FindPhase.searching;
      _findError = null;
    });
    try {
      final invites = await ref
          .read(workerSelfRepositoryProvider)
          .findInvitesByPhone();

      if (!mounted) return;

      if (invites.isEmpty) {
        setState(() => _findPhase = _FindPhase.noneFound);
        return;
      }

      setState(() => _findPhase = _FindPhase.idle);

      if (invites.length == 1) {
        context.go('${Routes.claim}?token=${invites.first.token}');
      } else {
        await showModalBottomSheet<void>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) => _InvitePickerSheet(
            invites: invites,
            onPicked: (token) {
              Navigator.of(ctx).pop();
              context.go('${Routes.claim}?token=$token');
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _findPhase = _FindPhase.error;
          _findError = 'Could not search for invites. Check your connection.';
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

                  // ── Personal wallet ──────────────────────────────────────
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

                  // ── Company account ──────────────────────────────────────
                  OutlinedButton(
                    onPressed: _findPhase == _FindPhase.searching
                        ? null
                        : _findCompanyAccount,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EqColours.deep,
                      side: const BorderSide(color: EqColours.border),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _findPhase == _FindPhase.searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: EqColours.deep,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Find my company account'),
                  ),

                  if (_findPhase == _FindPhase.noneFound) ...[
                    const SizedBox(height: EqSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(EqSpacing.md),
                      decoration: BoxDecoration(
                        color: EqColours.ice,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: EqColours.sky.withAlpha(80)),
                      ),
                      child: Text(
                        'No company invites found for your number. Ask your manager to send you an invite.',
                        style:
                            EqTypography.bodyM.copyWith(color: EqColours.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else if (_findPhase == _FindPhase.error &&
                      _findError != null) ...[
                    const SizedBox(height: EqSpacing.sm),
                    Text(
                      _findError!,
                      style: EqTypography.label
                          .copyWith(color: EqColours.error),
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

// ── Invite picker (multiple orgs) ────────────────────────────────────────────

class _InvitePickerSheet extends StatelessWidget {
  const _InvitePickerSheet({
    required this.invites,
    required this.onPicked,
  });

  final List<FoundInvite> invites;
  final void Function(String token) onPicked;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: EqSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: EqSpacing.xl),
              child: Text(
                'Choose your company',
                style: EqTypography.headingM.copyWith(
                  fontWeight: FontWeight.w700,
                  color: EqColours.ink,
                ),
              ),
            ),
            const SizedBox(height: EqSpacing.sm),
            ...invites.map(
              (invite) => ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: EqSpacing.xl,
                  vertical: EqSpacing.xs,
                ),
                leading: const Icon(Icons.business_outlined,
                    color: EqColours.sky),
                title: Text(
                  invite.orgName,
                  style: EqTypography.bodyM
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 14, color: EqColours.grey),
                onTap: () => onPicked(invite.token),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

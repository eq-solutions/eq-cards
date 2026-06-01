import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../data/admin_worker_repository.dart';
import '../providers/org_admin_provider.dart';

/// Deep-link target for worker invite claims.
///
/// URL: /claim?token=`uuid`
///
/// Flow:
///   - Signed in  → auto-calls eq_cards_claim_invite, shows result.
///   - Signed out → shows a "create your account" prompt; after the worker
///     signs in the claim resolves on the next visit to this URL.
class ClaimInviteScreen extends ConsumerStatefulWidget {
  const ClaimInviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ClaimInviteScreen> createState() => _ClaimInviteScreenState();
}

class _ClaimInviteScreenState extends ConsumerState<ClaimInviteScreen> {
  _ClaimState _state = _ClaimState.idle;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final isSignedIn =
        Supabase.instance.client.auth.currentSession != null;
    if (isSignedIn) unawaited(_claim());
  }

  Future<void> _claim() async {
    setState(() {
      _state = _ClaimState.loading;
      _errorMessage = null;
    });
    try {
      await ref
          .read(adminWorkerRepositoryProvider)
          .claimInvite(widget.token);

      // Invalidate so the app picks up the newly linked worker record.
      ref.invalidate(orgAdminOrgIdProvider);

      setState(() => _state = _ClaimState.success);

      // Give the success screen a moment then send to home.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) context.go(Routes.licencesList);
    } catch (e) {
      final msg = switch (e.toString()) {
        final s when s.contains('invite_not_found') =>
          'This invite link is not valid.',
        final s when s.contains('invite_already_claimed') =>
          'This invite has already been used.',
        final s when s.contains('invite_expired') =>
          'This invite has expired. Ask your admin to send a new one.',
        _ => 'Something went wrong. Please try again or contact your admin.',
      };
      setState(() {
        _state = _ClaimState.error;
        _errorMessage = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn =
        Supabase.instance.client.auth.currentSession != null;

    return Scaffold(
      appBar: const EqAppBar(title: 'Activate account'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.lg),
          child: switch (_state) {
            _ClaimState.idle when !isSignedIn => _NotSignedIn(
                onSignIn: () => context.push(Routes.email),
              ),
            _ClaimState.idle => const _Loading(),
            _ClaimState.loading => const _Loading(),
            _ClaimState.success => const _Success(),
            _ClaimState.error => _Error(
                message: _errorMessage!,
                onRetry: _claim,
              ),
          },
        ),
      ),
    );
  }
}

enum _ClaimState { idle, loading, success, error }

// ── States ────────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: EqColours.sky),
          SizedBox(height: EqSpacing.md),
          Text('Activating your account…'),
        ],
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 72, color: EqColours.success),
          const SizedBox(height: EqSpacing.md),
          Text("You're in.", style: EqTypography.headingL),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Your profile and credentials are ready.\nTaking you to your wallet…',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _NotSignedIn extends StatelessWidget {
  const _NotSignedIn({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, size: 72, color: EqColours.sky),
          const SizedBox(height: EqSpacing.md),
          Text("You've been invited", style: EqTypography.headingL),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'Your profile and credentials are already loaded.\n'
            'Sign in or create your account to access them.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(
            label: 'Sign in / Create account',
            onPressed: onSignIn,
            fullWidth: true,
          ),
          const SizedBox(height: EqSpacing.sm),
          Text(
            'After signing in, open this link again to activate your account.',
            style: EqTypography.label,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 72, color: EqColours.error),
          const SizedBox(height: EqSpacing.md),
          Text('Could not activate', style: EqTypography.headingM),
          const SizedBox(height: EqSpacing.sm),
          Text(
            message,
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(label: 'Try again', onPressed: onRetry, fullWidth: true),
        ],
      ),
    );
  }
}

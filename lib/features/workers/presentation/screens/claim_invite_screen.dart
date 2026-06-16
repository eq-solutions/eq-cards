import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/pending_claim.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_app_bar.dart';
import '../../../../core/widgets/eq_button.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/admin_worker_repository.dart';
import '../../data/worker_self_repository.dart';
import '../providers/org_admin_provider.dart';

/// Deep-link target for worker invite claims.
///
/// URL: `/claim?token=<uuid>`
///
/// Flow:
///   1. On load: fetch invite preview (org name, credential count).
///   2. Not signed in → "You've been invited by {org}" + sign-in button.
///   3. Signed in + preview loaded → consent screen ("Activate my account").
///   4. Signed in, tap activate → claim RPC → success → wallet.
///   5. Token invalid/expired/claimed → error with clear message.
class ClaimInviteScreen extends ConsumerStatefulWidget {
  const ClaimInviteScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ClaimInviteScreen> createState() => _ClaimInviteScreenState();
}

class _ClaimInviteScreenState extends ConsumerState<ClaimInviteScreen> {
  _Phase _phase = _Phase.loading;
  InvitePreview? _preview;
  late String _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    setState(() => _phase = _Phase.loading);
    try {
      final preview = await ref
          .read(workerSelfRepositoryProvider)
          .previewInvite(widget.token)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (preview == null) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage =
              'This invite link is not valid, has already been used, or has expired.';
        });
        return;
      }

      _preview = preview;
      final isSignedIn =
          Supabase.instance.client.auth.currentSession != null;

      setState(
          () => _phase = isSignedIn ? _Phase.consent : _Phase.notSignedIn);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = 'Taking too long to load. Check your connection and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage =
            'Could not load invite. Check your connection and try again.';
      });
    }
  }

  Future<void> _activate() async {
    setState(() => _phase = _Phase.activating);
    try {
      await ref
          .read(adminWorkerRepositoryProvider)
          .claimInvite(widget.token);

      // The session was minted at sign-in — BEFORE this claim granted a tenant
      // — so its JWT carries no tenant_id and the provisioning gate would bounce
      // the worker to not-provisioned. Re-run the shell exchange now that the
      // claim has written their shell_control identity, so the refreshed JWT
      // carries the tenant and routing lands them in the wallet. Phone-OTP path
      // only (the exchange matches by phone); a no-op for other sign-in methods.
      final session = Supabase.instance.client.auth.currentSession;
      final rawPhone = session?.user.phone;
      final accessToken = session?.accessToken;
      // Skip the exchange when the hook has already embedded tenant_id.
      final tenantId = session?.user.appMetadata['tenant_id'];
      if (rawPhone != null && rawPhone.isNotEmpty && accessToken != null && tenantId == null) {
        final e164 = rawPhone.startsWith('+') ? rawPhone : '+$rawPhone';
        try {
          await ref
              .read(authRepositoryProvider)
              .phoneOtpShellExchange(e164, accessToken)
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // Non-fatal — claim already committed; JWT refreshes on next navigation.
        }
      }

      // Refresh the session so the custom_access_token_hook now injects
      // tenant_id — the claim RPC just wrote the shell_control.users entry
      // that the hook reads. Without this the JWT still has no tenant_id and
      // the router bounces the worker to notProvisioned after "Open my wallet".
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {
        // Non-fatal — JWT refreshes on next token expiry.
      }

      ref.invalidate(orgAdminOrgIdProvider);

      // Claim done — the worker now has a tenant. Drop the pending token so the
      // router stops treating them as mid-claim.
      PendingClaim.clear();

      setState(() => _phase = _Phase.success);
      // Auto-navigate fallback after 8s so the screen never gets stuck.
      // Primary path: worker taps "Open my wallet" below.
      await Future<void>.delayed(const Duration(seconds: 8));
      if (mounted && _phase == _Phase.success) context.go(Routes.licencesList);
    } catch (e, st) {
      // Known invite states are expected outcomes — surface a clear message,
      // don't page anyone. Anything else is a real failure in the claim path
      // (the chain that's otherwise unobservable) — capture it so a broken
      // first-time activation shows up in Sentry instead of dying silently.
      final s = e.toString();
      final isExpected = s.contains('invite_not_found') ||
          s.contains('invite_already_claimed') ||
          s.contains('invite_expired');
      final msg = switch (s) {
        _ when s.contains('invite_not_found') =>
          'This invite link is not valid.',
        _ when s.contains('invite_already_claimed') =>
          'This invite has already been used.',
        _ when s.contains('invite_expired') =>
          'This invite has expired. Ask your admin to send a new one.',
        _ => 'Something went wrong. Please try again or contact your admin.',
      };
      if (!isExpected) {
        unawaited(Sentry.captureException(
          e,
          stackTrace: st,
          withScope: (scope) async {
            await scope.setTag('flow', 'claim_activate');
            await scope.setContexts('claim', {'token': widget.token});
          },
        ));
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EqAppBar(title: 'Activate account'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.lg),
          child: switch (_phase) {
            _Phase.loading => const _Loading(message: 'Loading invite…'),
            _Phase.notSignedIn => _NotSignedIn(
                preview: _preview,
                onSignIn: () {
                  // Remember the token so that after sign-in (when the worker
                  // has a session but no tenant yet) the router returns them
                  // here to activate, instead of bouncing to not-provisioned.
                  PendingClaim.token = widget.token;
                  unawaited(context.push(Routes.email));
                },
              ),
            _Phase.consent => _Consent(
                preview: _preview!,
                onActivate: _activate,
              ),
            _Phase.activating =>
              const _Loading(message: 'Activating your account…'),
            _Phase.success => _Success(
                orgName: _preview?.orgName,
                onGoToWallet: () {
                  if (mounted) context.go(Routes.licencesList);
                },
              ),
            _Phase.error => _Error(
                message: _errorMessage,
                onRetry: _loadPreview,
              ),
          },
        ),
      ),
    );
  }
}

enum _Phase { loading, notSignedIn, consent, activating, success, error }

// ── Loading ───────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: EqColours.sky),
          const SizedBox(height: EqSpacing.md),
          Text(message),
        ],
      ),
    );
  }
}

// ── Not signed in ─────────────────────────────────────────────────────────────

class _NotSignedIn extends StatelessWidget {
  const _NotSignedIn({required this.preview, required this.onSignIn});

  final InvitePreview? preview;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final orgName = preview?.orgName ?? 'an organisation';
    final count = preview?.credentialCount ?? 0;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/launcher.png',
            width: 80,
            height: 80,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.badge_outlined, size: 80, color: EqColours.sky),
          ),
          const SizedBox(height: EqSpacing.md),
          Text("You've been invited", style: EqTypography.headingL),
          const SizedBox(height: EqSpacing.sm),
          Text(
            '$orgName has pre-loaded your profile'
            '${count > 0 ? ' and $count credential${count == 1 ? '' : 's'}' : ''}'
            ' into your wallet.\nSign in to activate your account.',
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
            "We'll bring you straight back here to activate once you've "
            'signed in.',
            style: EqTypography.label,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Consent ───────────────────────────────────────────────────────────────────

class _Consent extends StatelessWidget {
  const _Consent({required this.preview, required this.onActivate});

  final InvitePreview preview;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final count = preview.credentialCount;
    final days = preview.daysUntilExpiry;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/launcher.png',
            width: 80,
            height: 80,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.badge_outlined, size: 80, color: EqColours.sky),
          ),
          const SizedBox(height: EqSpacing.md),
          Text('Activate your account', style: EqTypography.headingL),
          const SizedBox(height: EqSpacing.sm),
          Text(
            '${preview.orgName} has pre-loaded your profile'
            '${count > 0 ? '\nand $count credential${count == 1 ? '' : 's'}' : ''}'
            ' into your wallet.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          Container(
            padding: const EdgeInsets.all(EqSpacing.md),
            decoration: BoxDecoration(
              color: EqColours.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EqColours.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'By activating, you agree to share your wallet with '
                  '${preview.orgName}. Your profile data will be stored '
                  "in ${preview.orgName}'s EQ Cards workspace. "
                  'You can revoke access at any time from Settings.',
                  style: EqTypography.label,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EqSpacing.sm),
                GestureDetector(
                  onTap: () => context.push(Routes.privacyPolicy),
                  child: Text(
                    'Privacy Policy',
                    style: EqTypography.label.copyWith(
                      color: EqColours.sky,
                      decoration: TextDecoration.underline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(
            label: 'Activate my account',
            onPressed: onActivate,
            fullWidth: true,
          ),
          if (days > 0) ...[
            const SizedBox(height: EqSpacing.sm),
            Text(
              'Link expires in $days day${days == 1 ? '' : 's'}',
              style: EqTypography.label.copyWith(color: EqColours.grey),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Success ───────────────────────────────────────────────────────────────────

class _Success extends StatelessWidget {
  const _Success({required this.onGoToWallet, this.orgName});

  final VoidCallback onGoToWallet;
  final String? orgName;

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
            'Your profile and credentials are ready.',
            style: EqTypography.bodyM.copyWith(color: EqColours.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: EqSpacing.xl),
          EqButton(
            label: 'Open my wallet',
            onPressed: onGoToWallet,
            fullWidth: true,
          ),
          const SizedBox(height: EqSpacing.xl),
          Container(
            padding: const EdgeInsets.all(EqSpacing.md),
            decoration: BoxDecoration(
              color: EqColours.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EqColours.border),
            ),
            child: Column(
              children: [
                Text(
                  'Access EQ on your computer',
                  style: EqTypography.label.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EqSpacing.xs),
                Text(
                  'Visit core.eq.solutions and sign in with your phone number to access your full EQ account'
                  '${orgName != null ? ' at $orgName' : ''}.',
                  style: EqTypography.label.copyWith(color: EqColours.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

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

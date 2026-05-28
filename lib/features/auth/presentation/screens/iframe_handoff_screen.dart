// Cards Unit 4 (2026-05-21) — replaces email-OTP entry.
//
// Cards no longer authenticates against its own Supabase. Instead, the
// EQ Shell mints a canonical Supabase JWT and passes it to the Cards
// iframe via the URL hash on the handoff route:
//
//     https://cards.eq.solutions/auth/handoff#sh=<jwt>
//
// Targeting /auth/handoff directly avoids a GoRouter redirect from "/"
// that would strip the hash fragment before this screen can read it.
//
// This screen runs as the unauthenticated landing route. It:
//
//   1. Pulls #sh=<jwt> out of window.location.hash (web only — Cards
//      is web-first per RUNBOOK; native gets a "open via shell" prompt)
//   2. Calls Supabase.auth.setSession(jwt) — once that succeeds the
//      GoRouter redirect logic kicks in and lands the user on /licences
//   3. Clears the hash from history so the JWT doesn't end up in
//      browser screenshots / pasted URLs
//   4. On no token, shows a clear "open via your tenant shell" prompt
//      with a link to the shell origin
//
// Browser DOM access is behind a conditional import so flutter test
// (VM target, no dart:html) still loads the screen for widget tests.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import 'handoff_platform_io.dart'
    if (dart.library.html) 'handoff_platform_web.dart';

class IframeHandoffScreen extends ConsumerStatefulWidget {
  const IframeHandoffScreen({super.key});

  @override
  ConsumerState<IframeHandoffScreen> createState() =>
      _IframeHandoffScreenState();
}

class _IframeHandoffScreenState extends ConsumerState<IframeHandoffScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShellAuth());
  }

  // Tries cookie-based shell auth first when inside an iframe, then falls
  // back to the URL hash path for backward compatibility.
  Future<void> _consumeShellAuth() async {
    if (!kIsWeb) {
      if (mounted) context.go(Routes.email);
      return;
    }

    if (HandoffPlatform.isInIframe()) {
      final token = await HandoffPlatform.fetchShellVerify();
      if (token != null && token.isNotEmpty) {
        try {
          await Supabase.instance.client.auth.signOut(
            scope: SignOutScope.local,
          );
          await Supabase.instance.client.auth.setSession(
            token,
            accessToken: token,
          );
          HandoffPlatform.replaceHashWithCleanPath();
          if (mounted) context.go(Routes.licencesList);
        } catch (e, stack) {
          debugPrint('IframeHandoffScreen: shell-verify setSession failed: $e');
          unawaited(Sentry.captureException(e, stackTrace: stack));
          setState(
            () => _error =
                'Sign-in failed. Reload EQ Cards from your portal at core.eq.solutions.',
          );
        }
        return;
      }
      // Cookie path gave nothing — fall through to hash check.
    }

    await _consumeHash();
  }

  Future<void> _consumeHash() async {
    if (!kIsWeb) {
      if (mounted) context.go(Routes.email);
      return;
    }

    final hash = HandoffPlatform.currentHash();
    if (hash.isEmpty || !hash.contains('sh=')) {
      // No shell token. If we're embedded in the Shell iframe, don't redirect
      // to the email form — the Google/OTP flows are sandbox-blocked inside an
      // iframe and just confuse users. Show a clear "reload from portal" prompt.
      if (HandoffPlatform.isInIframe()) {
        setState(
          () => _error =
              'Session expired. Reload EQ Cards from your portal at core.eq.solutions.',
        );
        return;
      }
      // Standalone access (direct to cards.eq.solutions) — email OTP is fine.
      if (mounted) context.go(Routes.email);
      return;
    }

    final payload = hash.startsWith('#') ? hash.substring(1) : hash;
    final params = Uri.splitQueryString(payload);
    final token = params['sh'];
    if (token == null || token.isEmpty) {
      setState(
        () => _error =
            'Handoff URL was malformed. Refresh from your tenant shell to retry.',
      );
      return;
    }

    try {
      // Clear any prior session (e.g. a stale email-OTP session from
      // before Unit 4) so the Shell JWT always wins. scope: local means
      // no network call — just wipes localStorage.
      await Supabase.instance.client.auth.signOut(
        scope: SignOutScope.local,
      );

      // gotrue's setSession is (refreshToken, {accessToken}). The shell
      // mints an HS256 access token, NOT a refresh token. Passing it
      // ONLY as positional arg would hit _callRefreshToken which POSTs
      // /token?grant_type=refresh_token and 400s. Passing it as BOTH
      // hits the "accessToken provided + not expired" branch which
      // decodes the JWT, calls getUser(accessToken) to validate (the
      // auth.users row exists, mirrored to shell_control.users), and
      // constructs a Session directly — no /token round-trip.
      // The refreshToken slot will never be used because we never call
      // .refreshSession(); the JWT-cache is renewed by the shell.
      await Supabase.instance.client.auth.setSession(
        token,
        accessToken: token,
      );
      HandoffPlatform.replaceHashWithCleanPath();
      // Navigate explicitly — GoRouter's redirect intentionally excludes
      // /auth/handoff to allow stale-session replacement, so we must drive
      // the final navigation ourselves.
      if (mounted) context.go(Routes.licencesList);
    } catch (e, stack) {
      debugPrint('IframeHandoffScreen: setSession failed: $e');
      unawaited(Sentry.captureException(e, stackTrace: stack));
      setState(
        () => _error = HandoffPlatform.isInIframe()
            ? 'Sign-in failed. Reload EQ Cards from your portal at core.eq.solutions.'
            : 'Sign-in failed. Sign out and back in at your tenant shell, then retry.',
      );
    }
  }

  void _goToEmail() => context.go(Routes.email);

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
                children: [
                  Image.asset(
                    'assets/icon/launcher.png',
                    width: 64,
                    height: 64,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    _error != null ? 'Sign-in failed' : 'Signing you in…',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
                  if (_error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _error!,
                          style: EqTypography.bodyM
                              .copyWith(color: EqColours.ink),
                          textAlign: TextAlign.center,
                        ),
                        // In iframe mode the Google/OTP flows are sandbox-blocked;
                        // show email fallback only for standalone (direct) access.
                        if (!kIsWeb || !HandoffPlatform.isInIframe()) ...[
                          const SizedBox(height: EqSpacing.lg),
                          FilledButton(
                            onPressed: _goToEmail,
                            style: FilledButton.styleFrom(
                              backgroundColor: EqColours.sky,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text('Sign in with email'),
                          ),
                        ],
                      ],
                    )
                  else
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: EqColours.sky,
                        strokeWidth: 2,
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

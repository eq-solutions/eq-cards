// Cards Unit 4 (2026-05-21) — replaces email-OTP entry.
//
// Cards no longer authenticates against its own Supabase. Instead, the
// EQ Shell mints a canonical Supabase JWT and passes it to the Cards
// iframe via the URL hash:
//
//     https://cards.eq.solutions/#sh=<jwt>
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
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeHash());
  }

  Future<void> _consumeHash() async {
    if (!kIsWeb) {
      setState(() => _error = 'Open EQ Cards via your tenant shell.');
      return;
    }

    final hash = HandoffPlatform.currentHash();
    if (hash.isEmpty || !hash.contains('sh=')) {
      setState(() => _error = null); // no token; show prompt
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

    setState(() => _hasToken = true);

    try {
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
    } catch (e) {
      setState(
        () => _error =
            'EQ Cards rejected the sign-in handoff. Sign out and back in at your tenant shell, then retry.\n\n$e',
      );
    }
  }

  void _openShell() {
    if (!kIsWeb) return;
    HandoffPlatform.redirectTo('https://core.eq.solutions');
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
                children: [
                  Image.asset(
                    'assets/icon/launcher.png',
                    width: 64,
                    height: 64,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    _hasToken && _error == null
                        ? 'Signing you in…'
                        : _error == null
                            ? 'EQ Cards'
                            : 'Sign-in failed',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
                  if (_hasToken && _error == null)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: EqColours.sky,
                        strokeWidth: 2,
                      ),
                    )
                  else if (_error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _error!,
                          style: EqTypography.bodyM
                              .copyWith(color: EqColours.ink),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: EqSpacing.lg),
                        FilledButton(
                          onPressed: _openShell,
                          style: FilledButton.styleFrom(
                            backgroundColor: EqColours.sky,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Open my tenant shell'),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Text(
                          'EQ Cards is part of the EQ Solutions platform. Open Cards through your tenant shell to sign in.',
                          style: EqTypography.bodyM
                              .copyWith(color: EqColours.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: EqSpacing.lg),
                        FilledButton(
                          onPressed: _openShell,
                          style: FilledButton.styleFrom(
                            backgroundColor: EqColours.sky,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Open my tenant shell'),
                        ),
                      ],
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

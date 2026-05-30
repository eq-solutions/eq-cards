// Cards Unit 4 (2026-05-21) — replaces email-OTP entry.
//
// Auth priority (most secure → least):
//
//   1. postMessage  — Flutter sends REQUEST_SHELL_TOKEN to the parent shell;
//                     shell responds with SHELL_TOKEN_RESPONSE containing a
//                     fresh JWT. JWT never touches the URL. Works for both
//                     initial load and 15-min refresh cycles.
//
//   2. URL hash     — Legacy path: shell injects #sh=<jwt> into the iframe
//                     src. Kept as fallback until postMessage is confirmed
//                     stable across all tenants; will be removed once Phase 2
//                     ships (shell stops injecting the hash).
//
//   3. Email OTP    — Non-iframe / non-web fallback (native, direct URL).

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

  /// Tries to establish a Supabase session from the shell JWT, in priority order.
  Future<void> _consumeShellAuth() async {
    if (!kIsWeb) {
      if (mounted) context.go(Routes.email);
      return;
    }

    if (HandoffPlatform.isInIframe()) {
      // 1. postMessage — preferred path, JWT never in URL.
      final pmToken = await HandoffPlatform.requestShellToken();
      if (pmToken != null && pmToken.isNotEmpty) {
        final ok = await _applyToken(pmToken);
        if (ok) return;
      }
    }

    // 2. URL hash — legacy fallback (#sh=<jwt> injected by shell).
    await _consumeHash();
  }

  /// Calls setSession with [token], navigates to licences on success.
  /// Returns true on success, false on failure (error state already set).
  Future<bool> _applyToken(String token) async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      await Supabase.instance.client.auth.setSession(
        token,
        accessToken: token,
      );
      HandoffPlatform.replaceHashWithCleanPath();
      if (mounted) context.go(Routes.licencesList);
      return true;
    } catch (e, stack) {
      debugPrint('IframeHandoffScreen: setSession failed: $e');
      unawaited(Sentry.captureException(e, stackTrace: stack));
      setState(
        () => _error = HandoffPlatform.isInIframe()
            ? 'Sign-in failed. Reload EQ Cards from your portal at core.eq.solutions.'
            : 'Sign-in failed. Sign out and back in at your tenant shell, then retry.',
      );
      return false;
    }
  }

  Future<void> _consumeHash() async {
    if (!kIsWeb) {
      if (mounted) context.go(Routes.email);
      return;
    }

    final hash = HandoffPlatform.currentHash();
    if (hash.isEmpty || !hash.contains('sh=')) {
      if (HandoffPlatform.isInIframe()) {
        setState(
          () => _error =
              'Session expired. Reload EQ Cards from your portal at core.eq.solutions.',
        );
        return;
      }
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

    await _applyToken(token);
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
                          style:
                              EqTypography.bodyM.copyWith(color: EqColours.ink),
                          textAlign: TextAlign.center,
                        ),
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

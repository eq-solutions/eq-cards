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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeShellAuth());
  }

  /// gotrue_dart 2.20.0+ calls getUser() inside setSession, which rejects
  /// shell-minted JWTs (no auth.sessions row → session_not_found). The iframe
  /// handoff and #sh= hash paths are therefore broken. Redirect to phone OTP
  /// sign-in, which works correctly via the custom_access_token_hook.
  Future<void> _consumeShellAuth() async {
    HandoffPlatform.replaceHashWithCleanPath();
    if (mounted) context.go(Routes.email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.bg,
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
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                  Text(
                    'Signing you in…',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
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

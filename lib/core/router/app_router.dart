import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth.dart';
import '../../features/auth/domain/app_lock_state.dart';
import '../../features/auth/presentation/notifiers/app_lock_notifier.dart';
import '../../features/auth/presentation/screens/pin_entry_screen.dart';
import '../../features/certificates/certificates.dart';
import '../../features/legal/presentation/screens/legal_document_screen.dart';
import '../../features/licences/licences.dart';
import '../../features/profile/profile.dart';
import '../../features/settings/settings.dart';
import '../shell/home_shell_screen.dart';
import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';
import 'routes.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  // Bridge: Riverpod state changes -> ChangeNotifier -> GoRouter refresh.
  final notifier = _AuthRouterNotifier();
  ref.listen(authStateChangesProvider, (_, __) => notifier.bump());
  ref.listen(appLockNotifierProvider, (_, __) => notifier.bump());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final lockPhase = ref.read(appLockNotifierProvider);
      return _redirect(context, state, lockPhase);
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),
      // Shell handoff — reads #sh=<jwt> from URL hash and calls setSession.
      // Redirects to /auth/email if no token is present in the hash.
      GoRoute(
        path: Routes.handoff,
        builder: (context, state) => const IframeHandoffScreen(),
      ),
      // Email OTP — direct sign-in outside the Shell.
      GoRoute(
        path: Routes.email,
        builder: (context, state) => const EmailEntryScreen(),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (context, state) => const OtpScreen(),
      ),
      // PIN auth — gates the app on every cold start once a PIN is set.
      GoRoute(
        path: Routes.pinSetup,
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: Routes.pinEntry,
        builder: (context, state) => const PinEntryScreen(),
      ),
      // Legal documents — top-level routes outside the shell so they can be
      // reached from anywhere (Settings, share sheet, etc.) and present as
      // full-screen single-document views.
      GoRoute(
        path: Routes.privacyPolicy,
        builder: (context, state) => LegalDocumentScreen.privacy(),
      ),
      GoRoute(
        path: Routes.termsOfUse,
        builder: (context, state) => LegalDocumentScreen.terms(),
      ),
      // D2: public licence-verification page — no auth required.
      // Reached by scanning a QR code from a tradie's EQ Cards wallet.
      GoRoute(
        path: Routes.share,
        builder: (context, state) {
          final licenceId = state.uri.queryParameters['licence_id'] ?? '';
          return ShareLicenceScreen(licenceId: licenceId);
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navShell) =>
            HomeShellScreen(navigationShell: navShell),
        branches: [
          // Tab 0 — Licences (default tab)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.licencesList,
                builder: (context, state) => const LicencesListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) {
                      final prefill = state.extra as LicencePrefill?;
                      return LicenceEditScreen(prefill: prefill);
                    },
                  ),
                  // Driver licence profile-fill confirmation — shown between
                  // OCR and licence save when a DL scan extracts profile data.
                  GoRoute(
                    path: 'fill-profile',
                    builder: (context, state) {
                      final fill = state.extra as DlProfileFill?;
                      return ProfileFillFromLicenceScreen(fill: fill);
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return LicenceDetailScreen(licenceId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) {
                          final id = state.pathParameters['id']!;
                          return LicenceEditScreen(licenceId: id);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Tab 1 — Certificates
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.certificatesList,
                builder: (context, state) => const CertificatesListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) =>
                        const CertificateAddScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return CertificateDetailScreen(certificateId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) {
                          final id = state.pathParameters['id']!;
                          return CertificateAddScreen(certificateId: id);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Tab 2 — Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const ProfileEditScreen(),
                  ),
                ],
              ),
            ],
          ),
          // Tab 2 — Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

String? _redirect(BuildContext context, GoRouterState state, AppLockPhase lockPhase) {
  // Treat an expired session the same as no session. Without this, an
  // offline user whose token expired (and `tokenRefreshed` never fired)
  // stays on signed-in routes while every Supabase call returns 401 —
  // confusing data-loading errors with no path to re-auth.
  final session = Supabase.instance.client.auth.currentSession;
  final isSignedIn = session != null && !session.isExpired;
  final loc = state.matchedLocation;
  final isAuthRoute = loc.startsWith('/auth/');
  final isPinRoute = loc == Routes.pinSetup || loc == Routes.pinEntry;
  // Legal documents are reachable without sign-in so users can review the
  // Privacy Policy and Terms before sign-in.
  final isLegalRoute = loc.startsWith('/legal/');
  // /share is a public licence-verification page — no sign-in needed.
  final isShareRoute = loc.startsWith('/share');

  if (loc == Routes.splash || loc == Routes.home) {
    return isSignedIn ? Routes.licencesList : Routes.handoff;
  }

  // Unauthenticated: PIN routes are off-limits.
  if (!isSignedIn && isPinRoute) return Routes.email;

  // Handoff is always processed even when a session exists — it needs to
  // clear any stale session and apply the fresh Shell JWT.
  // PIN routes remain accessible when signed in (they ARE the gate).
  if (isSignedIn && isAuthRoute && loc != Routes.handoff && !isPinRoute) {
    return Routes.licencesList;
  }
  if (!isSignedIn && !isAuthRoute && !isLegalRoute && !isShareRoute) {
    return Routes.email;
  }

  // PIN gate — only applies to signed-in users on non-auth/legal/share routes,
  // or when the lock notifier has determined a PIN action is required.
  if (isSignedIn) {
    if (lockPhase == AppLockPhase.pinSetupRequired && !isPinRoute) {
      return Routes.pinSetup;
    }
    if (lockPhase == AppLockPhase.pinEntryRequired && !isPinRoute) {
      return Routes.pinEntry;
    }
    // Once unlocked, bounce away from PIN routes if user somehow navigates back.
    if (lockPhase == AppLockPhase.unlocked && isPinRoute) {
      return Routes.licencesList;
    }
  }

  return null;
}

class _AuthRouterNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/launcher.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              const SizedBox(height: EqSpacing.lg),
              Text(
                'EQ Cards',
                style: EqTypography.headingL.copyWith(
                  fontWeight: FontWeight.w700,
                  color: EqColours.deep,
                ),
              ),
              const SizedBox(height: EqSpacing.xl),
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
    );
  }
}

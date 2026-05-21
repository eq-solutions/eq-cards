import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth.dart';
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
  // Bridge: Riverpod auth-state changes -> ChangeNotifier -> GoRouter refresh.
  final notifier = _AuthRouterNotifier();
  ref.listen(authStateChangesProvider, (_, __) => notifier.bump());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: _redirect,
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),
      // Cards Unit 4 (2026-05-21) — sole auth entry point. Reads
      // #sh=<jwt> from the URL hash and calls Supabase.auth.setSession.
      GoRoute(
        path: Routes.handoff,
        builder: (context, state) => const IframeHandoffScreen(),
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
          // Tab 1 — Profile
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

String? _redirect(BuildContext context, GoRouterState state) {
  // Treat an expired session the same as no session. Without this, an
  // offline user whose token expired (and `tokenRefreshed` never fired)
  // stays on signed-in routes while every Supabase call returns 401 —
  // confusing data-loading errors with no path to re-auth.
  final session = Supabase.instance.client.auth.currentSession;
  final isSignedIn = session != null && !session.isExpired;
  final loc = state.matchedLocation;
  final isAuthRoute = loc.startsWith('/auth/');
  // Legal documents are reachable without sign-in so users can review the
  // Privacy Policy and Terms before sign-in.
  final isLegalRoute = loc.startsWith('/legal/');

  if (loc == Routes.splash || loc == Routes.home) {
    return isSignedIn ? Routes.licencesList : Routes.handoff;
  }
  if (isSignedIn && isAuthRoute) return Routes.licencesList;
  if (!isSignedIn && !isAuthRoute && !isLegalRoute) return Routes.handoff;
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

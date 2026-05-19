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
import 'routes.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  // Bridge: Riverpod auth-state changes -> ChangeNotifier -> GoRouter refresh.
  // ref.listen (not ref.watch) — we re-evaluate the redirect via
  // refreshListenable rather than rebuilding the router on every auth event.
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
      GoRoute(
        path: Routes.emailEntry,
        builder: (context, state) => const EmailEntryScreen(),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (context, state) {
          final email = state.extra as String?;
          if (email == null) return const _MissingEmailScreen();
          return OtpScreen(email: email);
        },
      ),
      // Legal documents — top-level routes outside the shell so they can be
      // reached from anywhere (Settings, signup flow, share sheet, etc.) and
      // present as full-screen single-document views.
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
                  // Static-segment route ('new') BEFORE wildcard (':id') so
                  // GoRouter matches it before falling through to detail.
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
  // Privacy Policy and Terms before creating an account. They still appear
  // in Settings once signed in via the same routes.
  final isLegalRoute = loc.startsWith('/legal/');

  if (loc == Routes.splash || loc == Routes.home) {
    return isSignedIn ? Routes.licencesList : Routes.emailEntry;
  }
  if (isSignedIn && isAuthRoute) return Routes.licencesList;
  if (!isSignedIn && !isAuthRoute && !isLegalRoute) return Routes.emailEntry;
  return null;
}

class _AuthRouterNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _MissingEmailScreen extends StatelessWidget {
  const _MissingEmailScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Missing email parameter')),
    );
  }
}

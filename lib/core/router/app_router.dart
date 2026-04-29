import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth.dart';
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
        path: Routes.phoneEntry,
        builder: (context, state) => const PhoneEntryScreen(),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (context, state) {
          final phone = state.extra as String?;
          if (phone == null) return const _MissingPhoneScreen();
          return OtpScreen(phone: phone);
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
  final isSignedIn = Supabase.instance.client.auth.currentSession != null;
  final loc = state.matchedLocation;
  final isAuthRoute = loc.startsWith('/auth/');

  if (loc == Routes.splash || loc == Routes.home) {
    return isSignedIn ? Routes.licencesList : Routes.phoneEntry;
  }
  if (isSignedIn && isAuthRoute) return Routes.licencesList;
  if (!isSignedIn && !isAuthRoute) return Routes.phoneEntry;
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

class _MissingPhoneScreen extends StatelessWidget {
  const _MissingPhoneScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Missing phone parameter')),
    );
  }
}

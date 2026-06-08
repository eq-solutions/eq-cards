import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth.dart';
// Platform bridge for the Shell iframe handoff. Conditional import: the web
// build pulls in the dart:html implementation, the VM (test) build the stub.
import '../../features/auth/presentation/screens/handoff_platform_io.dart'
    if (dart.library.html) '../../features/auth/presentation/screens/handoff_platform_web.dart';
import '../../features/auth/presentation/screens/not_provisioned_screen.dart';
import '../../features/certificates/certificates.dart';
import '../../features/legal/presentation/screens/legal_document_screen.dart';
import '../../features/licences/licences.dart';
import '../../features/onboarding/presentation/screens/onboarding_done_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_review_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_wallet_step_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_welcome_screen.dart';
import '../../features/profile/profile.dart';
import '../../features/settings/settings.dart';
import '../../features/workers/data/models/worker.dart';
import '../../features/workers/presentation/screens/admin_members_screen.dart';
import '../../features/workers/presentation/screens/admin_worker_detail_screen.dart';
import '../../features/workers/presentation/screens/admin_worker_form_screen.dart';
import '../../features/workers/presentation/screens/claim_invite_screen.dart';
import '../../features/workers/presentation/screens/worker_hr_record_screen.dart';
import '../shell/home_shell_screen.dart';
import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';
import 'pending_claim.dart';
import 'routes.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  // Bridge: Riverpod state changes -> ChangeNotifier -> GoRouter refresh.
  final notifier = _AuthRouterNotifier();
  ref.listen(authStateChangesProvider, (_, _) => notifier.bump());
  ref.listen(profileNotifierProvider, (_, _) => notifier.bump());
  ref.listen(authFlowNotifierProvider, (_, _) => notifier.bump());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final AsyncValue<Profile?> profile = ref.read(profileNotifierProvider);
      final AuthFlowState flowState = ref.read(authFlowNotifierProvider);
      return _redirect(context, state, profile, flowState);
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
      // Authenticated but unprovisioned — user signed in without an invite link.
      GoRoute(
        path: Routes.notProvisioned,
        builder: (context, state) => const NotProvisionedScreen(),
      ),
      // Onboarding wizard — shown on first sign-in when profile is incomplete.
      // Full-screen flows outside the shell (no bottom nav).
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingWelcomeScreen(),
      ),
      GoRoute(
        path: Routes.onboardingProfile,
        builder: (context, state) => const ProfileEditScreen(isOnboarding: true),
      ),
      GoRoute(
        path: Routes.onboardingWallet,
        builder: (context, state) => const OnboardingWalletStepScreen(),
      ),
      GoRoute(
        path: Routes.onboardingReview,
        builder: (context, state) => const OnboardingReviewScreen(),
      ),
      GoRoute(
        path: Routes.onboardingDone,
        builder: (context, state) => const OnboardingDoneScreen(),
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
      // Admin — org admin only; entered from Settings.
      GoRoute(
        path: Routes.adminMembers,
        builder: (context, state) => const AdminMembersScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) {
              final orgId = state.extra! as String;
              return AdminWorkerFormScreen(orgId: orgId);
            },
          ),
          GoRoute(
            path: ':workerId',
            builder: (context, state) {
              final workerId = state.pathParameters['workerId']!;
              final orgId = state.extra! as String;
              return AdminWorkerDetailScreen(workerId: workerId, orgId: orgId);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final (orgId, worker) = state.extra! as (String, Worker);
                  return AdminWorkerFormScreen(orgId: orgId, worker: worker);
                },
              ),
            ],
          ),
        ],
      ),
      // Invite claim — exempt from auth redirect; the screen handles
      // unauthenticated workers itself and prompts them to sign in first.
      GoRoute(
        path: Routes.claim,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return ClaimInviteScreen(token: token);
        },
      ),
      // Join — public QR / join-code onboarding entry point.
      // Exempt from auth redirect so unauthenticated workers can land here.
      GoRoute(
        path: Routes.join,
        builder: (context, state) {
          final tenant = state.uri.queryParameters['tenant'] ?? '';
          return JoinTenantScreen(tenantSlug: tenant);
        },
      ),
      // Worker self-service: APP 12 access to own employment record.
      GoRoute(
        path: Routes.workerHrRecord,
        builder: (context, state) => const WorkerHrRecordScreen(),
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

String? _redirect(
  BuildContext context,
  GoRouterState state,
  AsyncValue<Profile?> profile,
  AuthFlowState flowState,
) {
  // Treat an expired session the same as no session. Without this, an
  // offline user whose token expired (and `tokenRefreshed` never fired)
  // stays on signed-in routes while every Supabase call returns 401 —
  // confusing data-loading errors with no path to re-auth.
  final session = Supabase.instance.client.auth.currentSession;
  final isSignedIn = session != null && !session.isExpired;
  final loc = state.matchedLocation;
  final isAuthRoute = loc.startsWith('/auth/');
  final isOnboardingRoute = loc.startsWith('/onboarding');
  // Legal documents are reachable without sign-in so users can review the
  // Privacy Policy and Terms before sign-in.
  final isLegalRoute = loc.startsWith('/legal/');
  // /share is a public licence-verification page — no sign-in needed.
  final isShareRoute = loc.startsWith('/share');
  // /claim handles its own auth state — unauthenticated workers see a
  // "sign in first" prompt rather than being bounced to the auth flow and
  // losing the token.
  final isClaimRoute = loc.startsWith('/claim');
  // /join is a public onboarding entry — unauthenticated workers land here
  // from QR codes or after entering a join code. No auth redirect.
  final isJoinRoute = loc.startsWith('/join');

  // Provisioning gate: authenticated but tenant_id absent from JWT means the
  // user bypassed the invite flow. Redirect to the not-provisioned screen so
  // they get a clear message rather than silent 401s on every RPC call.
  // The notProvisioned route itself is exempt to avoid an infinite redirect.
  if (isSignedIn) {
    final tenantId = session.user.appMetadata['tenant_id'];
    // No tenant claim → the user bypassed provisioning. Park them on the
    // not-provisioned screen (which is itself exempt to avoid a self-redirect).
    // /claim is ALSO exempt: claiming an invite is precisely how a signed-in
    // worker GETS their tenant, so a tenant-less user must be able to reach the
    // claim screen. Without this the flow dead-ends — sign in by phone (no
    // tenant yet) → bounced to not-provisioned → can never activate.
    // During phone OTP verification the shell exchange runs AFTER GoTrue emits
    // the first onAuthStateChange (raw JWT, no tenant_id). Exempting the OTP
    // screen here keeps the user on the loading spinner instead of flashing
    // through notProvisioned. The second onAuthStateChange (shell JWT, has
    // tenant_id) then routes to licencesList normally.
    final isPhoneExchangeInProgress =
        flowState is AuthFlowVerifying && flowState.isPhone && loc == Routes.otp;
    if (tenantId == null && loc != Routes.notProvisioned && !isClaimRoute && !isJoinRoute && !isPhoneExchangeInProgress) {
      // A worker who signed in FROM an invite link has a session but no tenant
      // yet — the tenant arrives only when they activate. Send them back to the
      // claim screen (where they'll see "Activate my account") rather than
      // dead-ending on not-provisioned. The activate step clears the token.
      final pending = PendingClaim.token;
      if (pending != null && pending.isNotEmpty) {
        return '${Routes.claim}?token=$pending';
      }
      return Routes.notProvisioned;
    }
    // A provisioned user must never sit on the not-provisioned screen. Without
    // this, the auth-route bounce below is the only thing that moves them off
    // it — and for a tenant-less user that bounce vs. the gate above forms a
    // redirect loop (/auth/not-provisioned <=> /licences). Handle it here so
    // the auth-route rule can safely exempt not-provisioned.
    if (tenantId != null && loc == Routes.notProvisioned) {
      return Routes.licencesList;
    }
  }
  // Signed-out users on the notProvisioned route go back to sign-in.
  if (!isSignedIn && loc == Routes.notProvisioned) {
    final inShellIframeEarly = kIsWeb && HandoffPlatform.isInIframe();
    return inShellIframeEarly ? Routes.handoff : Routes.email;
  }

  // Inside the Shell iframe, a missing/expired session must re-run the silent
  // handoff (postMessage re-auth) — NOT bounce to email OTP. Shell-minted JWTs
  // carry no Supabase refresh_token, so the only way to renew is a fresh mint
  // from the parent shell, which the handoff screen requests on entry.
  final inShellIframe = kIsWeb && HandoffPlatform.isInIframe();
  final signedOutDestination = inShellIframe ? Routes.handoff : Routes.email;

  // Onboarding routes require sign-in; bounce unauthenticated visitors.
  if (!isSignedIn && isOnboardingRoute) return signedOutDestination;
  // Only redirect the root welcome screen away when profile is already
  // complete — sub-routes (/wallet, /review, /done) must flow freely so
  // the wizard continues after profile is saved in step 2.
  if (isSignedIn && loc == Routes.onboarding) {
    final isComplete = profile.value?.isComplete ?? false;
    if (isComplete) return Routes.licencesList;
  }

  if (loc == Routes.splash || loc == Routes.home) {
    if (!isSignedIn) return Routes.handoff;
    // Wait for profile to load before deciding where to send the user. The
    // notifier listens to profileNotifierProvider so a second bump fires once
    // the AsyncData arrives and this branch is re-evaluated.
    if (profile is! AsyncData) return null;
    final isComplete = profile.value?.isComplete ?? false;
    return isComplete ? Routes.licencesList : Routes.onboarding;
  }

  // Handoff is always processed even when a session exists — it needs to
  // clear any stale session and apply the fresh Shell JWT.
  // not-provisioned is exempt: a tenant-less user belongs there, and the gate
  // above already moves a provisioned user off it. Bouncing it here would loop.
  if (isSignedIn &&
      isAuthRoute &&
      loc != Routes.handoff &&
      loc != Routes.notProvisioned) {
    return Routes.licencesList;
  }
  if (!isSignedIn && !isAuthRoute && !isLegalRoute && !isShareRoute && !isClaimRoute && !isJoinRoute) {
    return signedOutDestination;
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
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
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

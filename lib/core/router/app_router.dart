import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth.dart';
import '../../features/auth/presentation/screens/not_provisioned_screen.dart';
import '../../features/certificates/certificates.dart';
import '../../features/connections/presentation/screens/connect_to_company_screen.dart';
import '../../features/legal/presentation/screens/legal_document_screen.dart';
import '../../features/licences/licences.dart';
import '../../features/profile/profile.dart';
import '../../features/settings/settings.dart';
import '../../features/workers/data/models/worker.dart';
import '../../features/workers/presentation/screens/admin_members_screen.dart';
import '../../features/workers/presentation/screens/admin_worker_detail_screen.dart';
import '../../features/workers/presentation/screens/admin_worker_form_screen.dart';
import '../../features/workers/presentation/screens/claim_by_phone_screen.dart';
import '../../features/workers/presentation/screens/claim_invite_screen.dart';
import '../../features/workers/presentation/screens/worker_hr_record_screen.dart';
import '../shell/home_shell_screen.dart';
import '../shell/shell_bridge.dart';
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
  ref.listen(authFlowNotifierProvider, (_, _) => notifier.bump());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final AuthFlowState flowState = ref.read(authFlowNotifierProvider);
      return _redirect(context, state, flowState);
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),
      // Shell iframe entry point — shows splash while the router redirect fires.
      GoRoute(
        path: Routes.handoff,
        builder: (context, state) => const _SplashScreen(),
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
          final token  = state.uri.queryParameters['token']  ?? '';
          final tenant = state.uri.queryParameters['tenant'] ?? '';
          // QR scan path: no token, but tenant slug present.
          // Worker enters their phone → lookup RPC → redirect to /claim?token=
          if (token.isEmpty && tenant.isNotEmpty) {
            return ClaimByPhoneScreen(tenantSlug: tenant);
          }
          return ClaimInviteScreen(token: token);
        },
      ),
      // Join — public QR / join-code onboarding entry point.
      // Exempt from auth redirect so unauthenticated workers can land here.
      // Supports ?tenant=<slug>&name=<org+name> — name is optional; QR admin
      // page encodes it so the screen can show the real org name without a
      // network fetch.
      GoRoute(
        path: Routes.join,
        builder: (context, state) {
          final tenant = state.uri.queryParameters['tenant'] ?? '';
          final name = state.uri.queryParameters['name'];
          return JoinTenantScreen(tenantSlug: tenant, tenantName: name);
        },
      ),
      // Provision — org admin self-provisions a new workspace via a one-time link.
      // ?token=<uuid>&name=<orgName>  (name is an optional display hint)
      // Public route — exempt from auth redirect; the provision token is the gate.
      GoRoute(
        path: Routes.provision,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          final name = state.uri.queryParameters['name'];
          return ProvisionTenantScreen(provisionToken: token, orgName: name);
        },
      ),
      // Worker self-service: APP 12 access to own employment record.
      GoRoute(
        path: Routes.workerHrRecord,
        builder: (context, state) => const WorkerHrRecordScreen(),
      ),
      // Self-signup company discovery — worker finds employers and submits an application.
      GoRoute(
        path: Routes.connect,
        builder: (context, state) => const ConnectToCompanyScreen(),
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
      // Settings — accessible from Profile; pushed full-screen outside the shell.
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      // /card is a legacy route — redirect to the wallet (Licences tab).
      // Existing deep-links in SMS/email still work after the 3→2 tab merge.
      GoRoute(
        path: Routes.card,
        redirect: (_, _) => Routes.licencesList,
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navShell) =>
            HomeShellScreen(navigationShell: navShell),
        branches: [
          // Tab 0 — Wallet (licences & certificates combined)
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
              // Certificate routes share the Licences branch so the bottom
              // nav stays visible and the tab highlight stays on "Licences".
              GoRoute(
                path: Routes.certificatesList,
                builder: (context, state) => const CertificatesListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => CertificateAddScreen(
                      prefill: state.extra as CertPrefill?,
                    ),
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
          // Tab 2 — Profile (includes workspaces + sign out)
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
        ],
      ),
    ],
  );
}

String? _redirect(
  BuildContext context,
  GoRouterState state,
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
  // /provision is a public self-serve setup entry — org admins land here from
  // a one-time provision link. The token is the gate; no auth required.
  final isProvisionRoute = loc.startsWith('/provision');

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
    // through notProvisioned. Once the exchange completes and the session
    // refreshes with tenant_id, the router re-evaluates and routes normally.
    final isPhoneExchangeInProgress =
        flowState is AuthFlowVerifying && flowState.isPhone && loc == Routes.otp;
    if (tenantId == null && loc != Routes.notProvisioned && !isClaimRoute && !isJoinRoute && !isProvisionRoute && !isPhoneExchangeInProgress) {
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
    return Routes.email;
  }
  // Signed-out users on the Shell handoff route go to sign-in, UNLESS the
  // iframe was loaded by Shell with ?shell=1. In that case, let _SplashScreen
  // request a token from the parent frame via shell_bridge — redirecting here
  // would kill the postMessage flow before it starts.
  if (!isSignedIn && loc == Routes.handoff) {
    if (state.uri.queryParameters['shell'] == '1') return null;
    return Routes.email;
  }

  const signedOutDestination = Routes.email;

  if (loc == Routes.splash) {
    if (!isSignedIn) {
      // If there's an expired session (access token stale, refresh token may
      // still be valid), stay on splash while _SplashScreen triggers an
      // explicit refreshSession(). The router re-evaluates when
      // onAuthStateChange fires TokenRefreshed (→ /card) or signedOut
      // (→ /email). Without this, the router bounces to /email before the
      // async startup refresh completes — visible as a sign-in flash on every
      // cold open for iOS PWA users whose JWT expired while the app was closed.
      if (Supabase.instance.client.auth.currentSession != null) return null;
      return Routes.email;
    }
    // Signed-in users at the root always have a workspace by this point — the
    // provisioning gate above redirects tenant-less users away. Go straight to
    // the wallet. The onboarding wizard is no longer a forced step (it was
    // cancelled — payroll PII out of scope); the soft "complete your profile"
    // banner inside the wallet handles the nudge instead. No profile wait.
    return Routes.card;
  }

  // not-provisioned is exempt: a tenant-less user belongs there, and the gate
  // above already moves a provisioned user off it. Bouncing it here would loop.
  // OTP screen is exempt: the shell exchange runs AFTER GoTrue emits the auth
  // event; bouncing here drops the user off OTP before _resolveAndLand() can
  // navigate deterministically. OTP handles its own post-verify routing.
  if (isSignedIn &&
      isAuthRoute &&
      loc != Routes.notProvisioned &&
      loc != Routes.otp) {
    return Routes.card;
  }
  if (!isSignedIn && !isAuthRoute && !isLegalRoute && !isShareRoute && !isClaimRoute && !isJoinRoute && !isProvisionRoute) {
    return signedOutDestination;
  }

  return null;
}

class _AuthRouterNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    // When loaded by Shell iframe with ?shell=1 and no session, request a
    // token hash from the parent frame. Shell returns a GoTrue magic-link
    // hashed_token; verifyOTP creates a real auth.sessions row (with
    // refresh_token) so future refreshSession() calls work correctly.
    // On any failure, falls back to _ensureSession() → router sends to /email.
    if (kIsWeb && Uri.base.queryParameters['shell'] == '1' &&
        Supabase.instance.client.auth.currentSession == null) {
      unawaited(_handleShellHandoff());
    } else {
      unawaited(_ensureSession());
    }
  }

  Future<void> _handleShellHandoff() async {
    final tokenHash = await requestAndReceiveShellToken();
    if (!mounted) return;
    if (tokenHash == null) {
      // Shell handshake timed out or Shell reported an error. Try refreshing
      // any stored session first; if there's nothing to refresh (first open,
      // or stale refresh token), send the user to the email sign-in screen so
      // they're not stuck on the spinner indefinitely.
      await _ensureSession();
      if (mounted && Supabase.instance.client.auth.currentSession == null) {
        context.go(Routes.email);
      }
      return;
    }
    try {
      await Supabase.instance.client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.magiclink,
      );
      // onAuthStateChange fires signedIn → GoRouter re-evaluates → /card
    } catch (_) {
      if (mounted) unawaited(_ensureSession());
    }
  }

  // If the stored session has an expired access token, trigger an explicit
  // refresh immediately. supabase-flutter starts its own internal refresh
  // timer, but on iOS PWA cold-start that timer may not fire before the
  // router's first redirect evaluation — causing a sign-in screen flash even
  // when the user has a valid refresh token. Calling refreshSession() here
  // races ahead of the timer: on success TokenRefreshed fires → router goes
  // to /card; on failure (expired or revoked refresh token) signOut fires →
  // router goes to /email.
  Future<void> _ensureSession() async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null || !session.isExpired) return;
    try {
      await auth.refreshSession().timeout(const Duration(seconds: 15));
    } catch (_) {
      try {
        await auth.signOut();
      } catch (_) {}
    }
  }

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

// Auth repository — sign-in paths:
//   1. Phone OTP: verifyPhoneOtp() calls GoTrue, then (if the
//      custom_access_token_hook is not yet active) phoneOtpShellExchange() to
//      set the eq_shell_session cookie on core.eq.solutions.
//   2. Email OTP: sendOtp() / verifyOtp() wrap Supabase gotrue methods.
//   - joinTenantExchange() — claim/join-code flow post-verification.
//   - signOut() — the only outbound auth action the Cards UI takes.
//   - Breadcrumb helpers for Sentry diagnostics.
//
// When custom_access_token_hook is enabled on eq-canonical the GoTrue JWT
// natively carries tenant_id via app_metadata, so phoneOtpShellExchange is
// skipped (see the tenantId == null guard in verifyPhoneOtp). The Shell
// exchange call is retained as a fallback for non-hook environments.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';

part 'auth_repository.g.dart';

/// Shell base URL — same constant as CardsApi. Overridable at build time:
///   flutter run --dart-define=SHELL_BASE_URL=http://localhost:8888
const _kShellBaseUrl = String.fromEnvironment(
  'SHELL_BASE_URL',
  defaultValue: 'https://core.eq.solutions',
);

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  /// Send a 6-digit OTP to [email]. The Supabase project must have email OTP
  /// enabled in Auth → Email → "Enable Email OTP" (distinct from magic links).
  Future<void> sendOtp(String email) async {
    unawaited(_breadcrumb('otp_send_started', {'email': email}));
    try {
      await _client.auth.signInWithOtp(email: email);
      unawaited(_breadcrumb('otp_send_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('otp_send_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  /// Verify the 6-digit [token] for [email]. On success, Supabase establishes
  /// a session; GoRouter's auth listener picks it up and redirects.
  Future<void> verifyOtp(String email, String token) async {
    unawaited(_breadcrumb('otp_verify_started'));
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      unawaited(_breadcrumb('otp_verify_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('otp_verify_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  /// Send a 6-digit SMS OTP to [e164Phone] (E.164 format, e.g. +61412345678).
  /// Requires Twilio configured as the SMS provider in Supabase Auth settings.
  Future<void> sendPhoneOtp(String e164Phone) async {
    unawaited(_breadcrumb('phone_otp_send_started', {'phone': e164Phone}));
    try {
      await _client.auth.signInWithOtp(phone: e164Phone);
      unawaited(_breadcrumb('phone_otp_send_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('phone_otp_send_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  /// Verify the 6-digit SMS [token] for [e164Phone].
  ///
  /// After GoTrue accepts the OTP, the resulting session has no
  /// app_metadata.tenant_id (the custom_access_token_hook is not yet enabled).
  /// This method calls [phoneOtpShellExchange] immediately after to swap the
  /// raw GoTrue JWT for a shell-minted JWT that carries tenant_id, then calls
  /// setSession() with that JWT. GoRouter's auth listener picks up the new
  /// session and redirects — no extra plumbing needed at the call site.
  Future<void> verifyPhoneOtp(String e164Phone, String token) async {
    unawaited(_breadcrumb('phone_otp_verify_started'));
    try {
      final res = await _client.auth.verifyOTP(
        phone: e164Phone,
        token: token,
        type: OtpType.sms,
      );
      unawaited(_breadcrumb('phone_otp_verify_succeeded'));

      final accessToken = res.session?.accessToken;
      if (accessToken != null) {
        // Skip the exchange when the custom_access_token_hook has already
        // embedded tenant_id — calling setSession() would replace the
        // hook-minted JWT with the older shell JWT.
        final tenantId = res.session?.user.appMetadata['tenant_id'];
        if (tenantId == null) {
          await phoneOtpShellExchange(e164Phone, accessToken);
        }
      }
    } catch (e) {
      unawaited(_breadcrumb('phone_otp_verify_failed', {'error': e.toString()}));
      if (e is Failure) rethrow;
      throw mapSupabaseError(e);
    }
  }

  /// Exchanges a raw GoTrue phone-OTP access token for a shell-minted Supabase
  /// JWT that carries app_metadata.tenant_id.
  ///
  /// Calls POST /.netlify/functions/shell-login-phone-otp on the Shell with
  /// { phone, access_token }. On success the Shell returns a supabase_jwt
  /// (short-lived HS256 JWT with tenant_id in app_metadata); Cards calls
  /// setSession() to replace the raw GoTrue session with this one.
  ///
  /// Failures are non-fatal at the GoRouter level: if the user is not in
  /// shell_control.users the Shell returns { valid: false }, the exchange
  /// silently does nothing, auth_state_provider detects the missing tenant_id
  /// and routes to the notProvisioned screen instead of authenticated. The
  /// user sees "No workspace access" and is asked to contact their manager.
  ///
  /// Note: this method is a bridge until the custom_access_token_hook is
  /// enabled on eq-canonical. Once it is, the GoTrue JWT will carry tenant_id
  /// natively and this exchange call becomes redundant. See
  /// docs/cards-canonical-api-rewire.md §5 and supabase/manual/.
  Future<void> phoneOtpShellExchange(
    String e164Phone,
    String accessToken,
  ) async {
    unawaited(_breadcrumb('phone_otp_shell_exchange_started'));
    try {
      final uri = Uri.parse(
        '$_kShellBaseUrl/.netlify/functions/shell-login-phone-otp',
      );
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': e164Phone, 'access_token': accessToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        // Shell rate-limited the exchange — surface it to the user instead of
        // silently routing them to the notProvisioned screen.
        unawaited(_breadcrumb('phone_otp_shell_exchange_rate_limited'));
        await _client.auth.signOut();
        throw const ServerFailure(429, 'rate-limited');
      }

      if (response.statusCode != 200) {
        unawaited(
          _breadcrumb('phone_otp_shell_exchange_http_error', {
            'status': response.statusCode,
          }),
        );
        // Non-200 (e.g. 500 from a misconfigured Shell) — don't crash the auth
        // flow. auth_state_provider will detect missing tenant_id and route to
        // notProvisioned. Capture for diagnostics.
        unawaited(
          Sentry.captureMessage(
            'phoneOtpShellExchange: unexpected HTTP ${response.statusCode}',
            level: SentryLevel.warning,
          ),
        );
        return;
      }

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        unawaited(_breadcrumb('phone_otp_shell_exchange_parse_error'));
        return;
      }

      if (body['valid'] != true) {
        // Shell returned valid:false — user not in shell_control.users, phone
        // mismatch, or a transient error (GoTrue token reject, inactive tenant).
        // Sign out so GoRouter clears back to the phone sign-in screen. The
        // user can retry immediately; if the problem persists they contact their
        // manager. Signing out is preferable to leaving the user on the
        // notProvisioned screen with no actionable path.
        unawaited(_breadcrumb('phone_otp_shell_exchange_not_provisioned'));
        await _client.auth.signOut();
        return;
      }

      // Shell validated the user and set the eq_shell_session cookie on
      // core.eq.solutions. With custom_access_token_hook enabled the GoTrue JWT
      // already carries tenant_id from the initial verifyOTP call, so we do not
      // need to call setSession here — gotrue_dart 2.20.0+ calls getUser()
      // server-side inside setSession, which rejects shell-minted JWTs because
      // they have no row in auth.sessions (→ session_not_found).
      unawaited(_breadcrumb('phone_otp_shell_exchange_succeeded'));
    } catch (e, st) {
      // Mapped failures (e.g. 429 rate-limit) must surface to the caller.
      if (e is Failure) rethrow;
      // Exchange failure is non-fatal — user lands on notProvisioned rather
      // than crashing. Capture for diagnostics.
      unawaited(_breadcrumb('phone_otp_shell_exchange_exception', {'error': e.toString()}));
      unawaited(Sentry.captureException(e, stackTrace: st));
    }
  }

  /// Sign in via Google OAuth. On web, redirects to Google then back to the
  /// app at `redirectTo`. Supabase picks up the session from the URL fragment
  /// on return — no extra handling needed in the app.
  ///
  /// Requires Google configured as an OAuth provider in Supabase Auth settings
  /// with the Supabase callback URL added to the Google Cloud Console.
  Future<void> signInWithGoogle() async {
    unawaited(_breadcrumb('google_signin_started'));
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        // Web: redirect back to the PWA root after Google auth.
        // Native iOS/Android: use the custom URL scheme registered in
        // AndroidManifest.xml and Info.plist so the OS routes the callback
        // back to the app and supabase_flutter's deep-link listener picks it up.
        redirectTo: kIsWeb
            ? 'https://cards.eq.solutions'
            : 'io.supabase.eqcards://login-callback/',
      );
      // On web, the page redirects — execution doesn't continue here.
      // Session is established when the app reloads on the callback URL.
    } catch (e) {
      unawaited(_breadcrumb('google_signin_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  /// Verify the 6-digit SMS [token] for [e164Phone] without performing the
  /// shell exchange. Returns the raw GoTrue access token on success, or null
  /// if the session was not established.
  ///
  /// Used in the join-tenant flow where a separate [joinTenantExchange] call
  /// follows with a specific tenantSlug, rather than the generic
  /// shell-login-phone-otp exchange used by [verifyPhoneOtp].
  Future<String?> verifyPhoneOtpOnly(
    String e164Phone,
    String token,
  ) async {
    unawaited(_breadcrumb('phone_otp_verify_only_started'));
    try {
      final res = await _client.auth.verifyOTP(
        phone: e164Phone,
        token: token,
        type: OtpType.sms,
      );
      unawaited(_breadcrumb('phone_otp_verify_only_succeeded'));
      return res.session?.accessToken;
    } catch (e) {
      unawaited(_breadcrumb('phone_otp_verify_only_failed', {'error': e.toString()}));
      if (e is Failure) rethrow;
      throw mapSupabaseError(e);
    }
  }

  /// Calls the Shell's shell-join-tenant function to provision the worker into
  /// [tenantSlug] using their GoTrue [accessToken].
  ///
  /// On success (valid: true) the Shell returns a tenant-scoped Supabase JWT
  /// and Cards calls setSession() with it. On valid: false the worker has no
  /// account under that tenant — signOut() is called and a [ValidationFailure]
  /// is thrown with a human-readable message.
  Future<void> joinTenantExchange(
    String e164Phone,
    String accessToken,
    String tenantSlug,
  ) async {
    unawaited(_breadcrumb('join_tenant_exchange_started', {'tenant': tenantSlug}));
    try {
      final uri = Uri.parse(
        '$_kShellBaseUrl/.netlify/functions/shell-join-tenant',
      );
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': e164Phone,
              'access_token': accessToken,
              'tenant_slug': tenantSlug,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        unawaited(
          _breadcrumb('join_tenant_exchange_http_error', {
            'status': response.statusCode,
          }),
        );
        unawaited(
          Sentry.captureMessage(
            'joinTenantExchange: unexpected HTTP ${response.statusCode}',
            level: SentryLevel.warning,
          ),
        );
        await _client.auth.signOut();
        throw const ValidationFailure(
          'Something went wrong joining the team. Please try again.',
        );
      }

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        unawaited(_breadcrumb('join_tenant_exchange_parse_error'));
        await _client.auth.signOut();
        throw const ValidationFailure(
          'Something went wrong joining the team. Please try again.',
        );
      }

      if (body['valid'] != true) {
        unawaited(_breadcrumb('join_tenant_not_provisioned', {'tenant': tenantSlug}));
        await _client.auth.signOut();
        throw const ValidationFailure(
          'No account found for this number. Check your join code or contact your manager.',
        );
      }

      // Shell set the cookie and validated the user. Refresh the GoTrue session
      // so the hook injects the new tenant_id into the JWT.
      // gotrue_dart 2.20.0+ calls getUser() inside setSession, which rejects
      // shell-minted JWTs → use native refreshSession() instead.
      try {
        await _client.auth.refreshSession();
      } catch (_) {
        // Non-fatal — the hook may already have tenant_id in the current JWT
        // if the session was just minted. Proceed and let the router decide.
      }
      unawaited(_breadcrumb('join_tenant_exchange_succeeded', {'tenant': tenantSlug}));
    } on Failure {
      rethrow;
    } catch (e, st) {
      unawaited(_breadcrumb('join_tenant_exchange_exception', {'error': e.toString()}));
      unawaited(Sentry.captureException(e, stackTrace: st));
      await _client.auth.signOut();
      throw const ValidationFailure(
        'Something went wrong joining the team. Please try again.',
      );
    }
  }

  /// Calls the Shell's shell-provision-tenant function to atomically create a
  /// new tenant workspace for [provisionToken].
  ///
  /// The provision token is a one-time UUID issued by a platform admin via
  /// shell-create-provision-token. On success the Shell creates all required
  /// DB rows (tenants, users, org_memberships etc.) and returns the new
  /// [tenantSlug] and [accessToken] (echoed back so Shell can auto-login the
  /// admin via shell-handoff-provision — no second OTP required).
  ///
  /// Returns a record `(tenantSlug, accessToken)`. Either value may be null on
  /// partial server responses; callers should handle null gracefully.
  ///
  /// Throws [ValidationFailure] with a user-facing message on any error,
  /// including a duplicate-use attempt (409).
  Future<(String?, String?)> provisionTenantExchange(
    String e164Phone,
    String accessToken,
    String provisionToken,
  ) async {
    unawaited(_breadcrumb('provision_tenant_exchange_started'));
    try {
      final uri = Uri.parse(
        '$_kShellBaseUrl/.netlify/functions/shell-provision-tenant',
      );
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': e164Phone,
              'access_token': accessToken,
              'provision_token': provisionToken,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        unawaited(_breadcrumb('provision_tenant_exchange_parse_error'));
        throw const ValidationFailure(
          'Something went wrong setting up your workspace. Please try again.',
        );
      }

      if (response.statusCode == 409) {
        unawaited(_breadcrumb('provision_tenant_exchange_link_used'));
        throw ValidationFailure(
          (body['error'] as String?) ??
              'This invitation link has already been used.',
        );
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        unawaited(
          _breadcrumb('provision_tenant_exchange_http_error', {
            'status': response.statusCode,
          }),
        );
        unawaited(
          Sentry.captureMessage(
            'provisionTenantExchange: unexpected HTTP ${response.statusCode}',
            level: SentryLevel.warning,
          ),
        );
        throw ValidationFailure(
          (body['error'] as String?) ??
              'Something went wrong setting up your workspace. Please try again.',
        );
      }

      if (body['valid'] != true) {
        unawaited(_breadcrumb('provision_tenant_exchange_invalid'));
        throw ValidationFailure(
          (body['error'] as String?) ??
              'Invalid or expired invitation link.',
        );
      }

      unawaited(_breadcrumb('provision_tenant_exchange_succeeded'));
      return (
        body['tenant_slug'] as String?,
        body['access_token'] as String?,
      );
    } on Failure {
      rethrow;
    } catch (e, st) {
      unawaited(
        _breadcrumb('provision_tenant_exchange_exception', {'error': e.toString()}),
      );
      unawaited(Sentry.captureException(e, stackTrace: st));
      throw const ValidationFailure(
        'Something went wrong setting up your workspace. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    unawaited(_breadcrumb('sign_out_started'));
    try {
      await _client.auth.signOut();
    } catch (e) {
      unawaited(_breadcrumb('sign_out_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  Future<void> _breadcrumb(String message, [Map<String, dynamic>? data]) {
    return Sentry.addBreadcrumb(
      Breadcrumb(category: 'auth', message: message, data: data),
    );
  }
}

@riverpod
AuthRepository authRepository(Ref ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
}

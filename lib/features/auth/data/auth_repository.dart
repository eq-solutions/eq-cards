// Auth repository — three sign-in paths:
//   1. Shell handoff: JWT minted by Shell, passed via #sh= URL hash.
//      acceptHandoff() applies it as the active Supabase session.
//   2. Email OTP: user types email, receives a 6-digit code, verifies it.
//      sendOtp() / verifyOtp() wrap the Supabase gotrue methods.
//   3. Google OAuth: signInWithGoogle() triggers Supabase's OAuth flow.
//      On web, redirects to Google then back to the app — no extra package.
//   - signOut() — the only outbound auth action the Cards UI takes
//   - Breadcrumb helpers for Sentry diagnostics
//
// Phone OTP sign-in requires a second step: after GoTrue verifies the SMS code
// the raw GoTrue JWT carries no app_metadata.tenant_id (the Supabase
// custom_access_token_hook that would inject it has not been enabled yet —
// see docs/cards-canonical-api-rewire.md §5 and supabase/manual/). As a
// bridge, phoneOtpShellExchange() calls the Shell's shell-login-phone-otp
// function, which looks up the user in shell_control.users and returns a
// shell-minted Supabase JWT that already contains tenant_id. Cards then calls
// setSession() with that JWT so every subsequent operation (RLS, cards-api
// gateway) sees the tenant claim correctly.
//
// Once the custom_access_token_hook is enabled and verified on eq-canonical,
// the exchange call becomes redundant (the GoTrue JWT will carry tenant_id
// natively) and can be removed — the auth state listener in
// auth_state_provider.dart will continue to work unchanged.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
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

  /// Apply a shell-minted JWT as the active Supabase session.
  /// Throws a mapped Failure on rejection.
  ///
  /// The shell-minted token IS the access token (HS256 signed with the
  /// canonical project JWT secret); there's no separate refresh token.
  /// gotrue's setSession(refreshToken, {accessToken}) uses the access-
  /// token branch when both are supplied — no /token grant_type=refresh
  /// round-trip, just a getUser(accessToken) validation. We pass the
  /// same token in both slots; the refreshToken slot is stored on the
  /// Session but never used (we re-mint via the shell instead of
  /// refreshing).
  Future<void> acceptHandoff(String accessToken) async {
    unawaited(_breadcrumb('handoff_accept_started'));
    try {
      await _client.auth.setSession(accessToken, accessToken: accessToken);
      unawaited(_breadcrumb('handoff_accept_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('handoff_accept_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

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
        await phoneOtpShellExchange(e164Phone, accessToken);
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
  @visibleForTesting
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
        // User not in shell_control.users — notProvisioned route handles this.
        unawaited(_breadcrumb('phone_otp_shell_exchange_not_provisioned'));
        return;
      }

      final supabaseJwt = body['supabase_jwt'] as String?;
      if (supabaseJwt == null || supabaseJwt.isEmpty) {
        unawaited(_breadcrumb('phone_otp_shell_exchange_missing_jwt'));
        return;
      }

      // Replace the raw GoTrue session with the shell-minted JWT that carries
      // tenant_id. Pattern mirrors IframeHandoffScreen._applyToken and the
      // shell-verify handoff path.
      await _client.auth.setSession(supabaseJwt, accessToken: supabaseJwt);
      unawaited(_breadcrumb('phone_otp_shell_exchange_succeeded'));
    } catch (e, st) {
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

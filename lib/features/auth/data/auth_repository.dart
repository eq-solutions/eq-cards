// Auth repository — three sign-in paths:
//   1. Shell handoff: JWT minted by Shell, passed via #sh= URL hash.
//      acceptHandoff() applies it as the active Supabase session.
//   2. Email OTP: user types email, receives a 6-digit code, verifies it.
//      sendOtp() / verifyOtp() wrap the Supabase gotrue methods.
//   3. Google OAuth: signInWithGoogle() triggers Supabase's OAuth flow.
//      On web, redirects to Google then back to the app — no extra package.
//   - signOut() — the only outbound auth action the Cards UI takes
//   - Breadcrumb helpers for Sentry diagnostics

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';

part 'auth_repository.g.dart';

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

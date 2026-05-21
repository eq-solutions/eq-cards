// Cards Unit 4 (2026-05-21) — email-OTP sign-in is gone. Cards now
// authenticates via a JWT minted by the shell and passed in the
// URL hash. See IframeHandoffScreen for the consumer.
//
// What's left here:
//   - signOut() — the only outbound auth action the Cards UI takes
//   - acceptHandoff() — applies a shell-minted JWT as the active
//     Supabase session
//   - Breadcrumb helpers for Sentry diagnostics

import 'dart:async';

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
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
}

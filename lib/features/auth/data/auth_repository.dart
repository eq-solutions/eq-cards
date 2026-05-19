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

  Future<void> sendOtp(String email) async {
    unawaited(_breadcrumb('send_otp_started', {'email_hint': _hint(email)}));
    try {
      await _client.auth.signInWithOtp(email: email);
      unawaited(_breadcrumb('send_otp_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('send_otp_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  Future<void> verifyOtp(String email, String code) async {
    unawaited(_breadcrumb('verify_otp_started'));
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      unawaited(_breadcrumb('verify_otp_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('verify_otp_failed', {'error': e.toString()}));
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

  /// Masked email hint (first char + domain) for breadcrumb diagnostics —
  /// enough to cross-reference a support ticket without writing the full
  /// address into the Sentry trail.
  /// `royce@example.com` -> `r***@example.com`
  String _hint(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return '***';
    final firstChar = email.substring(0, 1);
    final domain = email.substring(at);
    return '$firstChar***$domain';
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

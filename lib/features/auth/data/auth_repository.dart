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

  Future<void> sendOtp(String phone) async {
    unawaited(_breadcrumb('send_otp_started', {'phone_prefix': _prefix(phone)}));
    try {
      await _client.auth.signInWithOtp(phone: phone);
      unawaited(_breadcrumb('send_otp_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('send_otp_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  Future<void> verifyOtp(String phone, String code) async {
    unawaited(_breadcrumb('verify_otp_started'));
    try {
      await _client.auth.verifyOTP(
        phone: phone,
        token: code,
        type: OtpType.sms,
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

  /// Last 4 digits of the phone — enough for cross-checking against
  /// support tickets ("did the user fail to OTP?") without storing the
  /// full number in the breadcrumb trail.
  String _prefix(String phone) {
    if (phone.length < 4) return '****';
    return '...${phone.substring(phone.length - 4)}';
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

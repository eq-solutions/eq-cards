import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Future<void> sendOtp(String phone) async {
    try {
      await _client.auth.signInWithOtp(phone: phone);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> verifyOtp(String phone, String code) async {
    try {
      await _client.auth.verifyOTP(
        phone: phone,
        token: code,
        type: OtpType.sms,
      );
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
}

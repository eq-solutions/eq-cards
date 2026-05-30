import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';

part 'pin_repository.g.dart';

class PinRepository {
  PinRepository(this._client);
  final SupabaseClient _client;

  /// Returns true if the current user has a PIN set in shell_control.users.
  Future<bool> hasPin() async {
    try {
      final result = await _client.rpc<dynamic>('has_pin');
      return result as bool? ?? false;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Hash and store [pin] server-side via pgcrypto. [pin] must be 4 digits.
  Future<void> setPin(String pin) async {
    try {
      await _client.rpc<dynamic>('set_pin', params: {'p_pin': pin});
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Returns true if [pin] matches the stored hash for the current user.
  Future<bool> verifyPin(String pin) async {
    try {
      final result =
          await _client.rpc<dynamic>('verify_pin', params: {'p_pin': pin});
      return result as bool? ?? false;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

@riverpod
PinRepository pinRepository(PinRepositoryRef ref) =>
    PinRepository(ref.watch(supabaseClientProvider));

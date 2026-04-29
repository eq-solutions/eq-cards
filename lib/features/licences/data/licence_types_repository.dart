import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'models/licence_type.dart';

part 'licence_types_repository.g.dart';

class LicenceTypesRepository {
  LicenceTypesRepository(this._client);
  final SupabaseClient _client;

  Future<List<LicenceType>> getAll() async {
    try {
      final rows = await _client
          .from('licence_types')
          .select()
          .order('label');
      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(LicenceType.fromJson)
          .toList();
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<LicenceType> createCustom({
    required String code,
    required String label,
    bool requiresState = false,
    int? defaultValidityMonths,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthenticatedFailure();
    try {
      final row = await _client
          .from('licence_types')
          .insert({
            'code': code,
            'label': label,
            'requires_state': requiresState,
            'default_validity_months': defaultValidityMonths,
            'is_custom': true,
            'user_id': userId,
          })
          .select()
          .single();
      return LicenceType.fromJson(row);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

@riverpod
LicenceTypesRepository licenceTypesRepository(
  LicenceTypesRepositoryRef ref,
) {
  return LicenceTypesRepository(ref.watch(supabaseClientProvider));
}

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'models/profile.dart';

part 'profile_repository.g.dart';

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<Profile?> getCurrent() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthenticatedFailure();
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      return row == null ? null : Profile.fromJson(row);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Profile> upsert(Profile profile) async {
    try {
      final row = await _client
          .from('profiles')
          .upsert(profileToUpsertPayload(profile))
          .select()
          .single();
      return Profile.fromJson(row);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

/// Builds the JSON payload for an upsert. Pure — no Supabase client involved
/// — so it's unit-testable without faking the data source.
///
/// Server-managed columns (`created_at`, `updated_at`, `deleted_at`) are
/// deliberately omitted; Postgres triggers and defaults populate them.
@visibleForTesting
Map<String, dynamic> profileToUpsertPayload(Profile p) {
  final payload = <String, dynamic>{'id': p.id};
  if (p.fullName != null) payload['full_name'] = p.fullName;
  if (p.dateOfBirth != null) {
    payload['date_of_birth'] = _isoDate(p.dateOfBirth!);
  }
  if (p.mobile != null) payload['mobile'] = p.mobile;
  if (p.email != null) payload['email'] = p.email;
  if (p.addressStreet != null) payload['address_street'] = p.addressStreet;
  if (p.addressSuburb != null) payload['address_suburb'] = p.addressSuburb;
  if (p.addressState != null) payload['address_state'] = p.addressState;
  if (p.addressPostcode != null) {
    payload['address_postcode'] = p.addressPostcode;
  }
  if (p.emergencyContactName != null) {
    payload['emergency_contact_name'] = p.emergencyContactName;
  }
  if (p.emergencyContactRelationship != null) {
    payload['emergency_contact_relationship'] = p.emergencyContactRelationship;
  }
  if (p.emergencyContactMobile != null) {
    payload['emergency_contact_mobile'] = p.emergencyContactMobile;
  }
  return payload;
}

String _isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

@riverpod
ProfileRepository profileRepository(ProfileRepositoryRef ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
}

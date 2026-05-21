// Cards Unit 4 (2026-05-21) — calls public.eq_cards_current_staff +
// public.eq_cards_upsert_my_profile on eq-canonical. These RPCs bridge
// the column rename (Cards profiles -> canonical staff): the response
// shape matches what Profile.fromJson expects, so the model is
// unchanged.
//
// The `id` returned IS the canonical staff_id. Cards uses it as the
// "current user identifier" throughout the app (the first segment of
// photo storage paths used to be auth.uid(); post-flip it should be
// the tenant_id, with staff_id as the second segment — see
// LicenceRepository for path generation).

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
    // The RPC reads JWT claims; no need to pass user_id explicitly.
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    try {
      final rows = await _client.rpc<List<dynamic>>('eq_cards_current_staff');
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) return null;
      return Profile.fromJson(list.first);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Profile> upsert(Profile profile) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_upsert_my_profile',
        params: {'p_payload': profileToUpsertPayload(profile)},
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        throw const NotFoundFailure();
      }
      return Profile.fromJson(list.first);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}

/// Builds the JSON payload sent to eq_cards_upsert_my_profile. Pure —
/// no Supabase client — so unit-testable.
///
/// Note: `id` is NOT sent. The RPC auto-resolves the target staff row
/// from the JWT. Sending an `id` here is meaningless and the RPC
/// ignores it anyway. This is a deliberate guard against a client
/// trying to write to a different staff row.
@visibleForTesting
Map<String, dynamic> profileToUpsertPayload(Profile p) {
  final payload = <String, dynamic>{};
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

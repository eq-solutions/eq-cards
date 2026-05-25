// Cards Unit 5 (2026-05-24) — profile reads/writes route through the
// Shell's /cards-api endpoint (CardsApi in lib/core/cards_api). The
// endpoint targets the caller's per-tenant Supabase project (resolved
// from the JWT). Return shapes are unchanged so Profile.fromJson works
// against the JSON we receive without coercion.
//
// Previously (Cards Unit 4, 2026-05-21) these called supabase.rpc
// against shared eq-canonical's eq_cards_current_staff +
// eq_cards_upsert_my_profile. After the Shell admin moved to per-tenant
// DBs that direct path caused drift; the new path closes the gap.
//
// The `id` returned IS still the canonical staff_id (cards-api just
// proxies; same id, same meaning, just routed to a different DB).

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cards_api/cards_api.dart';
import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import 'models/profile.dart';

part 'profile_repository.g.dart';

class ProfileRepository {
  ProfileRepository(this._client, this._api);
  final SupabaseClient _client;
  final CardsApi _api;

  Future<Profile?> getCurrent() async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    try {
      final row = await _api.currentStaff();
      if (row == null) return null;
      return Profile.fromJson(row);
    } catch (e) {
      unawaited(_breadcrumb('profile_fetch_failed', {'error': e.toString()}));
      rethrow;
    }
  }

  Future<Profile> upsert(Profile profile) async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    unawaited(_breadcrumb('profile_upsert_started'));
    try {
      final row = await _api.upsertMyProfile(profileToUpsertPayload(profile));
      final saved = Profile.fromJson(row);
      unawaited(_breadcrumb('profile_upsert_succeeded'));
      return saved;
    } catch (e) {
      unawaited(_breadcrumb('profile_upsert_failed', {'error': e.toString()}));
      rethrow;
    }
  }

  Future<void> _breadcrumb(String message, [Map<String, dynamic>? data]) {
    return Sentry.addBreadcrumb(
      Breadcrumb(category: 'profile', message: message, data: data),
    );
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
  return ProfileRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(cardsApiProvider),
  );
}

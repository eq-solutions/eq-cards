// Profile data ops route through CardsDataSource, selected by the
// CARDS_DATA_TRANSPORT dart-define (see licence_repository.dart and
// docs/cards-canonical-api-rewire.md). The auth pre-check stays on the direct
// Supabase client regardless of transport.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cards_api/cards_data_source_providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import '../../../core/utils/date_utils.dart';
import 'models/profile.dart';

part 'profile_repository.g.dart';

class ProfileRepository {
  ProfileRepository(this._data, this._client);

  /// Transport for profile data ops (direct RPC vs cards-api gateway).
  final CardsDataSource _data;

  /// Direct Supabase client — used only for the auth pre-check.
  final SupabaseClient _client;

  Future<Profile?> getCurrent() async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    try {
      final row = await _data.currentStaff();
      if (row == null) return null;
      return Profile.fromJson(row);
    } catch (e) {
      unawaited(_breadcrumb('profile_fetch_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  Future<Profile> upsert(Profile profile) async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    unawaited(_breadcrumb('profile_upsert_started'));
    try {
      final row = await _data.upsertMyProfile(profileToUpsertPayload(profile));
      final saved = Profile.fromJson(row);
      unawaited(_breadcrumb('profile_upsert_succeeded'));
      return saved;
    } catch (e) {
      unawaited(_breadcrumb('profile_upsert_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  Future<void> _breadcrumb(String message, [Map<String, dynamic>? data]) {
    return Sentry.addBreadcrumb(
      Breadcrumb(category: 'profile', message: message, data: data),
    );
  }
}

/// Builds the JSON payload for eq_cards_upsert_my_profile. Pure — no
/// Supabase client — so it's unit-testable.
///
/// `id` is NOT sent. The RPC auto-resolves the target staff row from the
/// JWT. Sending an `id` here is meaningless and the RPC ignores it.
@visibleForTesting
Map<String, dynamic> profileToUpsertPayload(Profile p) {
  final payload = <String, dynamic>{};
  if (p.fullName != null) payload['full_name'] = p.fullName;
  if (p.dateOfBirth != null) {
    payload['date_of_birth'] = EqDates.iso(p.dateOfBirth!);
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

@riverpod
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository(
    ref.watch(cardsDataSourceProvider),
    ref.watch(supabaseClientProvider),
  );
}

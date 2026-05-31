// Licence data ops route through CardsDataSource, selected by the
// CARDS_DATA_TRANSPORT dart-define (default: direct eq_cards_* RPCs on
// eq-canonical; `gateway` proxies via the Shell cards-api to the per-tenant
// DB). Storage (signed photo URLs) and the auth pre-check stay on the direct
// Supabase client regardless of transport — see
// docs/cards-canonical-api-rewire.md.

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
import 'models/licence.dart';

part 'licence_repository.g.dart';

class LicenceRepository {
  LicenceRepository(this._data, this._client);

  /// Transport for licence data ops (direct RPC vs cards-api gateway).
  final CardsDataSource _data;

  /// Direct Supabase client — used only for storage signing and the auth
  /// pre-check, never for licence data ops.
  final SupabaseClient _client;

  static const _bucket = 'licence-photos';
  static const _signedUrlSeconds = 3600;

  Future<List<Licence>> getAllForCurrentUser() async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    try {
      final rows = await _data.listMyLicences();
      final list = rows.map(Licence.fromJson).toList();
      return Future.wait(list.map(_withSignedUrls));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Licence> getById(String id) async {
    try {
      final all = await getAllForCurrentUser();
      final match = all.where((l) => l.id == id).toList();
      if (match.isEmpty) throw const NotFoundFailure();
      return match.first;
    } on Failure {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Licence> upsert(Licence licence) async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    final isInsert = licence.id == null;
    unawaited(_breadcrumb(
      isInsert ? 'licence_insert_started' : 'licence_update_started',
      {'licence_type': licence.licenceType},
    ),);
    try {
      final row = await _data.upsertMyLicence(licenceToUpsertPayload(licence));
      final saved = await _withSignedUrls(Licence.fromJson(row));
      unawaited(_breadcrumb(
        isInsert ? 'licence_insert_succeeded' : 'licence_update_succeeded',
        {'licence_id': saved.id ?? '', 'type': saved.licenceType},
      ),);
      return saved;
    } catch (e) {
      unawaited(_breadcrumb(
        isInsert ? 'licence_insert_failed' : 'licence_update_failed',
        {'error': e.toString()},
      ),);
      throw mapSupabaseError(e);
    }
  }

  Future<void> softDelete(String id) async {
    unawaited(_breadcrumb('licence_delete_started', {'licence_id': id}));
    try {
      await _data.softDeleteMyLicence(id);
      unawaited(_breadcrumb('licence_delete_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('licence_delete_failed', {'error': e.toString()}));
      throw mapSupabaseError(e);
    }
  }

  Future<void> _breadcrumb(String message, [Map<String, dynamic>? data]) {
    return Sentry.addBreadcrumb(
      Breadcrumb(category: 'licence', message: message, data: data),
    );
  }

  Future<Licence> _withSignedUrls(Licence l) async {
    Future<String?> sign(String? path) async {
      if (path == null) return null;
      try {
        return await _client.storage
            .from(_bucket)
            .createSignedUrl(path, _signedUrlSeconds);
      } catch (_) {
        return null;
      }
    }

    // Front and back are independent storage round-trips — sign concurrently.
    final signed = await Future.wait([
      sign(l.photoFrontPath),
      sign(l.photoBackPath),
    ]);
    return l.copyWith(
      photoFrontSignedUrl: signed[0],
      photoBackSignedUrl: signed[1],
    );
  }
}

/// Builds the JSON payload for eq_cards_upsert_my_licence. Pure — no
/// Supabase client involved — so it's unit-testable.
///
/// `user_id` is NOT in the payload. The RPC auto-resolves it from the
/// JWT app_metadata (server-derived identity, never client-supplied).
@visibleForTesting
Map<String, dynamic> licenceToUpsertPayload(Licence l) {
  final payload = <String, dynamic>{
    'licence_type': l.licenceType,
    'licence_number': l.licenceNumber,
    'expiry_date': EqDates.iso(l.expiryDate),
    'metadata': l.metadata,
  };
  if (l.issueDate != null) payload['issue_date'] = EqDates.iso(l.issueDate!);
  if (l.id != null) payload['id'] = l.id;
  if (l.issuingAuthority != null) {
    payload['issuing_authority'] = l.issuingAuthority;
  }
  // Normalise state to a trimmed upper-case code so the SAVED value is
  // identical across transports: the per-tenant gateway RPC stores
  // UPPER(NULLIF(state)), while the direct eq-canonical RPC stores it verbatim.
  // Blank/whitespace-only -> omitted (matches the gateway's NULLIF).
  final state = l.state?.trim();
  if (state != null && state.isNotEmpty) {
    payload['state'] = state.toUpperCase();
  }
  if (l.photoFrontPath != null) payload['photo_front_url'] = l.photoFrontPath;
  if (l.photoBackPath != null) payload['photo_back_url'] = l.photoBackPath;
  if (l.notes != null) payload['notes'] = l.notes;
  return payload;
}

@riverpod
LicenceRepository licenceRepository(LicenceRepositoryRef ref) {
  return LicenceRepository(
    ref.watch(cardsDataSourceProvider),
    ref.watch(supabaseClientProvider),
  );
}

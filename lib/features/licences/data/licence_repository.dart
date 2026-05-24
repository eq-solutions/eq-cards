// Cards Unit 5 (2026-05-24) — Cards Flutter writes go through the
// per-tenant data plane via the Shell's /cards-api endpoint (CardsApi
// in lib/core/cards_api). The endpoint resolves the caller's tenant
// from the Supabase JWT we already hold and routes to that tenant's
// dedicated Supabase project (eq-canonical-internal / sks-canonical).
//
// Previously (Cards Unit 4, 2026-05-21) these calls went directly to
// shared eq-canonical via supabase.rpc('eq_cards_*'). After the Shell's
// admin-side cards bridge moved to per-tenant DBs on 2026-05-24, that
// direct path caused stale-data surprises (Cards mobile wrote to
// shared, Shell read from tenant — divergence). This switch closes
// the gap.
//
// What does NOT change:
//   - Photo storage uploads still target shared eq-canonical's
//     `licence-photos` bucket (no Shell consumer of these images today;
//     storage migration deferred — see Shell-side runbook).
//   - `_withSignedUrls` still constructs signed URLs against shared
//     storage via the Supabase client.
//   - The Licence Flutter model. Return shapes from cards-api mirror
//     the old RPC return shapes exactly.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cards_api/cards_api.dart';
import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import 'models/licence.dart';

part 'licence_repository.g.dart';

class LicenceRepository {
  LicenceRepository(this._client, this._api);

  /// Kept for storage uploads + signed-URL generation only. All licence
  /// row reads/writes go through [_api].
  final SupabaseClient _client;
  final CardsApi _api;

  static const _bucket = 'licence-photos';
  static const _signedUrlSeconds = 3600;

  Future<List<Licence>> getAllForCurrentUser() async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    final rows = await _api.listMyLicences();
    final list = rows.map(Licence.fromJson).toList();
    return Future.wait(list.map(_withSignedUrls));
  }

  Future<Licence> getById(String id) async {
    // No dedicated single-row endpoint — list + filter is acceptable for
    // the tiny per-user dataset (a wallet typically has <30 licences).
    final all = await getAllForCurrentUser();
    final match = all.where((l) => l.id == id).toList();
    if (match.isEmpty) throw const NotFoundFailure();
    return match.first;
  }

  Future<Licence> upsert(Licence licence) async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    final isInsert = licence.id == null;
    unawaited(
      _breadcrumb(
        isInsert ? 'licence_insert_started' : 'licence_update_started',
        {'licence_type': licence.licenceType},
      ),
    );
    try {
      final row = await _api.upsertMyLicence(licenceToUpsertPayload(licence));
      final saved = await _withSignedUrls(Licence.fromJson(row));
      unawaited(
        _breadcrumb(
          isInsert ? 'licence_insert_succeeded' : 'licence_update_succeeded',
          {'licence_id': saved.id ?? '', 'type': saved.licenceType},
        ),
      );
      return saved;
    } catch (e) {
      unawaited(
        _breadcrumb(
          isInsert ? 'licence_insert_failed' : 'licence_update_failed',
          {'error': e.toString()},
        ),
      );
      rethrow;
    }
  }

  Future<void> softDelete(String id) async {
    unawaited(_breadcrumb('licence_delete_started', {'licence_id': id}));
    try {
      await _api.softDeleteMyLicence(id);
      unawaited(_breadcrumb('licence_delete_succeeded'));
    } catch (e) {
      unawaited(_breadcrumb('licence_delete_failed', {'error': e.toString()}));
      rethrow;
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

    return l.copyWith(
      photoFrontSignedUrl: await sign(l.photoFrontPath),
      photoBackSignedUrl: await sign(l.photoBackPath),
    );
  }
}

/// Builds the JSON payload sent to eq_cards_upsert_my_licence. Pure —
/// no Supabase client involved — so it's unit-testable.
///
/// `user_id` is NOT in the payload. The RPC auto-resolves it from the
/// JWT app_metadata. This matches the Phase 1.F security stance —
/// server-derived tenancy / identity, never client-supplied.
///
/// Transient signed URLs (`photoFrontSignedUrl`, `photoBackSignedUrl`)
/// are excluded from JSON via `@JsonKey(includeToJson: false)` on the
/// model and also are never written here.
@visibleForTesting
Map<String, dynamic> licenceToUpsertPayload(Licence l) {
  final payload = <String, dynamic>{
    'licence_type': l.licenceType,
    'licence_number': l.licenceNumber,
    'issue_date': _isoDate(l.issueDate),
    'expiry_date': _isoDate(l.expiryDate),
    'metadata': l.metadata,
  };
  if (l.id != null) payload['id'] = l.id;
  if (l.issuingAuthority != null) {
    payload['issuing_authority'] = l.issuingAuthority;
  }
  if (l.state != null) payload['state'] = l.state;
  if (l.photoFrontPath != null) {
    payload['photo_front_url'] = l.photoFrontPath;
  }
  if (l.photoBackPath != null) {
    payload['photo_back_url'] = l.photoBackPath;
  }
  if (l.notes != null) payload['notes'] = l.notes;
  return payload;
}

String _isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

@riverpod
LicenceRepository licenceRepository(LicenceRepositoryRef ref) {
  return LicenceRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(cardsApiProvider),
  );
}

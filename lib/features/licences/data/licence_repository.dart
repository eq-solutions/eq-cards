// Cards Unit 4 (2026-05-21) — All reads + writes go directly to
// eq-canonical (jvknxcmbtrfnxfrwfimn) via public.eq_cards_* RPCs.
//
// The cards-api Shell proxy (Unit 5) was rolled back because it requires
// app_metadata.tenant_id in the JWT, which direct OTP sign-ins don't carry.
// Routing stays on eq-canonical until tenant provisioning is wired for all
// auth paths.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'models/licence.dart';

part 'licence_repository.g.dart';

class LicenceRepository {
  LicenceRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'licence-photos';
  static const _signedUrlSeconds = 3600;

  Future<List<Licence>> getAllForCurrentUser() async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthenticatedFailure();
    }
    try {
      final rows = await _client.rpc<List<dynamic>>('eq_cards_list_my_licences');
      final list = rows.cast<Map<String, dynamic>>().map(Licence.fromJson).toList();
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
    ));
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_upsert_my_licence',
        params: {'p_payload': licenceToUpsertPayload(licence)},
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) throw const NotFoundFailure();
      final saved = await _withSignedUrls(Licence.fromJson(list.first));
      unawaited(_breadcrumb(
        isInsert ? 'licence_insert_succeeded' : 'licence_update_succeeded',
        {'licence_id': saved.id ?? '', 'type': saved.licenceType},
      ));
      return saved;
    } catch (e) {
      unawaited(_breadcrumb(
        isInsert ? 'licence_insert_failed' : 'licence_update_failed',
        {'error': e.toString()},
      ));
      throw mapSupabaseError(e);
    }
  }

  Future<void> softDelete(String id) async {
    unawaited(_breadcrumb('licence_delete_started', {'licence_id': id}));
    try {
      await _client.rpc<void>(
        'eq_cards_soft_delete_my_licence',
        params: {'p_licence_id': id},
      );
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

    return l.copyWith(
      photoFrontSignedUrl: await sign(l.photoFrontPath),
      photoBackSignedUrl: await sign(l.photoBackPath),
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
    'issue_date': _isoDate(l.issueDate),
    'expiry_date': _isoDate(l.expiryDate),
    'metadata': l.metadata,
  };
  if (l.id != null) payload['id'] = l.id;
  if (l.issuingAuthority != null) payload['issuing_authority'] = l.issuingAuthority;
  if (l.state != null) payload['state'] = l.state;
  if (l.photoFrontPath != null) payload['photo_front_url'] = l.photoFrontPath;
  if (l.photoBackPath != null) payload['photo_back_url'] = l.photoBackPath;
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
  return LicenceRepository(ref.watch(supabaseClientProvider));
}

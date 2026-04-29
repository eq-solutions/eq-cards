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
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthenticatedFailure();
    try {
      final rows = await _client
          .from('licences')
          .select()
          .eq('user_id', userId)
          .filter('deleted_at', 'is', null)
          .order('expiry_date');
      final licences = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(Licence.fromJson)
          .toList();
      return Future.wait(licences.map(_withSignedUrls));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Licence> getById(String id) async {
    try {
      final row = await _client
          .from('licences')
          .select()
          .eq('id', id)
          .single();
      return _withSignedUrls(Licence.fromJson(row));
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Licence> upsert(Licence licence) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthenticatedFailure();
    final isInsert = licence.id == null;
    unawaited(
      _breadcrumb(
        isInsert ? 'licence_insert_started' : 'licence_update_started',
        {'licence_type': licence.licenceType},
      ),
    );
    try {
      final row = await _client
          .from('licences')
          .upsert(licenceToUpsertPayload(licence, userId))
          .select()
          .single();
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
      throw mapSupabaseError(e);
    }
  }

  Future<void> softDelete(String id) async {
    unawaited(_breadcrumb('licence_delete_started', {'licence_id': id}));
    try {
      await _client
          .from('licences')
          .update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
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

/// Builds the JSON payload for an upsert. Pure — no Supabase client involved
/// — so it's unit-testable without faking the data source.
///
/// `user_id` always comes from the authenticated session (parameter), never
/// from the model — RLS would reject any other value anyway, but this makes
/// the contract explicit.
///
/// Transient signed URLs (`photoFrontSignedUrl`, `photoBackSignedUrl`) are
/// excluded from JSON via `@JsonKey(includeToJson: false)` on the model and
/// also are never written here. Only persistent paths are sent.
@visibleForTesting
Map<String, dynamic> licenceToUpsertPayload(Licence l, String userId) {
  final payload = <String, dynamic>{
    'user_id': userId,
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
  return LicenceRepository(ref.watch(supabaseClientProvider));
}

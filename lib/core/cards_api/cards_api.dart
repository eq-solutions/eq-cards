// Thin client for the Shell's /.netlify/functions/cards-api endpoint.
//
// All licence + profile reads/writes go through here post-Phase-2.B
// (the per-tenant data plane migration). The endpoint is multiplexed via
// `?op=…` and authenticates via Authorization: Bearer <supabase_jwt> —
// the same JWT Cards already holds in its Supabase session. The Shell
// function resolves the caller's tenant from the JWT's app_metadata and
// routes the request to the tenant's dedicated Supabase project.
//
// Migration history:
//   Cards Unit 4 (2026-05-21): repos called supabase.rpc('eq_cards_*')
//   directly against shared eq-canonical. Worked, but every Cards write
//   landed on the shared DB while the Shell admin pages started reading
//   from per-tenant DBs (post-2026-05-24 cutover) — caused stale-data
//   surprises in the Shell admin Cards-approval flow.
//
//   This client replaces that. Same return shapes (so the dart models
//   are unchanged), different transport. Storage uploads
//   (licence-photos bucket) intentionally stay on shared via the
//   Supabase client — there's no Shell consumer of those images today,
//   so the storage migration is deferred (see Shell-side runbook
//   docs/runbooks/cards-mobile-tenant-cutover.md in the eq-shell repo).
//
// Shell-side contract:
//   netlify/functions/cards-api.ts (eq-shell repo)
//   supabase/tenant-migrations/0006_cards_rpcs.sql (eq-shell repo)
//   supabase/tenant-migrations/0007_cards_profile_rpc.sql (eq-shell repo)

import 'dart:io' show HttpStatus;

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';
import '../supabase/supabase_client_provider.dart';

part 'cards_api.g.dart';

/// Production base URL for the Shell. Hardcoded for now (Cards mobile
/// has no env/config layer). If a non-prod build target lands, surface
/// this through whatever config provider the rest of the app adopts.
const String _shellBaseUrl = 'https://core.eq.solutions';

/// Single shared Dio instance configured with the Shell base URL and a
/// short timeout. Auth headers are attached per-request because the JWT
/// rotates (15-min TTL by default).
class CardsApi {
  CardsApi(this._supabase, {Dio? dio, String baseUrl = _shellBaseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: '$baseUrl/.netlify/functions/cards-api',
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                // Don't throw on 4xx — we read the error envelope from
                // the body and map to a typed Failure. 5xx propagates as
                // DioException so the caller's catch path runs.
                validateStatus: (s) => s != null && s < 500,
              ),
            );

  final SupabaseClient _supabase;
  final Dio _dio;

  /// GET /cards-api?op=current_staff → { ok, staff }
  Future<Map<String, dynamic>?> currentStaff() async {
    final res = await _request(
      method: 'GET',
      op: 'current_staff',
    );
    return res['staff'] as Map<String, dynamic>?;
  }

  /// GET /cards-api?op=list_my_licences → { ok, licences: [...] }
  Future<List<Map<String, dynamic>>> listMyLicences() async {
    final res = await _request(
      method: 'GET',
      op: 'list_my_licences',
    );
    return (res['licences'] as List).cast<Map<String, dynamic>>();
  }

  /// POST /cards-api?op=upsert_my_licence  body: { payload } → { ok, licence }
  Future<Map<String, dynamic>> upsertMyLicence(Map<String, dynamic> payload) async {
    final res = await _request(
      method: 'POST',
      op: 'upsert_my_licence',
      body: {'payload': payload},
    );
    return res['licence'] as Map<String, dynamic>;
  }

  /// POST /cards-api?op=soft_delete_my_licence  body: { licence_id } → { ok }
  Future<void> softDeleteMyLicence(String licenceId) async {
    await _request(
      method: 'POST',
      op: 'soft_delete_my_licence',
      body: {'licence_id': licenceId},
    );
  }

  /// POST /cards-api?op=upsert_my_profile  body: { payload } → { ok, profile }
  Future<Map<String, dynamic>> upsertMyProfile(Map<String, dynamic> payload) async {
    final res = await _request(
      method: 'POST',
      op: 'upsert_my_profile',
      body: {'payload': payload},
    );
    return res['profile'] as Map<String, dynamic>;
  }

  // ────────────────────────────────────────────────────────────────────
  // internals
  // ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _request({
    required String method,
    required String op,
    Map<String, dynamic>? body,
  }) async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) {
      throw const NotAuthenticatedFailure();
    }

    final Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        '',
        queryParameters: {'op': op},
        data: body,
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $token'},
          contentType: body != null ? 'application/json' : null,
        ),
      );
    } on DioException catch (e) {
      // Network-level (timeout, DNS, TLS, server 5xx) — surfaced as
      // ServerFailure so the UI can show a retry CTA.
      final status = e.response?.statusCode ?? 0;
      final msg = e.message ?? 'network error';
      if (status == 0) {
        throw const NetworkFailure();
      }
      throw ServerFailure(status, msg);
    }

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw ServerFailure(res.statusCode ?? 500, 'unexpected response shape');
    }

    if (data['ok'] == true) return data;

    // Error envelope from cards-api: { ok: false, error: '<code>', detail?: '<human>' }
    final code   = data['error']  as String? ?? 'unknown';
    final detail = data['detail'] as String?;
    final status = res.statusCode ?? 500;

    if (status == HttpStatus.unauthorized || code == 'not_signed_in') {
      throw const NotAuthenticatedFailure();
    }
    if (status == HttpStatus.notFound || code == 'licence_not_found') {
      throw const NotFoundFailure();
    }
    throw ServerFailure(status, detail ?? code);
  }
}

@Riverpod(keepAlive: true)
CardsApi cardsApi(CardsApiRef ref) {
  return CardsApi(ref.watch(supabaseClientProvider));
}

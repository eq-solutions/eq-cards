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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';
import '../supabase/supabase_client_provider.dart';
// Platform bridge for the Shell iframe handoff. Conditional import: the web
// build pulls the dart:html impl; the VM (test) build the stub (returns null,
// so the native-refresh fallback runs). Lets the client renew shell-minted
// JWTs — which have no Supabase refresh_token — via a fresh mint from the shell.
import '../../features/auth/presentation/screens/handoff_platform_io.dart'
    if (dart.library.html) '../../features/auth/presentation/screens/handoff_platform_web.dart';

part 'cards_api.g.dart';

/// Shell base URL. Defaults to production; override for dev/staging via:
///   flutter run --dart-define=SHELL_BASE_URL=http://localhost:8888
const String _shellBaseUrl = String.fromEnvironment(
  'SHELL_BASE_URL',
  defaultValue: 'https://core.eq.solutions',
);

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
    final res = await _request(method: 'GET', op: 'list_my_licences');
    final licences = res['licences'];
    if (licences is! List) {
      throw const ServerFailure(500, 'missing licences in response');
    }
    return licences.cast<Map<String, dynamic>>();
  }

  /// POST /cards-api?op=upsert_my_licence  body: { payload } → { ok, licence }
  Future<Map<String, dynamic>> upsertMyLicence(Map<String, dynamic> payload) async {
    final res = await _request(
      method: 'POST',
      op: 'upsert_my_licence',
      body: {'payload': payload},
    );
    final licence = res['licence'];
    if (licence is! Map<String, dynamic>) {
      throw const ServerFailure(500, 'missing licence in response');
    }
    return licence;
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
    final profile = res['profile'];
    if (profile is! Map<String, dynamic>) {
      throw const ServerFailure(500, 'missing profile in response');
    }
    return profile;
  }

  // ────────────────────────────────────────────────────────────────────
  // internals
  // ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _request({
    required String method,
    required String op,
    Map<String, dynamic>? body,
  }) async {
    var session = _supabase.auth.currentSession;
    if (session == null) throw const NotAuthenticatedFailure();

    // Refresh proactively if expiring within 60 s — Supabase's auto-refresh
    // timer can lag after a background/foreground cycle, sending a stale token
    // that causes a 401 even though a silent refresh would have succeeded.
    final expiresAt = session.expiresAt;
    final nearExpiry = expiresAt != null &&
        DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
            .isBefore(DateTime.now().add(const Duration(seconds: 60)));
    if (nearExpiry) {
      // Shell-minted JWTs (iframe handoff) carry no Supabase refresh_token, so
      // auth.refreshSession() throws — surfacing a false "session expired".
      // Re-request a fresh JWT from the parent shell instead (silent
      // postMessage handshake). Native / direct-URL sessions DO have a
      // refresh_token, so they fall through to the standard refresh.
      String? shellToken;
      if (kIsWeb && HandoffPlatform.isInIframe()) {
        shellToken = await HandoffPlatform.requestShellToken();
      }
      if (shellToken != null && shellToken.isNotEmpty) {
        await _supabase.auth.setSession(shellToken, accessToken: shellToken);
        session = _supabase.auth.currentSession;
      } else {
        try {
          final refreshed = await _supabase.auth.refreshSession();
          session = refreshed.session;
        } on AuthException {
          throw const NotAuthenticatedFailure();
        }
      }
    }
    final token = session?.accessToken;
    if (token == null) throw const NotAuthenticatedFailure();

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

    // Literal status codes — avoids a dart:io import that fails Flutter web.
    if (status == 401 || code == 'not_signed_in') {
      throw const NotAuthenticatedFailure();
    }
    if (status == 404 || code == 'licence_not_found') {
      throw const NotFoundFailure();
    }
    throw ServerFailure(status, detail ?? code);
  }
}

@Riverpod(keepAlive: true)
CardsApi cardsApi(CardsApiRef ref) {
  return CardsApi(ref.watch(supabaseClientProvider));
}

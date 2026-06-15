// Anon client for the Shell `cards-api` gateway's `lookup_invite_by_phone` op.
//
// This is deliberately SEPARATE from CardsApi (the JWT-gated, flag-selected
// data transport in lib/core/cards_api/). Invite lookup happens during
// onboarding — *before* the worker has a session — so:
//
//   • it sends NO Authorization header (the gateway op is anon), and
//   • it is ALWAYS routed through the gateway, regardless of the
//     CARDS_DATA_TRANSPORT flag, because the whole point is to put the call
//     behind the gateway's per-attacker (IP) rate limit. The anon Supabase
//     RPC it replaces could only be throttled per-slug (the DB function can't
//     see the client IP). The per-slug DB throttle (migration 0034) still
//     applies underneath the gateway.
//
// Shell-side contract: netlify/functions/cards-api.ts (eq-shell repo),
// op=lookup_invite_by_phone.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';

/// Shell base URL — the same dart-define CardsApi uses, so a build that points
/// Cards at a non-prod Shell (e.g. localhost:8888) affects this call too.
///   flutter run --dart-define=SHELL_BASE_URL=http://localhost:8888
const String _shellBaseUrl = String.fromEnvironment(
  'SHELL_BASE_URL',
  defaultValue: 'https://core.eq.solutions',
);

class InviteLookupApi {
  InviteLookupApi({Dio? dio, String baseUrl = _shellBaseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: '$baseUrl/.netlify/functions/cards-api',
                connectTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                // The gateway returns a typed error envelope with 4xx/5xx
                // statuses ({ ok:false, error, detail }); read the body rather
                // than letting Dio collapse them into a DioException.
                validateStatus: (s) => s != null && s < 600,
              ),
            );

  final Dio _dio;

  /// POST /cards-api?op=lookup_invite_by_phone  body: { phone, slug }
  ///   → `{ ok:true, token: <uuid|null> }`
  ///
  /// Returns the unclaimed invite's claim token, or null when no matching
  /// invite exists. Throws [RateLimitedFailure] on 429, [NetworkFailure] on a
  /// transport error, [ServerFailure] otherwise.
  Future<String?> lookupInviteByPhone(String phone, String slug) async {
    final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        '',
        queryParameters: {'op': 'lookup_invite_by_phone'},
        data: {'phone': phone, 'slug': slug},
        options: Options(contentType: 'application/json'),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 0) throw const NetworkFailure();
      throw ServerFailure(status, e.message ?? 'network error');
    }

    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw ServerFailure(res.statusCode ?? 500, 'unexpected response shape');
    }

    if (data['ok'] == true) {
      final token = data['token'];
      return token is String ? token : null;
    }

    final code = data['error'] as String? ?? 'unknown';
    final status = res.statusCode ?? 500;
    if (status == 429 || code == 'rate_limited') {
      final ra = data['retry_after_seconds'];
      throw RateLimitedFailure(ra is num ? ra.toInt() : null);
    }
    final detail = data['detail'] as String?;
    throw ServerFailure(status, detail ?? code);
  }
}

final inviteLookupApiProvider = Provider<InviteLookupApi>(
  (ref) => InviteLookupApi(),
);

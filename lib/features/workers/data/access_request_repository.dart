import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';

part 'access_request_repository.g.dart';

/// A pending request from an employer asking to connect to the signed-in
/// worker's wallet (worker-facing — the consent prompt).
class IncomingAccessRequest {
  const IncomingAccessRequest({
    required this.requestId,
    required this.orgId,
    required this.orgName,
    required this.orgSlug,
    required this.note,
    required this.requestedAt,
  });

  factory IncomingAccessRequest.fromJson(Map<String, dynamic> json) =>
      IncomingAccessRequest(
        requestId: json['request_id'] as String,
        orgId: json['org_id'] as String,
        orgName: json['org_name'] as String,
        orgSlug: json['org_slug'] as String,
        note: json['note'] as String?,
        requestedAt: DateTime.parse(json['requested_at'] as String),
      );

  final String requestId;
  final String orgId;
  final String orgName;
  final String orgSlug;
  final String? note;
  final DateTime requestedAt;
}

class AccessRequestRepository {
  AccessRequestRepository(this._client);
  final SupabaseClient _client;

  // ── Worker side ──────────────────────────────────────────────────────────

  Future<List<IncomingAccessRequest>> listIncoming() async {
    final rows = await _client
        .rpc<List<dynamic>>('eq_cards_list_incoming_requests');
    return rows
        .map((e) => IncomingAccessRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Approve or decline. On approve the worker gains the org as a switchable
  /// workspace (the RPC reconciles the membership across every layer).
  Future<String> respond(String requestId, {required bool approve}) async {
    final result = await _client.rpc<dynamic>(
      'eq_cards_respond_to_access_request',
      params: {'p_request_id': requestId, 'p_approve': approve},
    );
    return result as String;
  }

  // ── Admin side ───────────────────────────────────────────────────────────

  /// Ask an existing tradie (by phone) to connect their wallet to the org.
  /// Idempotent; reveals nothing about whether the phone has a wallet.
  Future<void> requestWorkerAccess(
    String orgId,
    String phone, {
    String? note,
  }) async {
    await _client.rpc<dynamic>(
      'eq_cards_request_worker_access',
      params: {'p_org_id': orgId, 'p_phone': phone, 'p_note': note},
    );
  }
}

@riverpod
AccessRequestRepository accessRequestRepository(Ref ref) =>
    AccessRequestRepository(ref.watch(supabaseClientProvider));

@riverpod
Future<List<IncomingAccessRequest>> incomingAccessRequests(Ref ref) =>
    ref.watch(accessRequestRepositoryProvider).listIncoming();

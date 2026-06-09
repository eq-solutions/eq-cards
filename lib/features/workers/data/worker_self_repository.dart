import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import 'models/worker.dart';

export 'models/worker.dart';

/// Summary returned by eq_cards_preview_invite — shown on the consent screen
/// before the worker commits to claiming.
class InvitePreview {
  const InvitePreview({
    required this.orgName,
    required this.workerName,
    required this.credentialCount,
    required this.expiresAt,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) => InvitePreview(
        orgName: (json['org_name'] as String?) ?? 'Your organisation',
        workerName: (json['worker_name'] as String?) ?? '',
        credentialCount: (json['credential_count'] as int?) ?? 0,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  final String orgName;
  final String workerName;
  final int credentialCount;
  final DateTime expiresAt;

  int get daysUntilExpiry =>
      expiresAt.difference(DateTime.now()).inDays.clamp(0, 99);
}

/// Worker-facing operations — distinct from AdminWorkerRepository which is
/// admin-only. These RPCs are SECURITY DEFINER and safe to call from the
/// worker's authenticated (or even anon) client.
class WorkerSelfRepository {
  WorkerSelfRepository(this._client);
  final SupabaseClient _client;

  Never _throw(Object e) => throw mapSupabaseError(e);

  /// Preview an invite without claiming it. Returns null if the token is
  /// expired, already claimed, or not found. Callable without auth — the
  /// token is the authorisation.
  Future<InvitePreview?> previewInvite(String token) async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_preview_invite',
        params: {'p_token': token},
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) return null;
      return InvitePreview.fromJson(list.first);
    } catch (e) {
      _throw(e);
    }
  }

  /// Returns the workers row linked to the current user.
  /// APP 12 — access to own personal information held by an organisation.
  Future<Worker?> getHrRecord() async {
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_get_worker_hr_record',
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) return null;
      return Worker.fromJson(list.first);
    } catch (e) {
      _throw(e);
    }
  }

  /// Given a normalised AU phone number and a tenant slug, returns the UUID
  /// token of the first unclaimed, non-expired worker invite for that
  /// worker + org — or null if none exists.
  ///
  /// Called by [ClaimByPhoneScreen] when a worker scans the tenant QR code
  /// (which has no per-worker token) and enters their mobile to look up their
  /// invite. Callable without auth — SECURITY DEFINER, anon-accessible.
  Future<String?> lookupInviteByPhone(String phone, String orgSlug) async {
    try {
      final result = await _client.rpc<dynamic>(
        'eq_cards_lookup_invite_by_phone',
        params: {'p_phone': phone, 'p_slug': orgSlug},
      );
      return result as String?;
    } catch (e) {
      _throw(e);
    }
  }

  /// Soft-deletes the current user's self-entered data.
  /// APP 17 — right to erasure of worker-owned information.
  /// Does NOT delete the org's HR record (workers table) — that is the
  /// org's data. Workers must contact their admin for those records.
  Future<void> deleteAccount() async {
    try {
      await _client.rpc<void>('eq_cards_delete_account');
    } catch (e) {
      _throw(e);
    }
  }
}

final workerSelfRepositoryProvider = Provider<WorkerSelfRepository>(
  (ref) => WorkerSelfRepository(ref.watch(supabaseClientProvider)),
);

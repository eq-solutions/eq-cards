import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_error_handler.dart';
import '../../../core/utils/date_utils.dart';
import '../../worker_house/worker_house.dart';
import 'models/worker.dart';
import 'models/worker_invite.dart';

export 'models/worker.dart';
export 'models/worker_invite.dart';

part 'admin_worker_repository.g.dart';

class AdminWorkerRepository {
  AdminWorkerRepository(this._client);
  final SupabaseClient _client;

  String get _uid {
    final u = _client.auth.currentUser;
    if (u == null) throw const NotAuthenticatedFailure();
    return u.id;
  }

  Never _throw(Object e) => throw mapSupabaseError(e);

  // ── Worker CRUD ──────────────────────────────────────────────────────────

  Future<List<Worker>> listWorkers(String orgId) async {
    _uid;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_admin_list_workers',
        params: {'p_org_id': orgId},
      );
      return rows.cast<Map<String, dynamic>>().map(Worker.fromJson).toList();
    } catch (e) {
      _throw(e);
    }
  }

  Future<Worker> upsertWorker(String orgId, Map<String, dynamic> payload) async {
    _uid;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_admin_upsert_worker',
        params: {'p_org_id': orgId, 'p_payload': payload},
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) throw const NotFoundFailure();
      return Worker.fromJson(list.first);
    } catch (e) {
      _throw(e);
    }
  }

  // ── Credential CRUD ──────────────────────────────────────────────────────

  Future<List<WorkerCredential>> listCredentials(String workerId) async {
    _uid;
    try {
      final rows = await _client
          .from('worker_credentials')
          .select()
          .eq('worker_id', workerId)
          .isFilter('deleted_at', null)
          .order('expiry_date', ascending: true, nullsFirst: false);
      return rows.map(WorkerCredential.fromJson).toList();
    } catch (e) {
      _throw(e);
    }
  }

  Future<WorkerCredential> upsertCredential(
    String orgId,
    String workerId,
    Map<String, dynamic> payload,
  ) async {
    _uid;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_admin_upsert_worker_credential',
        params: {
          'p_org_id': orgId,
          'p_worker_id': workerId,
          'p_payload': payload,
        },
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) throw const NotFoundFailure();
      return WorkerCredential.fromJson(list.first);
    } catch (e) {
      _throw(e);
    }
  }

  // ── Invite management ────────────────────────────────────────────────────

  Future<List<WorkerInvite>> listInvites(String orgId) async {
    _uid;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_admin_list_invites',
        params: {'p_org_id': orgId},
      );
      return rows.cast<Map<String, dynamic>>().map(WorkerInvite.fromJson).toList();
    } catch (e) {
      _throw(e);
    }
  }

  Future<WorkerInvite> createInvite(String orgId, String workerId) async {
    _uid;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_admin_create_invite',
        params: {'p_org_id': orgId, 'p_worker_id': workerId},
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) throw const NotFoundFailure();
      // RPC returns (invite_id, token, expires_at) — fetch the full row
      final inviteId = list.first['invite_id'] as String;
      final inviteRows = await _client
          .from('worker_invites')
          .select()
          .eq('id', inviteId)
          .single();
      return WorkerInvite.fromJson(inviteRows);
    } catch (e) {
      _throw(e);
    }
  }

  Future<void> revokeInvite(String inviteId) async {
    _uid;
    try {
      await _client.rpc<void>(
        'eq_cards_admin_revoke_invite',
        params: {'p_invite_id': inviteId},
      );
    } catch (e) {
      _throw(e);
    }
  }

  Future<Worker> claimInvite(String token) async {
    _uid;
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'eq_cards_claim_invite',
        params: {'p_token': token},
      );
      final list = rows.cast<Map<String, dynamic>>();
      if (list.isEmpty) throw const NotFoundFailure();
      return Worker.fromJson(list.first);
    } catch (e) {
      _throw(e);
    }
  }

  // ── Payload builders ─────────────────────────────────────────────────────

  @visibleForTesting
  static Map<String, dynamic> workerToPayload(Worker w) => {
    if (w.id.isNotEmpty) 'id': w.id,
    'first_name': w.firstName,
    'last_name': w.lastName,
    if (w.preferredName != null) 'preferred_name': w.preferredName,
    if (w.email != null) 'email': w.email,
    if (w.phone != null) 'phone': w.phone,
    if (w.dateOfBirth != null) 'date_of_birth': EqDates.iso(w.dateOfBirth!),
    if (w.addressStreet != null) 'address_street': w.addressStreet,
    if (w.addressSuburb != null) 'address_suburb': w.addressSuburb,
    if (w.addressState != null) 'address_state': w.addressState,
    if (w.addressPostcode != null) 'address_postcode': w.addressPostcode,
    if (w.emergencyContactName != null) 'emergency_contact_name': w.emergencyContactName,
    if (w.emergencyContactPhone != null) 'emergency_contact_phone': w.emergencyContactPhone,
    if (w.emergencyContactRelationship != null)
      'emergency_contact_relationship': w.emergencyContactRelationship,
    if (w.rightToWorkExpiry != null)
      'right_to_work_expiry': EqDates.iso(w.rightToWorkExpiry!),
  };

  @visibleForTesting
  static Map<String, dynamic> credentialToPayload(WorkerCredential c) => {
    if (c.id != null) 'id': c.id,
    'credential_type': c.credentialType,
    if (c.licenceNumber != null) 'licence_number': c.licenceNumber,
    if (c.issuingBody != null) 'issuing_body': c.issuingBody,
    if (c.stateTerritory != null) 'state_territory': c.stateTerritory,
    if (c.issueDate != null) 'issue_date': EqDates.iso(c.issueDate!),
    if (c.expiryDate != null) 'expiry_date': EqDates.iso(c.expiryDate!),
  };
}

@riverpod
AdminWorkerRepository adminWorkerRepository(Ref ref) =>
    AdminWorkerRepository(ref.watch(supabaseClientProvider));

/// Async list of workers for a given org — used by the admin member list screen.
@riverpod
Future<List<Worker>> adminWorkersList(Ref ref, String orgId) =>
    ref.watch(adminWorkerRepositoryProvider).listWorkers(orgId);

/// Async list of credentials for a given worker — used by the admin credential screen.
@riverpod
Future<List<WorkerCredential>> adminWorkerCredentials(Ref ref, String workerId) =>
    ref.watch(adminWorkerRepositoryProvider).listCredentials(workerId);

/// Async list of pending invites for a given org.
@riverpod
Future<List<WorkerInvite>> adminWorkerInvites(Ref ref, String orgId) =>
    ref.watch(adminWorkerRepositoryProvider).listInvites(orgId);

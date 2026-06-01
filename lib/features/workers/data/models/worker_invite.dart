import 'package:freezed_annotation/freezed_annotation.dart';

part 'worker_invite.freezed.dart';
part 'worker_invite.g.dart';

/// Mirrors public.worker_invites on eq-canonical.
///
/// [workerId] references a pre-created Worker record. When null the invite
/// carries a JSONB profile snapshot (legacy path — not used by the admin UI).
/// [claimedAt] is null until the worker authenticates and calls claim_invite.
@freezed
abstract class WorkerInvite with _$WorkerInvite {
  const factory WorkerInvite({
    required String id,
    required String orgId,
    required String token,
    String? workerId,
    required DateTime expiresAt,
    DateTime? claimedAt,
    String? claimedBy,
    required String createdBy,
    required DateTime createdAt,
  }) = _WorkerInvite;

  const WorkerInvite._();

  factory WorkerInvite.fromJson(Map<String, dynamic> json) =>
      _$WorkerInviteFromJson(json);

  bool get isClaimed => claimedAt != null;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isClaimed && !isExpired;
}

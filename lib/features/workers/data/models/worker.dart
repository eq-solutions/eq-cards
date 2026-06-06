import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/date_utils.dart';

part 'worker.freezed.dart';
part 'worker.g.dart';

/// The `eq_role` enum values (eq-canonical), in seniority order, with the
/// display labels shown in admin UI. The DB stores the snake_case key.
const Map<String, String> kEqRoleLabels = {
  'manager': 'Manager',
  'supervisor': 'Supervisor',
  'employee': 'Employee',
  'apprentice': 'Apprentice',
  'labour_hire': 'Labour hire',
};

/// Mirrors public.workers on eq-canonical.
///
/// [userId] is null for pre-created workers (admin has entered details but
/// the worker hasn't claimed their account yet). Set to the worker's
/// auth.uid() when they claim their invite.
@freezed
abstract class Worker with _$Worker {
  const factory Worker({
    required String id,
    String? userId,
    required String firstName,
    required String lastName,
    String? preferredName,
    String? email,
    String? phone,
    /// eq_role on public.workers. Null until an admin assigns one; copied into
    /// the invite and applied on claim (null → claim defaults to 'employee').
    String? role,
    DateTime? dateOfBirth,
    String? addressStreet,
    String? addressSuburb,
    String? addressState,
    String? addressPostcode,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelationship,
    String? rightToWorkType,
    DateTime? rightToWorkExpiry,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Worker;

  const Worker._();

  factory Worker.fromJson(Map<String, dynamic> json) => _$WorkerFromJson(json);

  String get displayName => preferredName ?? '$firstName $lastName';
  bool get isClaimed => userId != null;

  bool get rightToWorkExpired =>
      rightToWorkExpiry != null && EqDates.isExpired(rightToWorkExpiry!);
}

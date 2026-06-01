import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/date_utils.dart';

part 'worker_credential.freezed.dart';
part 'worker_credential.g.dart';

/// A credential seeded into the worker-house (eq-canonical-internal) by
/// the SKS Intake flow. Distinct from licences and certificates (which are
/// worker self-entered on the tenant DB); this data comes from the employer
/// side via the import and is owned by the worker.
@freezed
abstract class WorkerCredential with _$WorkerCredential {
  const factory WorkerCredential({
    required String id,
    required String workerId,
    required String credentialType,
    String? licenceNumber,
    required String issuingBody,
    String? stateTerritory,
    DateTime? issueDate,
    DateTime? expiryDate,
    required String status,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _WorkerCredential;

  const WorkerCredential._();

  factory WorkerCredential.fromJson(Map<String, dynamic> json) =>
      _$WorkerCredentialFromJson(json);

  bool get isExpired => expiryDate != null && EqDates.isExpired(expiryDate!);

  int? get daysUntilExpiry =>
      expiryDate != null ? EqDates.daysUntil(expiryDate!) : null;

  bool get isExpiringSoon =>
      expiryDate != null && EqDates.isExpiringSoon(expiryDate!);
}

/// Human-readable labels for worker_credential_type enum values.
const workerCredentialTypeLabels = <String, String>{
  'electrical_licence':    'Electrical Licence',
  'white_card':            'White Card',
  'first_aid':             'First Aid',
  'ewp':                   'EWP',
  'working_at_heights':    'Working at Heights',
  'confined_space':        'Confined Space',
  'asbestos_awareness':    'Asbestos Awareness',
};

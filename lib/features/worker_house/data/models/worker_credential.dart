import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/date_utils.dart';

part 'worker_credential.freezed.dart';
part 'worker_credential.g.dart';

/// Mirrors public.worker_credentials on eq-canonical.
///
/// Credentials are tied to a Worker record (not directly to auth.uid()).
/// Admin-entered via AdminWorkerRepository; readable by the worker after
/// they claim their invite.
@freezed
abstract class WorkerCredential with _$WorkerCredential {
  const factory WorkerCredential({
    String? id,
    required String workerId,
    required String credentialType,
    String? licenceNumber,
    String? issuingBody,
    String? stateTerritory,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? photoFrontPath,
    String? photoBackPath,
    String? notes,
    @Default({}) Map<String, dynamic> metadata,
    @Default('active') String status,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _WorkerCredential;

  const WorkerCredential._();

  factory WorkerCredential.fromJson(Map<String, dynamic> json) =>
      _$WorkerCredentialFromJson(json);

  bool get isExpired =>
      expiryDate != null && EqDates.isExpired(expiryDate!);

  int? get daysUntilExpiry =>
      expiryDate != null ? EqDates.daysUntil(expiryDate!) : null;

  bool get isExpiringSoon =>
      expiryDate != null && EqDates.isExpiringSoon(expiryDate!);
}

/// Human-readable labels for all credential types in the worker_credential_type enum.
const workerCredentialTypeLabels = <String, String>{
  'electrical_licence':  'Electrical Licence',
  'white_card':          'White Card (Construction Induction)',
  'working_at_heights':  'Working at Heights',
  'confined_space':      'Confined Space Entry',
  'open_cabling':        'Open Cabling',
  'scissor_lift':        'Scissor Lift (SL)',
  'boom_lift':           'Boom Lift (BL ≤11m)',
  'vertical_lift':       'Vertical Lift (VL ≤11m)',
  'hrwl_boom_11m':       'HRL — Boom Lift (>11m)',
  'forklift_hrwl':       'HRL — Forklift',
  'hrwl_dogging':        'HRL — Dogging',
  'riw':                 'Rail Industry Worker (RIW)',
  'first_aid':           'First Aid',
  'cpr':                 'CPR',
  'lvr':                 'Low Voltage Rescue (LVR)',
  'driver_licence':      'Driver Licence',
  'hv_switching':        'HV Switching',
  'hv_operators':        'HV Operators',
  'manual_handling':     'Manual Handling',
  'silica_awareness':    'Silica Awareness',
  'asbestos_awareness':  'Asbestos Awareness',
  'ewp':                 'Elevated Work Platform (EWP)',
  'medicare':            'Medicare Card',
  'test_and_tag':        'Test and Tag',
  'traffic_control':     'Traffic Control',
  'other':               'Other',
};

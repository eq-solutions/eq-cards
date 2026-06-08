import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_connection.freezed.dart';
part 'pending_connection.g.dart';

/// A single pending org-membership invitation — shown in the wallet banner
/// so the worker can accept or decline a company's access request.
@freezed
abstract class PendingConnection with _$PendingConnection {
  const factory PendingConnection({
    required String id,
    required String orgId,
    required String orgName,
    String? orgLogoUrl,
    required DateTime invitedAt,
  }) = _PendingConnection;

  factory PendingConnection.fromJson(Map<String, dynamic> json) =>
      _$PendingConnectionFromJson(json);
}

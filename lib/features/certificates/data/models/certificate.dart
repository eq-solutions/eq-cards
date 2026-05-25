import 'package:freezed_annotation/freezed_annotation.dart';

part 'certificate.freezed.dart';
part 'certificate.g.dart';

/// A single certificate — First Aid, Working at Heights, LV CPR, induction,
/// etc. Mirrors the `certificates` table.
///
/// `filePath` is the persistent storage path in the `certificates` bucket
/// (format `{userId}/{certificateId}.{ext}`). `fileSignedUrl` is transient —
/// attached post-fetch by [CertificateRepository], expires after 1 hour,
/// never persisted.
@freezed
class Certificate with _$Certificate {
  const factory Certificate({
    String? id,
    required String userId,
    required String title,
    required String certificateType,
    String? issuer,
    DateTime? issueDate,
    DateTime? expiryDate,
    required String filePath,
    // 'pdf' | 'image'
    required String fileType,
    String? notes,
    @Default(true) bool active,
    DateTime? createdAt,
    DateTime? updatedAt,

    /// Transient signed URL — populated by [CertificateRepository] post-fetch.
    /// Expires after 1 hour. NEVER persisted.
    @JsonKey(includeFromJson: false, includeToJson: false)
    String? fileSignedUrl,
  }) = _Certificate;

  const Certificate._();

  factory Certificate.fromJson(Map<String, dynamic> json) =>
      _$CertificateFromJson(json);

  bool get isPdf => fileType == 'pdf';

  /// True if today is strictly after `expiryDate`.
  bool get isExpired =>
      expiryDate != null && DateTime.now().isAfter(expiryDate!);

  /// Whole-day delta to expiry. Null when no expiry date is set.
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(
      expiryDate!.year,
      expiryDate!.month,
      expiryDate!.day,
    );
    return target.difference(today).inDays;
  }

  bool get isExpiringSoon {
    final days = daysUntilExpiry;
    return days != null && !isExpired && days <= 90;
  }

  bool isExpiringWithin({required int days}) {
    final d = daysUntilExpiry;
    return d != null && !isExpired && d <= days;
  }
}

/// Human-readable labels for certificate types.
const certTypeLabels = <String, String>{
  'first_aid': 'First Aid',
  'lv_cpr': 'LV CPR',
  'working_at_heights': 'Working at Heights',
  'white_card': 'White Card',
  'confined_space': 'Confined Space',
  'boom_ewp': 'Boom / EWP',
  'forklift': 'Forklift',
  'dogman': 'Dogman',
  'rigger': 'Rigger',
  'induction': 'Induction',
  'other': 'Other',
};

import 'package:freezed_annotation/freezed_annotation.dart';

part 'licence.freezed.dart';
part 'licence.g.dart';

/// A single wallet card — driver licence, white card, first aid, Medicare,
/// etc. Mirrors the `licences` table in SCHEMA.md.
///
/// Two pairs of photo fields look duplicative but aren't:
///
/// - `photoFrontPath` / `photoBackPath` are the persistent storage paths in
///   the `licence-photos` bucket (format `{userId}/{licenceId}/front.jpg`).
///   These round-trip through `fromJson`/`toJson`.
/// - `photoFrontSignedUrl` / `photoBackSignedUrl` are transient signed URLs
///   the repository attaches post-fetch. They expire after 1 hour. They are
///   excluded from JSON via `@JsonKey(includeFromJson/ToJson: false)` so they
///   never get persisted back.
///
/// `metadata` is a `jsonb` column for type-specific extras (Medicare IRN,
/// driver licence class, forklift HRWL ticket number, etc.). See SCHEMA.md
/// for the per-type key conventions; document new keys there before shipping
/// a licence type that uses them.
@freezed
class Licence with _$Licence {
  const factory Licence({
    /// Null for unsaved drafts; populated by Postgres on insert.
    String? id,
    required String userId,
    required String licenceType,
    required String licenceNumber,
    required DateTime issueDate,
    required DateTime expiryDate,
    String? issuingAuthority,
    String? state,

    /// Storage path in the `licence-photos` bucket — NOT a public URL.
    /// Format: `{userId}/{licenceId}/front.jpg`.
    @JsonKey(name: 'photo_front_url') String? photoFrontPath,
    @JsonKey(name: 'photo_back_url') String? photoBackPath,
    String? notes,
    @Default(<String, dynamic>{}) Map<String, dynamic> metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,

    /// Transient signed URLs populated by `LicenceRepository` post-fetch.
    /// Expire after 1 hour. NEVER persisted.
    @JsonKey(includeFromJson: false, includeToJson: false)
    String? photoFrontSignedUrl,
    @JsonKey(includeFromJson: false, includeToJson: false)
    String? photoBackSignedUrl,
  }) = _Licence;

  const Licence._();

  factory Licence.fromJson(Map<String, dynamic> json) =>
      _$LicenceFromJson(json);

  /// True if today is strictly after `expiryDate`. The day of expiry itself
  /// is treated as still valid.
  bool get isExpired => DateTime.now().isAfter(expiryDate);

  /// Whole-day delta to expiry, normalised to midnight on both sides so
  /// timezone offsets and time-of-day don't tip the count by ±1.
  ///
  /// Negative for already-expired licences. Zero on the day of expiry.
  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return target.difference(today).inDays;
  }

  /// True if not expired and within the 90-day reminder window. Drives the
  /// orange `ExpiryBadge` styling and matches the local-notification
  /// schedule in `AlertsScheduler` (90/30/7-day reminders).
  bool get isExpiringSoon => !isExpired && daysUntilExpiry <= 90;
}

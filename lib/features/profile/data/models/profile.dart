import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// The user's induction-ready profile — the data the wedge ("tap-to-copy")
/// fills onto every site induction form.
///
/// Mirrors the `profiles` table in SCHEMA.md. JSON keys map to snake_case via
/// the `field_rename: snake` config in `build.yaml`.
///
/// Server-managed timestamps are nullable here because client-constructed
/// drafts (e.g. a brand-new profile in the edit form) don't have them yet —
/// the server populates them on insert/update via Postgres triggers.
@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    String? fullName,
    DateTime? dateOfBirth,
    String? mobile,
    String? email,
    String? addressStreet,
    String? addressSuburb,
    String? addressState,
    String? addressPostcode,
    String? emergencyContactName,
    String? emergencyContactRelationship,
    String? emergencyContactMobile,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) = _Profile;

  const Profile._();

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  /// A blank draft for a brand-new user. The repository's upsert path skips
  /// any null fields, so saving an empty draft is a no-op apart from the row
  /// existing.
  factory Profile.empty(String userId) => Profile(id: userId);

  /// True once the wedge can do its job — the user can tap "Copy all profile
  /// fields" and get a usable induction-form payload. Drives the
  /// `CompleteProfileBanner` on the Licences tab; an incomplete profile keeps
  /// the banner showing.
  ///
  /// Email and emergency-contact relationship are intentionally not required:
  /// some inductions skip them, and we don't want the banner to nag users
  /// about fields they may not need.
  bool get isComplete {
    bool ok(String? s) => s != null && s.trim().isNotEmpty;
    return ok(fullName) &&
        dateOfBirth != null &&
        ok(mobile) &&
        ok(addressStreet) &&
        ok(addressSuburb) &&
        ok(addressState) &&
        ok(addressPostcode) &&
        ok(emergencyContactName) &&
        ok(emergencyContactMobile);
  }

  /// Human-readable single-line address built from the four address parts.
  /// Returns null if all parts are empty so callers can render `—` instead
  /// of an empty string.
  String? get fullAddress {
    final parts = [
      addressStreet,
      addressSuburb,
      addressState,
      addressPostcode,
    ].where((p) => p != null && p.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

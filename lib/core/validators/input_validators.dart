import '../../features/auth/data/aus_phone.dart';

/// Field-level validators returning a user-visible error message, or null
/// when the input is valid. Pure — no widgets, no Riverpod, no async.
/// Used by Form `validator:` callbacks and unit-tested independently.
///
/// Convention: empty input is permitted by default (most fields are
/// optional). Each validator has a `required` overload for required-field
/// flows.

/// Australian mobile number — uses the existing E.164 normaliser from
/// the auth feature so the validation matches the OTP-send path exactly.
/// Returns null for empty input (use [validateMobileRequired] when not
/// optional).
String? validateMobile(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  final normalised = normaliseAusMobile(v);
  if (normalised == null || !isValidAusMobile(normalised)) {
    return 'Enter a valid Australian mobile number';
  }
  return null;
}

String? validateMobileRequired(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Mobile is required';
  return validateMobile(value);
}

/// Email — RFC-5321 compliant enough for a wallet form. Matches against a
/// reasonable regex; doesn't try to be a full RFC parser.
String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  // local@domain.tld — allow plus-addressing, dots in local-part, etc.
  const pattern = r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$';
  if (!RegExp(pattern).hasMatch(v)) {
    return 'Enter a valid email address';
  }
  return null;
}

/// Australian postcode — 4 digits.
String? validatePostcode(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  if (!RegExp(r'^\d{4}$').hasMatch(v)) {
    return 'Postcode is 4 digits';
  }
  return null;
}

/// AU state code — must be one of the 8 standard codes when present.
String? validateAuState(String? value) {
  final v = value?.trim().toUpperCase() ?? '';
  if (v.isEmpty) return null;
  const valid = {'NSW', 'VIC', 'QLD', 'WA', 'SA', 'TAS', 'NT', 'ACT'};
  if (!valid.contains(v)) {
    return 'Use NSW / VIC / QLD / WA / SA / TAS / NT / ACT';
  }
  return null;
}

/// Date-of-birth — must be in the past, must be a plausible birth date
/// (not before 1900, not in the future). `null` is accepted (DOB optional).
String? validateDateOfBirth(DateTime? value, {DateTime? now}) {
  if (value == null) return null;
  final today = now ?? DateTime.now();
  if (value.isAfter(today)) return 'Date of birth is in the future';
  if (value.year < 1900) return 'Date of birth is too old to be plausible';
  return null;
}

/// Licence number — non-empty, ≤ 32 chars, alphanumeric / hyphen / space.
/// (32 chars is generous: most AU licence numbers are ≤ 12.)
String? validateLicenceNumber(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Licence number is required';
  if (v.length > 32) return 'Licence number is too long';
  if (!RegExp(r'^[A-Za-z0-9 \-/]+$').hasMatch(v)) {
    return 'Letters, numbers, hyphens and spaces only';
  }
  return null;
}

/// Issue date — must not be in the future. `null` is accepted by the field
/// validator wrapper because the form-level required check is separate.
String? validateIssueDate(DateTime? value, {DateTime? now}) {
  if (value == null) return null;
  final today = now ?? DateTime.now();
  if (value.isAfter(today)) return 'Issue date is in the future';
  if (value.year < 1900) return 'Issue date is too old to be plausible';
  return null;
}

/// Expiry date — must be after the issue date. Past expiries are allowed
/// (you may want to keep a record of an expired licence in your wallet
/// while you renew). `null` is accepted at field level.
String? validateExpiryDate(
  DateTime? value, {
  required DateTime? issueDate,
}) {
  if (value == null) return null;
  if (issueDate != null && !value.isAfter(issueDate)) {
    return 'Expiry must be after the issue date';
  }
  if (value.year > 2100) return 'Expiry is unrealistic';
  return null;
}

/// Postcode-pair sanity for an address. Used to flag obvious paste
/// mistakes (e.g. someone pastes their phone number into the postcode
/// field). Doesn't try to validate that postcode + state agree —
/// Australia Post API would do that and is out of scope.
String? validateAddressLine(String? value, {required String fieldName}) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  if (v.length > 200) return '$fieldName is too long';
  return null;
}

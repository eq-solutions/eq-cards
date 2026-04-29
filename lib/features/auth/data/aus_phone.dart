/// Normalises an Australian mobile number to E.164 format.
///
/// Accepts common Aussie input forms:
///   - `+61412345678` (already E.164)
///   - `61412345678` (missing leading +)
///   - `0412345678` (national format with leading 0)
///   - `412345678` (9 digits starting with 4)
/// Returns the E.164 form, or `null` if input can't be normalised.
///
/// Does NOT validate that the number is a mobile (use [isValidAusMobile]).
String? normaliseAusMobile(String input) {
  final cleaned = input.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return null;
  if (cleaned.startsWith('+61')) return cleaned;
  if (cleaned.startsWith('61') && cleaned.length >= 11) return '+$cleaned';
  if (cleaned.startsWith('0') && cleaned.length == 10) {
    return '+61${cleaned.substring(1)}';
  }
  if (cleaned.startsWith('4') && cleaned.length == 9) return '+61$cleaned';
  return null;
}

/// True if the E.164 string is a valid Australian mobile (`+614XXXXXXXX`).
bool isValidAusMobile(String e164) {
  return RegExp(r'^\+614\d{8}$').hasMatch(e164);
}

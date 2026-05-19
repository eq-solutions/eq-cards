import '../../data/models/licence.dart';

/// Filter buckets for the licence list. `all` is the default; the others
/// are derived purely from existing fields (no new schema). The enum lives
/// here next to its filter function so adding a bucket is a one-file change.
enum LicenceFilter { all, expiringSoon, expired }

extension LicenceFilterLabel on LicenceFilter {
  String get label => switch (this) {
        LicenceFilter.all => 'All',
        LicenceFilter.expiringSoon => 'Expiring soon',
        LicenceFilter.expired => 'Expired',
      };
}

/// Apply search + filter against a list of licences. Pure — no Supabase,
/// no Riverpod, no widgets. Trivial to unit-test against fixture data.
///
/// Order:
/// 1. Filter bucket reduces the list.
/// 2. Search query (case-insensitive substring) further reduces by
///    matching either the type label or the licence number.
List<Licence> applyLicenceFilters(
  List<Licence> input, {
  required Map<String, String> typeLabels,
  required LicenceFilter filter,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  return input.where((l) {
    switch (filter) {
      case LicenceFilter.all:
        break;
      case LicenceFilter.expiringSoon:
        if (!l.isExpiringWithin(days: 30)) return false;
      case LicenceFilter.expired:
        if (!l.isExpired) return false;
    }
    if (q.isEmpty) return true;
    final label = (typeLabels[l.licenceType] ?? l.licenceType).toLowerCase();
    final number = l.licenceNumber.toLowerCase();
    return label.contains(q) || number.contains(q);
  }).toList();
}

/// Maps an OCR-pipeline exception to a one-line user-visible explanation.
/// The full exception goes to Sentry verbatim; this is the "what do I tell
/// the user" mapping. Pure string-in / string-out so it's straightforward
/// to unit-test against the documented error contract.
String ocrErrorMessage(Object e) {
  final s = e.toString().toLowerCase();
  if (s.contains('unsupported_mime_type')) {
    return 'photo format not supported (try a JPEG/PNG)';
  }
  if (s.contains('unauthorized') || s.contains('401')) {
    return 'sign-in expired';
  }
  if (s.contains('anthropic_upstream_error') || s.contains('502')) {
    return 'OCR service is temporarily unavailable';
  }
  if (s.contains('failed host lookup') ||
      s.contains('socketexception') ||
      s.contains('clientexception') ||
      s.contains('typeerror: failed to fetch')) {
    return 'network unreachable';
  }
  if (s.contains('timeout')) {
    return 'OCR took too long';
  }
  return 'an unexpected error occurred';
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Licence type codes that contain sensitive information under the Australian
/// Privacy Act 1988 s6, grouped into consent categories. Consent is recorded
/// once per category — the user is not re-prompted for every upload.
enum SensitiveCategory {
  biometric,
  health,
  criminalHistory;

  String get displayName => switch (this) {
        biometric => 'Identity photo',
        health => 'Health credential',
        criminalHistory => 'Criminal history',
      };

  String get consentDescription => switch (this) {
        biometric =>
          'This licence contains an identity photograph. Under the Australian '
              'Privacy Act 1988, we need your consent before collecting and '
              'storing documents that include identity photos.',
        health =>
          'This credential contains health-related information. Under the '
              'Australian Privacy Act 1988, we need your consent before '
              'collecting and storing health-adjacent credentials.',
        criminalHistory =>
          'A police check contains sensitive information about criminal history. '
              'Under the Australian Privacy Act 1988, we need your consent '
              'before collecting and storing this document.',
      };

  String get whatWeStore => switch (this) {
        biometric =>
          'We store the photo securely and do not use facial recognition '
              'or biometric matching on any images you upload.',
        health =>
          'Only you can see this information unless you choose to share it '
              'with an employer or site.',
        criminalHistory =>
          'Only you can see this information unless you choose to share it '
              'with an employer or site.',
      };
}

/// Returns the [SensitiveCategory] for a licence type code, or null if the
/// type is not considered sensitive under the Privacy Act.
SensitiveCategory? sensitiveCategoryFor(String? typeCode) {
  return switch (typeCode) {
    'driver_licence' || 'passport' || 'photo_id' => SensitiveCategory.biometric,
    'medicare' || 'wwcc' => SensitiveCategory.health,
    'police_check' => SensitiveCategory.criminalHistory,
    _ => null,
  };
}

/// Reads the user's sensitive consent record from profiles.sensitive_consents.
/// Returns a map of category name → ISO-8601 timestamp.
// ignore: specify_nonobvious_property_types
final sensitiveConsentProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return {};
  final res = await Supabase.instance.client
      .from('profiles')
      .select('sensitive_consents')
      .eq('id', user.id)
      .maybeSingle();
  if (res == null || res['sensitive_consents'] == null) return {};
  final raw = res['sensitive_consents'] as Map<String, dynamic>;
  return Map.fromEntries(raw.entries.map((e) => MapEntry(e.key, e.value as String)));
});

/// Records consent for [category] in profiles.sensitive_consents.
/// Merges with existing consents so other categories are preserved.
Future<void> recordSensitiveConsent(
    WidgetRef ref, SensitiveCategory category) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;
  final now = DateTime.now().toUtc().toIso8601String();
  final current = await ref.read(sensitiveConsentProvider.future);
  final updated = {...current, category.name: now};
  await Supabase.instance.client.from('profiles').upsert(
    {'id': user.id, 'sensitive_consents': updated},
    onConflict: 'id',
  );
  ref.invalidate(sensitiveConsentProvider);
}

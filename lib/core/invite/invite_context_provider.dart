import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Display name of the organisation that generated the invite URL, e.g.
/// "SKS Technologies". Populated from the `?org=` query parameter before
/// the app starts; null when the app was opened without an invite link.
///
/// Set via ProviderScope.overrides in main.dart — do not override elsewhere.
final initialOrgNameProvider = Provider<String?>((ref) => null);

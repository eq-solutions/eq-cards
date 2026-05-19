import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'biometric_settings_notifier.g.dart';

@riverpod
class BiometricSettingsNotifier extends _$BiometricSettingsNotifier {
  static const _key = 'biometric_enabled';

  @override
  Future<bool> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true; // default on per architecture §11.4
    } catch (_) {
      // shared_preferences unreachable on web private mode — return the
      // default rather than crashing the Settings build.
      return true;
    }
  }

  Future<void> setEnabled({required bool value}) async {
    state = AsyncData(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Non-fatal — in-memory state already updated.
    }
  }
}

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/privacy/privacy_prefs.dart';

part 'privacy_settings_notifier.g.dart';

/// User opt-out for PostHog analytics. Reads the persisted value via
/// [PrivacyPrefs] on first build, writes through on every flip.
///
/// Default is opted-in (matches Privacy Policy §3.5 "we collect, you may
/// opt out via Settings → Privacy").
@riverpod
class AnalyticsOptOutNotifier extends _$AnalyticsOptOutNotifier {
  @override
  bool build() => PrivacyPrefs.analyticsOptOut;

  Future<void> set({required bool value}) async {
    state = value;
    await PrivacyPrefs.setAnalyticsOptOut(value: value);
  }
}

/// User opt-out for Sentry crash reporting. Same shape + semantics as
/// [AnalyticsOptOutNotifier], wired through to the Sentry `beforeSend` hook
/// configured in `main.dart`.
@riverpod
class CrashReportsOptOutNotifier extends _$CrashReportsOptOutNotifier {
  @override
  bool build() => PrivacyPrefs.crashReportsOptOut;

  Future<void> set({required bool value}) async {
    state = value;
    await PrivacyPrefs.setCrashReportsOptOut(value: value);
  }
}

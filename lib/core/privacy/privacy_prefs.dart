import 'package:shared_preferences/shared_preferences.dart';

/// User opt-out preferences for analytics + crash reporting.
///
/// The Privacy Policy §3.5 + §9 promise users can disable analytics and
/// crash reporting in Settings. This class holds the source-of-truth flags
/// that `AnalyticsService.track` and the Sentry `beforeSend` hook consult
/// on every event.
///
/// Two access patterns:
/// 1. **Synchronous read from anywhere** via the static getters
///    [analyticsOptOut] / [crashReportsOptOut]. Used by Sentry's
///    `beforeSend` callback (must be sync) and by `AnalyticsService.track`
///    (early-return without awaiting shared_preferences on every call).
/// 2. **Persisted writes** via [setAnalyticsOptOut] / [setCrashReportsOptOut].
///    Both update the static cache AND write to shared_preferences. The
///    Settings UI uses these.
///
/// Call [hydrate] once on app startup, before initialising PostHog / Sentry,
/// to load the persisted values into the static cache.
class PrivacyPrefs {
  PrivacyPrefs._();

  static const _analyticsKey = 'pref_analytics_opt_out';
  static const _crashReportsKey = 'pref_crash_reports_opt_out';

  static bool _analyticsOptOut = false;
  static bool _crashReportsOptOut = false;

  /// True when the user has opted out of PostHog analytics events.
  /// Default false (opted in) per the privacy-policy-stated default behaviour.
  static bool get analyticsOptOut => _analyticsOptOut;

  /// True when the user has opted out of Sentry crash reporting. Default
  /// false (opted in). Sentry's `beforeSend` reads this on every event.
  static bool get crashReportsOptOut => _crashReportsOptOut;

  /// Loads the persisted opt-out flags from shared_preferences into the
  /// static cache. Call once at the start of `main()`, before initialising
  /// PostHog / Sentry, so they pick up the user's choice on cold launch.
  ///
  /// Safe to call multiple times. Errors (e.g. shared_preferences
  /// unreachable in some web private-mode browsers) are swallowed — we
  /// fall back to defaults (opted in).
  static Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _analyticsOptOut = prefs.getBool(_analyticsKey) ?? false;
      _crashReportsOptOut = prefs.getBool(_crashReportsKey) ?? false;
    } catch (_) {
      // Defaults already set; leave them.
    }
  }

  /// Persists the analytics opt-out choice and updates the static cache so
  /// `AnalyticsService.track` sees it immediately.
  static Future<void> setAnalyticsOptOut({required bool value}) async {
    _analyticsOptOut = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_analyticsKey, value);
    } catch (_) {
      // In-memory state already updated; the user sees the toggle applied.
    }
  }

  /// Persists the crash-reports opt-out choice and updates the static cache
  /// so Sentry's `beforeSend` sees it immediately for the next captured event.
  static Future<void> setCrashReportsOptOut({required bool value}) async {
    _crashReportsOptOut = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_crashReportsKey, value);
    } catch (_) {
      // In-memory state already updated.
    }
  }
}

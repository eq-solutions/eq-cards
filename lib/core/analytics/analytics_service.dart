import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../privacy/privacy_prefs.dart';

abstract class AnalyticsService {
  static StreamSubscription<AuthState>? _authSub;

  static Future<void> track(
    String event, [
    Map<String, Object>? properties,
  ]) async {
    // Honour the user's analytics opt-out (Privacy Policy §9). The check
    // is sync against the cached PrivacyPrefs static so opting out takes
    // effect on the very next event after the toggle flip.
    if (PrivacyPrefs.analyticsOptOut) return;
    await Posthog().capture(eventName: event, properties: properties);
  }

  /// Identify the current user in PostHog.
  ///
  /// [userId] is the Supabase UUID and is used as the PostHog distinct_id —
  /// the stable cross-app key shared with Shell, Field, and Service (all carry
  /// the same UUID via their respective token handshakes). If [email] is
  /// provided, an alias is created so pre-existing email-based PostHog profiles
  /// merge into this UUID person on first call.
  static Future<void> identify(String userId, {String? email}) async {
    if (PrivacyPrefs.analyticsOptOut) return;
    await Posthog().identify(
      userId: userId,
      userProperties: {
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    // Merge any pre-existing email-based PostHog person into this UUID person.
    // Idempotent — PostHog ignores duplicate alias calls.
    if (email != null && email.isNotEmpty) {
      await Posthog().alias(alias: email.toLowerCase());
    }
  }

  static Future<void> reset() async {
    // Always call reset even when opted out — clears any stale identity
    // PostHog might have buffered before opt-out was set.
    await Posthog().reset();
  }

  /// Subscribes to Supabase auth events so PostHog stays in sync with the
  /// signed-in user. Call once after Supabase + PostHog are initialised.
  ///
  /// - `signedIn` → identify + emit `signup_completed`
  /// - `initialSession` (returning user, persisted session) → identify only
  /// - `signedOut` → reset
  static void startIdentitySync(SupabaseClient client) {
    unawaited(_authSub?.cancel());
    _authSub = client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          if (user != null) {
            unawaited(identify(user.id, email: user.email));
            // Fire signup_completed only for genuinely new auth users.
            // signedIn fires on every login; createdAt within 5 min = new signup.
            final created = DateTime.tryParse(user.createdAt);
            final isNew = created != null &&
                DateTime.now().toUtc().difference(created).abs() <
                    const Duration(minutes: 5);
            if (isNew) {
              unawaited(track('signup_completed', const {'method': 'phone'}));
            }
          }
        case AuthChangeEvent.initialSession:
          if (user != null) unawaited(identify(user.id, email: user.email));
        case AuthChangeEvent.signedOut:
          unawaited(reset());
        case _:
          break;
      }
    });
  }

  /// Emits `app_opened` once at launch with the current platform.
  static Future<void> trackAppOpened() {
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : 'other';
    return track('app_opened', {'platform': platform});
  }
}

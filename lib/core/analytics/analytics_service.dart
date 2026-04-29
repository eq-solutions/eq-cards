import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AnalyticsService {
  static StreamSubscription<AuthState>? _authSub;

  static Future<void> track(
    String event, [
    Map<String, Object>? properties,
  ]) async {
    await Posthog().capture(eventName: event, properties: properties);
  }

  static Future<void> identify(String userId) async {
    await Posthog().identify(userId: userId);
  }

  static Future<void> reset() async {
    await Posthog().reset();
  }

  /// Subscribes to Supabase auth events so PostHog stays in sync with the
  /// signed-in user. Call once after Supabase + PostHog are initialised.
  ///
  /// - `signedIn` → identify + emit `signup_completed`
  /// - `initialSession` (returning user, persisted session) → identify only
  /// - `signedOut` → reset
  static void startIdentitySync(SupabaseClient client) {
    _authSub?.cancel();
    _authSub = client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          if (user != null) {
            unawaited(identify(user.id));
            unawaited(track('signup_completed', const {'method': 'phone'}));
          }
        case AuthChangeEvent.initialSession:
          if (user != null) unawaited(identify(user.id));
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

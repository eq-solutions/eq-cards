import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/analytics/analytics_service.dart';
import 'core/invite/invite_context_provider.dart';
import 'core/privacy/privacy_prefs.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const _posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');
const _posthogHost = String.fromEnvironment(
  'POSTHOG_HOST',
  defaultValue: 'https://us.i.posthog.com',
);

Future<void> main() async {
  // Capture invite org name BEFORE usePathUrlStrategy() — once the URL
  // strategy is changed, GoRouter rewrites window.location and the original
  // query params are lost. Read them now while the raw URL is still intact.
  final inviteOrgName = kIsWeb ? Uri.base.queryParameters['org'] : null;

  // Path-based URLs — required for the #sh=<jwt> Shell handoff. Hash strategy
  // would treat #sh=<jwt> as a route path; path strategy treats it as a URL
  // fragment so GoRouter sees "/" and IframeHandoffScreen reads the hash.
  usePathUrlStrategy();

  // Single runZonedGuarded around everything: binding init, plugin setup, Sentry
  // init (without `appRunner` — we call runApp ourselves), and runApp all
  // execute in the same zone. This avoids the "Zone mismatch" assertion that
  // fires when runApp's zone differs from the binding's zone, which is what
  // happens if you let Sentry's `appRunner` wrap runApp in its own zone.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      assert(
        _supabaseUrl.isNotEmpty,
        'SUPABASE_URL must be passed via --dart-define',
      );
      assert(
        _supabaseAnonKey.isNotEmpty,
        'SUPABASE_ANON_KEY must be passed via --dart-define',
      );

      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);

      // Load user privacy opt-out flags before initialising analytics +
      // crash reporting so the user's stored choice gates the very first
      // event of the session.
      await PrivacyPrefs.hydrate();

      if (_posthogApiKey.isNotEmpty) {
        // posthog_flutter 4.x: `host` is a settable property on PostHogConfig,
        // not a constructor named parameter.
        final config = PostHogConfig(_posthogApiKey)..host = _posthogHost;
        await Posthog().setup(config);
        AnalyticsService.startIdentitySync(Supabase.instance.client);
        unawaited(AnalyticsService.trackAppOpened());
      }

      // Sentry init is fire-and-forget. Awaiting it on web has been observed
      // to hang past Supabase init and never reach runApp (blank screen).
      // Errors that fire before init resolves still get captured by the
      // runZonedGuarded handler below; they queue and flush once Sentry's
      // ready.
      if (_sentryDsn.isNotEmpty) {
        unawaited(
          SentryFlutter.init((options) {
            options.dsn = _sentryDsn;
            options.tracesSampleRate = 0.1;
            // beforeSend reads the static PrivacyPrefs cache on every
            // event. Toggling the Settings → Privacy switch updates the
            // cache, so opt-out takes effect for the very next event.
            options.beforeSend = (event, hint) {
              if (PrivacyPrefs.crashReportsOptOut) return null;
              return event;
            };
          }),
        );
      }

      runApp(
        ProviderScope(
          overrides: [
            if (inviteOrgName != null)
              initialOrgNameProvider.overrideWithValue(inviteOrgName),
          ],
          child: const EqCardsApp(),
        ),
      );
    },
    (error, stack) {
      // Uncaught zone errors → Sentry, if it's wired up.
      if (_sentryDsn.isNotEmpty) {
        unawaited(Sentry.captureException(error, stackTrace: stack));
      }
    },
  );
}

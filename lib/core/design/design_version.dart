import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'design_version.g.dart';

/// The 3 design directions exposed in Settings → Design. Switching versions
/// re-renders LicenceCard, LicenceDetail, the home empty state, and the app
/// icon preview without touching any other behaviour. Brand tokens (colors,
/// type, spacing) are shared across versions; only layout / hierarchy /
/// emphasis differ.
enum DesignVersion {
  /// Linear/Notion-style minimal: thin borders, no shadows, fields stacked,
  /// type label + number prominent. Closest to the original 0.1.0 release.
  linear,

  /// Apple Wallet-style: rounded-rect cards with a brand-stripe header,
  /// type as oversized title, photo overlapping bottom edge.
  wallet,

  /// Photo-forward: licence photo dominates, text overlays with subtle scrim,
  /// most "card in your pocket" feel.
  photoFirst,
}

extension DesignVersionLabel on DesignVersion {
  String get label => switch (this) {
        DesignVersion.linear => 'Linear (minimal)',
        DesignVersion.wallet => 'Wallet (Apple-style)',
        DesignVersion.photoFirst => 'Photo-first',
      };

  String get description => switch (this) {
        DesignVersion.linear =>
          'Thin borders, no shadows, fields stacked. Closest to the original.',
        DesignVersion.wallet =>
          'Rounded cards with a brand stripe, oversized type, photo overlap.',
        DesignVersion.photoFirst =>
          'Licence photo dominates, text overlays, "card in your pocket" feel.',
      };
}

const _prefsKey = 'design_version';

@Riverpod(keepAlive: true)
class DesignVersionNotifier extends _$DesignVersionNotifier {
  @override
  DesignVersion build() {
    // Default surfaces with linear; load real value asynchronously so the
    // first frame doesn't flash if a different version is persisted.
    unawaited(_load());
    return DesignVersion.linear;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final match = DesignVersion.values
          .where((v) => v.name == raw)
          .firstOrNull;
      if (match != null && match != state) state = match;
    } catch (_) {
      // shared_preferences unreachable on web private mode in some
      // browsers; keep the in-memory default rather than crashing.
    }
  }

  Future<void> set(DesignVersion version) async {
    state = version;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, version.name);
    } catch (_) {
      // Persist-failure is non-fatal; state still updates in-memory for
      // the rest of the session.
    }
  }
}

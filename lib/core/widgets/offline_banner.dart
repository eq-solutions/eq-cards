import 'package:flutter/material.dart';

import '../services/wallet_cache_service.dart';
import '../theme/eq_typography.dart';

/// Full-width amber banner shown when the device is offline AND the wallet
/// data was served from the local cache rather than from Supabase.
///
/// Placed at the very top of the licences list screen so it is always visible
/// regardless of list scroll position.
///
/// On native builds the widget collapses to a zero-height [SizedBox] because
/// [WalletCacheService.isOffline] always returns false on non-web platforms.
class OfflineBanner extends StatelessWidget {
  /// [fromCache] should be true when the wallet data was loaded from the
  /// local offline cache, false when it came from a live Supabase fetch.
  const OfflineBanner({super.key, required this.fromCache});

  final bool fromCache;

  // Amber — not in EqColours (brand palette is sky/deep/ink). Using the
  // standard Tailwind amber-500 value per the spec.
  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    if (!WalletCacheService.isOffline || !fromCache) {
      return const SizedBox.shrink();
    }
    return ColoredBox(
      color: _amber,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "You're offline — showing last synced data",
                style: EqTypography.label.copyWith(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

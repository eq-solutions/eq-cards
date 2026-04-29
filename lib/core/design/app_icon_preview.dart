import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import 'design_version.dart';

/// Renders a 3-direction app-icon mock for review in Settings. These are
/// pure-Flutter renders, not the real PNG/ICO files — once a direction is
/// chosen, those need to be generated via an image-export tool or a designer
/// (Figma plugin / AI image-gen). The mock here is the source of truth for
/// the design intent.
///
/// All three respect the EQ brand: Plus Jakarta Sans, sky/deep palette, no
/// gradients, no shadows, Linear/Notion aesthetic.
class AppIconPreview extends StatelessWidget {
  const AppIconPreview({
    super.key,
    required this.version,
    this.size = 96,
  });

  final DesignVersion version;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.225), // iOS app-icon ratio.
      child: SizedBox(
        width: size,
        height: size,
        child: switch (version) {
          DesignVersion.linear => _LinearIcon(size: size),
          DesignVersion.wallet => _WalletIcon(size: size),
          DesignVersion.photoFirst => _PhotoFirstIcon(size: size),
        },
      ),
    );
  }
}

// =====================================================================
// Linear — the actual installed launcher icon (EQ infinity-loop mark in
// sky on a white background). Loaded from `assets/icon/launcher.png` so
// the in-app preview matches the user's real home-screen icon. If the
// asset isn't present yet, falls back to a wordmark mock.
// =====================================================================
class _LinearIcon extends StatelessWidget {
  const _LinearIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EqColours.white,
      child: Image.asset(
        'assets/icon/launcher.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _LinearWordmarkFallback(size: size),
      ),
    );
  }
}

/// Pre-asset placeholder for `_LinearIcon`. Renders the original "EQ"
/// wordmark on sky so the picker remains usable before the launcher PNG
/// has been dropped into `assets/icon/`.
class _LinearWordmarkFallback extends StatelessWidget {
  const _LinearWordmarkFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EqColours.sky,
      child: Center(
        child: Text(
          'EQ',
          style: TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: EqColours.white,
            letterSpacing: -size * 0.005,
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Wallet — stylised licence-card silhouette on ice background, with the
// brand stripe and a placeholder photo dot. References the Wallet variant
// of LicenceCard so the icon matches what the app shows.
// =====================================================================
class _WalletIcon extends StatelessWidget {
  const _WalletIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EqColours.ice,
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: Container(
          decoration: BoxDecoration(
            color: EqColours.white,
            borderRadius: BorderRadius.circular(size * 0.06),
            border: Border.all(color: EqColours.border),
          ),
          child: Stack(
            children: [
              ColoredBox(
                color: EqColours.sky,
                child: SizedBox(
                  width: double.infinity,
                  height: size * 0.08,
                ),
              ),
              Positioned(
                left: size * 0.08,
                top: size * 0.22,
                right: size * 0.08,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: size * 0.30,
                      height: size * 0.04,
                      color: EqColours.deep,
                    ),
                    SizedBox(height: size * 0.04),
                    Container(
                      width: size * 0.55,
                      height: size * 0.10,
                      color: EqColours.ink,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: size * 0.08,
                bottom: size * 0.08,
                child: Container(
                  width: size * 0.16,
                  height: size * 0.16,
                  decoration: BoxDecoration(
                    color: EqColours.ice,
                    borderRadius: BorderRadius.circular(size * 0.03),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Photo-first — full-bleed brand colour with a centered "ID" badge mark
// that hints at the licence-photo wedge. Bold, immediately readable.
// =====================================================================
class _PhotoFirstIcon extends StatelessWidget {
  const _PhotoFirstIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EqColours.ink,
      child: Center(
        child: Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: BoxDecoration(
            color: EqColours.sky,
            borderRadius: BorderRadius.circular(size * 0.10),
          ),
          child: Center(
            child: Icon(
              Icons.badge_outlined,
              size: size * 0.42,
              color: EqColours.white,
            ),
          ),
        ),
      ),
    );
  }
}

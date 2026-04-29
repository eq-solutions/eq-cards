import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_typography.dart';

class EqAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EqAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.withBranding = false,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  /// When true, the EQ launcher mark renders next to the title. Used on the
  /// three shell screens (Licences, Profile, Settings) for persistent brand
  /// presence; deep routes (detail / edit) keep the simple title so the
  /// auto-back button isn't competing with the mark.
  final bool withBranding;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: EqColours.sky,
      foregroundColor: EqColours.white,
      elevation: 0,
      title: withBranding ? _BrandedTitle(title: title) : _PlainTitle(title: title),
      actions: actions,
      leading: leading,
    );
  }
}

class _PlainTitle extends StatelessWidget {
  const _PlainTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: EqTypography.headingM.copyWith(color: EqColours.white),
    );
  }
}

class _BrandedTitle extends StatelessWidget {
  const _BrandedTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // White-on-transparent variant of the EQ mark — sits naturally on
        // the sky AppBar without a chip / background. Same asset Android
        // adaptive icons use as the foreground layer.
        Image.asset(
          'assets/icon/launcher_foreground.png',
          width: 36,
          height: 36,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _BrandedFallback(),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: EqTypography.headingM.copyWith(color: EqColours.white),
        ),
      ],
    );
  }
}

class _BrandedFallback extends StatelessWidget {
  const _BrandedFallback();
  @override
  Widget build(BuildContext context) {
    return Text(
      'EQ',
      style: EqTypography.label.copyWith(
        color: EqColours.white,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

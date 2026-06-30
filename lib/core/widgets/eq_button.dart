import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_typography.dart';

enum EqButtonVariant { primary, secondary, destructive, hero }

class EqButton extends StatelessWidget {
  const EqButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = EqButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final EqButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (variant) {
      EqButtonVariant.primary     => (EqColours.sky, EqColours.white),
      EqButtonVariant.secondary   => (EqColours.ice, EqColours.deep),
      EqButtonVariant.destructive => (EqColours.error, EqColours.white),
      EqButtonVariant.hero        => (EqColours.sky, EqColours.white),
    };

    // V9 spec: CTA buttons are always radius 13 (never pill, never the 6px
    // control radius). The prominent primary/hero CTA is 50px tall, 800
    // weight; secondary/destructive stay 48px/600 as supporting actions.
    final bool isPrimaryCta =
        variant == EqButtonVariant.hero || variant == EqButtonVariant.primary;
    final double height     = isPrimaryCta ? 50 : 48;
    const double radius     = 13;
    final FontWeight weight = isPrimaryCta ? FontWeight.w800 : FontWeight.w600;

    final button = SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.5),
          disabledForegroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator.adaptive(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(foreground),
                ),
              )
            : Text(
                label,
                style: EqTypography.bodyL.copyWith(
                  color: foreground,
                  fontWeight: weight,
                ),
              ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

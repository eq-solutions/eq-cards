import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_typography.dart';

enum EqButtonVariant { primary, secondary, destructive }

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
      EqButtonVariant.primary => (EqColours.sky, EqColours.white),
      EqButtonVariant.secondary => (EqColours.ice, EqColours.deep),
      EqButtonVariant.destructive => (EqColours.error, EqColours.white),
    };

    final button = SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.5),
          disabledForegroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(foreground),
                ),
              )
            : Text(
                label,
                style: EqTypography.bodyL.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

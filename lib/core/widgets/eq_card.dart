import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';

class EqCard extends StatelessWidget {
  const EqCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(EqSpacing.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EqColours.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: EqColours.outlineSoft),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

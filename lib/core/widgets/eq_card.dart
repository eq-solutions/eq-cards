import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';

class EqCard extends StatelessWidget {
  const EqCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(EqSpacing.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EqColours.ice,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

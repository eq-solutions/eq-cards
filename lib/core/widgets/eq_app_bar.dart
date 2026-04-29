import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_typography.dart';

class EqAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EqAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: EqColours.sky,
      foregroundColor: EqColours.white,
      elevation: 0,
      title: Text(
        title,
        style: EqTypography.headingM.copyWith(color: EqColours.white),
      ),
      actions: actions,
      leading: leading,
    );
  }
}

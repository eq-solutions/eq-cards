import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_typography.dart';

/// Prev / next navigation bar for detail screens that have a sibling list.
/// Shows "N of M" with chevron buttons; hidden automatically when total ≤ 1.
class ItemNavBar extends StatelessWidget {
  const ItemNavBar({
    super.key,
    required this.current,
    required this.total,
    this.onPrev,
    this.onNext,
  });

  final int current;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EqColours.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1, color: EqColours.border),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: IconButton(
                      icon: Icon(
                        Icons.chevron_left,
                        color: onPrev != null
                            ? EqColours.deep
                            : EqColours.border,
                      ),
                      onPressed: onPrev,
                      tooltip: 'Previous',
                    ),
                  ),
                  Text(
                    '$current of $total',
                    style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: onNext != null
                              ? EqColours.deep
                              : EqColours.border,
                        ),
                        onPressed: onNext,
                        tooltip: 'Next',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

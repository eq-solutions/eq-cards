import 'package:flutter/material.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../../../core/widgets/eq_button.dart';

/// V9 wizard chrome: progress bar, step pill, back arrow, bottom action bar.
///
/// Wrap each full-screen wizard step with this. The [child] provides the
/// scrollable step content; [onAction] is the primary forward button.
class WizardShell extends StatelessWidget {
  const WizardShell({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.actionLabel,
    required this.onAction,
    required this.child,
    this.onBack,
    this.isActionLoading = false,
    this.actionEnabled = true,
  });

  final int step;
  final int totalSteps;
  final String actionLabel;
  final VoidCallback? onAction;
  final Widget child;
  final VoidCallback? onBack;
  final bool isActionLoading;
  final bool actionEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Back arrow + step pill
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EqSpacing.md, EqSpacing.md, EqSpacing.md, 0,
              ),
              child: Row(
                children: [
                  if (onBack != null)
                    GestureDetector(
                      onTap: onBack,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 22,
                          color: EqColours.ink,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 30),
                  const Spacer(),
                  Text(
                    'Step $step of $totalSteps',
                    style: EqTypography.label.copyWith(
                      color: EqColours.g500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: EqSpacing.sm),
            // 3px sky progress bar
            LinearProgressIndicator(
              value: step / totalSteps,
              minHeight: 3,
              backgroundColor: EqColours.outline,
              valueColor: const AlwaysStoppedAnimation<Color>(EqColours.sky),
            ),
            // Step content
            Expanded(child: child),
            // Bottom action bar
            Container(
              decoration: const BoxDecoration(
                color: EqColours.bg,
                border: Border(
                  top: BorderSide(color: EqColours.outlineSoft),
                ),
              ),
              padding: const EdgeInsets.all(EqSpacing.md),
              child: EqButton(
                label: actionLabel,
                onPressed: (actionEnabled && !isActionLoading) ? onAction : null,
                isLoading: isActionLoading,
                fullWidth: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

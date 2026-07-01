import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';

/// Animated "reading…" dialog shown while an OCR call is in-flight.
///
/// After 5 s a cancel button appears so the user can skip OCR and fill
/// fields manually. Pop returns `true` when the user skips, `false`/null
/// when OCR finishes first.
class OcrLoadingDialog extends StatefulWidget {
  /// Short noun inserted into the loading copy, e.g. 'licence', 'certificate'.
  const OcrLoadingDialog({super.key, this.noun = 'card'});

  final String noun;

  @override
  State<OcrLoadingDialog> createState() => _OcrLoadingDialogState();
}

class _OcrLoadingDialogState extends State<OcrLoadingDialog> {
  bool _allowCancel = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 9s, not 5 — the copy below tells the user scans usually take 5-10s,
    // so a 5s threshold flagged most completely normal scans (edge function
    // logs: 6.5-9.8s typical) as "taking longer than usual".
    _timer = Timer(const Duration(seconds: 9), () {
      if (mounted) setState(() => _allowCancel = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowCancel,
      child: Dialog(
        backgroundColor: EqColours.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(EqSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: EqColours.sky,
                ),
              ),
              const SizedBox(height: EqSpacing.md),
              Text(
                'Reading your ${widget.noun}…',
                style: EqTypography.bodyL,
              ),
              const SizedBox(height: EqSpacing.xs),
              Text(
                _allowCancel
                    ? "Still reading — you're welcome to fill it in "
                        'yourself instead.'
                    : 'Usually 5–10 seconds. '
                        'First scan of the day may take a little longer.',
                textAlign: TextAlign.center,
                style: EqTypography.label.copyWith(color: EqColours.grey),
              ),
              if (_allowCancel) ...[
                const SizedBox(height: EqSpacing.md),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'Skip OCR, fill manually',
                    style: EqTypography.bodyM.copyWith(color: EqColours.deep),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

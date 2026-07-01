import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/eq_colours.dart';
import '../../core/theme/eq_spacing.dart';
import '../../core/theme/eq_typography.dart';
import '../../core/widgets/eq_button.dart';

/// Full-screen first-login screen shown once when a new user's wallet is empty.
/// Pops with [ImageSource.camera], [ImageSource.gallery], or null (set up later).
/// The caller uses the result to launch the appropriate capture flow directly,
/// bypassing any additional source-picker sheet.
class FirstScanScreen extends StatefulWidget {
  const FirstScanScreen({super.key});

  @override
  State<FirstScanScreen> createState() => _FirstScanScreenState();
}

class _FirstScanScreenState extends State<FirstScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    unawaited(_ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.ink,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EqSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 3),
                  const Icon(
                    Icons.camera_alt_outlined,
                    size: 48,
                    color: EqColours.sky,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  Text(
                    'Add your first licence',
                    style: EqTypography.headingL.copyWith(
                      color: EqColours.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Text(
                    'Point at a licence or certificate — we read the '
                    'details automatically.',
                    style: EqTypography.bodyM.copyWith(
                      color: EqColours.white.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(flex: 4),
                  EqButton(
                    label: 'Take a photo',
                    onPressed: () =>
                        Navigator.of(context).pop(ImageSource.camera),
                    fullWidth: true,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Upload from album'),
                      onPressed: () =>
                          Navigator.of(context).pop(ImageSource.gallery),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: EqColours.white,
                        side: BorderSide(
                          color: EqColours.white.withValues(alpha: 0.25),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        textStyle: EqTypography.bodyL
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(
                      'Set up later',
                      style: EqTypography.bodyM.copyWith(
                        color: EqColours.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: EqSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/eq_colours.dart';
import '../../core/theme/eq_spacing.dart';
import '../../core/theme/eq_typography.dart';
import '../../core/widgets/eq_button.dart';

/// Full-screen first-login onboarding moment shown once when a new user's
/// wallet is empty. Tapping "Scan now" pops with `true` so the caller can
/// immediately launch the capture flow; "Set up later" pops with `false`.
///
/// Shown by LicencesListScreen after verifying the
/// `eq_cards.first_scan_shown` SharedPreferences flag is unset.
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
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _MockCard(),
                  const SizedBox(height: EqSpacing.xl),
                  Text(
                    'Add your first credential',
                    style: EqTypography.headingL.copyWith(
                      color: EqColours.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Text(
                    'Scan a licence or certificate — we read the details '
                    'automatically. Your employer can check your credentials '
                    'are current, anytime.',
                    style: EqTypography.bodyM.copyWith(
                      color: EqColours.white.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(flex: 3),
                  EqButton(
                    label: 'Scan now',
                    onPressed: () => Navigator.of(context).pop(true),
                    fullWidth: true,
                  ),
                  const SizedBox(height: EqSpacing.md),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
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

/// A static mock of what a filled credential card looks like — gives new
/// users a concrete preview of the end result before they scan anything.
class _MockCard extends StatelessWidget {
  const _MockCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 158,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: EqColours.sky.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 18,
            left: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bar(width: 44, height: 6, opacity: 0.9),
                const SizedBox(height: 6),
                _Bar(width: 88, height: 4, opacity: 0.35),
                const SizedBox(height: 28),
                Row(
                  children: [
                    _Bar(width: 56, height: 4, opacity: 0.5),
                    const SizedBox(width: 12),
                    _Bar(width: 72, height: 4, opacity: 0.5),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Bar(width: 40, height: 4, opacity: 0.3),
                    const SizedBox(width: 12),
                    _Bar(width: 56, height: 4, opacity: 0.3),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Icon(
              Icons.verified_outlined,
              color: EqColours.sky.withValues(alpha: 0.7),
              size: 20,
            ),
          ),
          Positioned(
            bottom: 14,
            right: 16,
            child: Text(
              'EQ Cards',
              style: TextStyle(
                color: EqColours.white.withValues(alpha: 0.25),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.opacity});
  final double width;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EqColours.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

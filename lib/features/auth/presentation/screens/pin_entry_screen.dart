import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/eq_colours.dart';
import '../../../../core/theme/eq_spacing.dart';
import '../../../../core/theme/eq_typography.dart';
import '../../data/auth_repository.dart';
import '../notifiers/app_lock_notifier.dart';

/// PIN unlock screen — shown on every cold start when a valid session exists
/// and the user has already set a PIN.
///
/// Max 5 incorrect attempts before signing out and returning to email auth.
class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  String _pin = '';
  bool _isVerifying = false;
  String? _error;
  int _attempts = 0;
  static const _maxAttempts = 5;

  void _onDigit(String digit) {
    if (_pin.length >= 4 || _isVerifying) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isVerifying) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_pin.length != 4 || _isVerifying) return;
    setState(() => _isVerifying = true);

    final ok =
        await ref.read(appLockNotifierProvider.notifier).verifyPin(_pin);

    if (!mounted) return;

    if (ok) return; // router redirect handles navigation

    _attempts++;
    if (_attempts >= _maxAttempts) {
      await ref.read(authRepositoryProvider).signOut();
      return;
    }

    setState(() {
      _isVerifying = false;
      _pin = '';
      _error = _attempts >= _maxAttempts - 1
          ? 'Incorrect PIN. One attempt left — then you\'ll need to sign in with email.'
          : 'Incorrect PIN. Try again.';
    });
  }

  Future<void> _useEmail() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.lg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Text(
                    'Enter your PIN',
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Text(
                    'Enter your 4-digit PIN to unlock EQ Cards.',
                    style:
                        EqTypography.bodyM.copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  _PinDots(length: _pin.length),
                  if (_error != null) ...[
                    const SizedBox(height: EqSpacing.md),
                    Text(
                      _error!,
                      style: EqTypography.label
                          .copyWith(color: EqColours.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const Spacer(),
                  _Numpad(
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    disabled: _isVerifying,
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  TextButton.icon(
                    onPressed: _isVerifying ? null : _useEmail,
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Forgot PIN? Sign out'),
                    style: TextButton.styleFrom(
                      foregroundColor: EqColours.grey,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── PIN setup screen ──────────────────────────────────────────────────────────

/// PIN setup screen — shown after a successful OTP when no PIN is set yet.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  String? _firstPin; // set after phase 1
  bool _isSaving = false;
  String? _error;

  bool get _isConfirming => _firstPin != null;

  String get _title =>
      _isConfirming ? 'Confirm your PIN' : 'Choose a PIN';

  String get _subtitle => _isConfirming
      ? 'Enter your PIN again to confirm.'
      : 'Pick a 4-digit PIN. You\'ll use it every time you open EQ Cards.';

  void _onDigit(String digit) {
    if (_pin.length >= 4 || _isSaving) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _advance();
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isSaving) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _advance() {
    if (!_isConfirming) {
      // Phase 1 complete — move to confirmation
      setState(() {
        _firstPin = _pin;
        _pin = '';
      });
      return;
    }

    // Phase 2 — check match
    if (_pin == _firstPin) {
      _save();
    } else {
      setState(() {
        _firstPin = null;
        _pin = '';
        _error = 'PINs didn\'t match. Start again.';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(appLockNotifierProvider.notifier).setupPin(_pin);
      // router redirect handles navigation to /licences
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _firstPin = null;
        _pin = '';
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EqSpacing.xl,
                vertical: EqSpacing.lg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Text(
                    _title,
                    style: EqTypography.headingL.copyWith(
                      fontWeight: FontWeight.w700,
                      color: EqColours.deep,
                    ),
                  ),
                  const SizedBox(height: EqSpacing.sm),
                  Text(
                    _subtitle,
                    style: EqTypography.bodyM
                        .copyWith(color: EqColours.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  _PinDots(length: _pin.length),
                  if (_error != null) ...[
                    const SizedBox(height: EqSpacing.md),
                    Text(
                      _error!,
                      style: EqTypography.label
                          .copyWith(color: EqColours.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const Spacer(),
                  _Numpad(
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    disabled: _isSaving,
                  ),
                  const SizedBox(height: EqSpacing.xl),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            ref
                                .read(appLockNotifierProvider.notifier)
                                .skipPinSetup();
                          },
                    child: Text(
                      'Skip for now',
                      style: EqTypography.bodyM
                          .copyWith(color: EqColours.grey),
                    ),
                  ),
                  const SizedBox(height: EqSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length});
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < length;
        return Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? EqColours.deep : Colors.transparent,
            border: Border.all(
              color: filled ? EqColours.deep : EqColours.grey,
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}

class _Numpad extends StatelessWidget {
  const _Numpad({
    required this.onDigit,
    required this.onBackspace,
    required this.disabled,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final bool disabled;

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _keys.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            if (key.isEmpty) {
              return const SizedBox(width: 88, height: 72);
            }
            final isBackspace = key == '⌫';
            return GestureDetector(
              onTap: disabled
                  ? null
                  : () => isBackspace ? onBackspace() : onDigit(key),
              child: Container(
                width: 88,
                height: 72,
                alignment: Alignment.center,
                child: isBackspace
                    ? Icon(
                        Icons.backspace_outlined,
                        size: 22,
                        color: disabled ? EqColours.grey : EqColours.ink,
                      )
                    : Text(
                        key,
                        style: EqTypography.headingM.copyWith(
                          color: disabled ? EqColours.grey : EqColours.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

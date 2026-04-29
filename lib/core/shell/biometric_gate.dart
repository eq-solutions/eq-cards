import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../features/settings/settings.dart';
import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';
import '../widgets/eq_button.dart';

/// Wraps the app's screens; presents a lock screen until biometric auth
/// succeeds. Re-locks if the app is backgrounded for ≥ 5 minutes.
///
/// On web (`kIsWeb`) the gate short-circuits — browser session security covers
/// the equivalent for v1. Architecture §11.4–§11.5.
///
/// If biometrics are disabled in settings or the device cannot check them,
/// the gate falls open without blocking.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  static const _backgroundLockThreshold = Duration(minutes: 5);

  bool _locked = !kIsWeb; // never start locked on web
  bool _verifying = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed &&
        _backgroundedAt != null) {
      final away = DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (away >= _backgroundLockThreshold && !_locked) {
        setState(() => _locked = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
      }
    }
  }

  Future<void> _verify() async {
    if (_verifying || kIsWeb) return;

    final enabled = await ref
        .read(biometricSettingsNotifierProvider.future)
        .catchError((_) => true);
    if (!enabled) {
      if (mounted) setState(() => _locked = false);
      return;
    }

    setState(() => _verifying = true);
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!supported || !canCheck) {
        if (mounted) {
          setState(() {
            _locked = false;
            _verifying = false;
          });
        }
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Unlock EQ Cards',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (mounted) {
        setState(() {
          _locked = !ok;
          _verifying = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locked = false;
          _verifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return Scaffold(
      backgroundColor: EqColours.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(EqSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: EqColours.deep,
                ),
                const SizedBox(height: EqSpacing.md),
                Text('EQ Cards', style: EqTypography.headingXL),
                const SizedBox(height: EqSpacing.sm),
                Text(
                  'Locked. Unlock with Face ID, Touch ID, or device passcode.',
                  style: EqTypography.bodyM.copyWith(color: EqColours.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: EqSpacing.xl),
                EqButton(
                  label: 'Unlock',
                  onPressed: _verifying ? null : _verify,
                  isLoading: _verifying,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/routes.dart';
import '../../core/theme/eq_colours.dart';
import '../../core/theme/eq_spacing.dart';
import '../../core/theme/eq_typography.dart';

// ignore: specify_nonobvious_property_types — FutureProvider.autoDispose<T> is not exported by riverpod
final consentStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return true;
  final res = await Supabase.instance.client
      .from('profiles')
      .select('consented_at')
      .eq('id', user.id)
      .maybeSingle();
  if (res == null) return false;
  return res['consented_at'] != null;
});

/// Wraps [child] with a full-screen consent gate shown once — the first
/// time a worker opens their wallet after account creation. Records
/// `profiles.consented_at` via the authenticated client on agreement.
class ConsentGate extends ConsumerWidget {
  const ConsentGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGate = ref.watch(consentStatusProvider).maybeWhen(
          data: (hasConsented) => !hasConsented,
          orElse: () => false,
        );

    return Stack(
      children: [
        child,
        if (showGate)
          _ConsentOverlay(
            onAgreed: () => ref.invalidate(consentStatusProvider),
          ),
      ],
    );
  }
}

class _ConsentOverlay extends StatefulWidget {
  const _ConsentOverlay({required this.onAgreed});

  final VoidCallback onAgreed;

  @override
  State<_ConsentOverlay> createState() => _ConsentOverlayState();
}

class _ConsentOverlayState extends State<_ConsentOverlay> {
  bool _saving = false;

  Future<void> _agree() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final now = DateTime.now().toUtc().toIso8601String();
        await Supabase.instance.client.from('profiles').upsert(
          {'id': user.id, 'consented_at': now},
          onConflict: 'id',
        );
      }
      widget.onAgreed();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: const Border(
              top: BorderSide(color: Color(0x1A000000)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            EqSpacing.md,
            EqSpacing.md,
            EqSpacing.md,
            EqSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(
                  style: EqTypography.bodyM.copyWith(
                    color: const Color(0xFF555555),
                    height: 1.55,
                  ),
                  children: [
                    const TextSpan(
                      text: 'EQ Cards stores your credentials so employers '
                          'can view them. By using your wallet you agree to '
                          'our ',
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => context.push(Routes.privacyPolicy),
                        child: Text(
                          'Privacy Policy',
                          style: EqTypography.bodyM.copyWith(
                            color: EqColours.sky,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: EqSpacing.sm),
              FilledButton(
                onPressed: _saving ? null : _agree,
                style: FilledButton.styleFrom(
                  backgroundColor: EqColours.sky,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: EqColours.sky.withValues(alpha: 0.5),
                  padding:
                      const EdgeInsets.symmetric(vertical: EqSpacing.sm + 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('I agree'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

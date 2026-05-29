import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/shell/biometric_gate.dart';
import 'core/theme/eq_theme.dart';
import 'features/auth/presentation/notifiers/shell_session_refresh.dart';

class EqCardsApp extends ConsumerWidget {
  const EqCardsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Keep the Shell-minted JWT fresh for the whole app session while embedded
    // in the EQ Shell iframe (no-op on native / non-iframe builds).
    ref.watch(shellSessionRefreshProvider);

    return MaterialApp.router(
      title: 'EQ Cards',
      theme: EqTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // BiometricGate wraps EVERY screen via the router builder so it
      // applies before any feature renders. On web it short-circuits.
      builder: (context, child) => BiometricGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

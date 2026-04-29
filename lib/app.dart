import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/shell/biometric_gate.dart';
import 'core/theme/eq_theme.dart';

class EqCardsApp extends ConsumerWidget {
  const EqCardsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

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

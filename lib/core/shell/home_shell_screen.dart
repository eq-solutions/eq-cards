import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../features/alerts/alerts.dart';
import '../theme/eq_colours.dart';
import '../theme/eq_spacing.dart';
import '../theme/eq_typography.dart';

class HomeShellScreen extends ConsumerWidget {
  const HomeShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Single listener on the combined provider — fires once whenever either
    // licences or credentials settle, with both lists together. Prevents the
    // two-listener pattern where each cancelAll wipes the other's scheduled
    // notifications mid-loop.
    ref.listen(expiryAlertListsProvider, (_, lists) {
      if (lists == null) return;
      unawaited(ref.read(alertsSchedulerProvider).syncAll(
        lists.licences,
        credentials: lists.credentials,
      ));
    });

    return Scaffold(
      // Wrap the active tab in a per-route error boundary. If any tab
      // throws during build, we render a friendly fallback rather than
      // a red-screen and the user can navigate to a different tab to
      // recover. Errors are forwarded to Sentry verbatim.
      body: _ShellErrorBoundary(child: navigationShell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        backgroundColor: EqColours.white,
        indicatorColor: EqColours.surface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon:
                Icon(Icons.account_balance_wallet, color: EqColours.deep),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: EqColours.deep),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Per-tab error boundary. Wraps the active navigation branch so a build
/// failure in one tab doesn't take down the whole shell. The user can
/// navigate to a different tab to recover. Errors are reported to Sentry.
class _ShellErrorBoundary extends StatefulWidget {
  const _ShellErrorBoundary({required this.child});

  final Widget child;

  @override
  State<_ShellErrorBoundary> createState() => _ShellErrorBoundaryState();
}

class _ShellErrorBoundaryState extends State<_ShellErrorBoundary> {
  Object? _error;

  @override
  void didUpdateWidget(_ShellErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset error when the shell switches tabs — give every tab a fresh
    // chance to render.
    if (widget.child != oldWidget.child) _error = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _ErrorFallback(error: _error!);
    return _ErrorBoundaryChild(
      onError: (error, st) {
        unawaited(Sentry.captureException(error, stackTrace: st));
        if (mounted) setState(() => _error = error);
      },
      child: widget.child,
    );
  }
}

class _ErrorBoundaryChild extends StatelessWidget {
  const _ErrorBoundaryChild({required this.child, required this.onError});

  final Widget child;
  final void Function(Object, StackTrace) onError;

  @override
  Widget build(BuildContext context) {
    // Flutter doesn't have native React-style error boundaries — this
    // wraps the child in an ErrorWidget builder override so build-phase
    // errors render the fallback inline. Async errors still flow through
    // Zone-level handling in main.dart.
    final previous = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      onError(details.exception, details.stack ?? StackTrace.current);
      return _ErrorFallback(error: details.exception);
    };
    try {
      return child;
    } finally {
      // Restore so other parts of the tree (modals, dialogs) keep their
      // own error rendering behaviour.
      ErrorWidget.builder = previous;
    }
  }
}

class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EqSpacing.lg),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 56,
              color: EqColours.error,
            ),
            const SizedBox(height: EqSpacing.md),
            Text(
              'Something broke on this screen',
              style: EqTypography.headingM,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: EqSpacing.sm),
            Text(
              "We've reported the error. Try a different tab below, or "
              'pull-to-refresh after a moment.',
              style: EqTypography.bodyM.copyWith(color: EqColours.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

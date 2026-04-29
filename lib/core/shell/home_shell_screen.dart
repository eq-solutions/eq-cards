import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alerts/alerts.dart';
import '../../features/licences/licences.dart';
import '../theme/eq_colours.dart';

class HomeShellScreen extends ConsumerWidget {
  const HomeShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whenever the licence list resolves with new data, re-sync local
    // expiry alerts. Cross-feature wiring lives at the shell layer; the
    // licences feature itself stays unaware of the alerts feature.
    ref.listen(licencesListNotifierProvider, (_, next) {
      next.whenData((licences) {
        ref.read(alertsSchedulerProvider).syncAll(licences);
      });
    });

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        backgroundColor: EqColours.white,
        indicatorColor: EqColours.ice,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge, color: EqColours.deep),
            label: 'Licences',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: EqColours.deep),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: EqColours.deep),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

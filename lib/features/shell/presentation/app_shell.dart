import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ui/ui.dart';
import '../../../core/providers/core_providers.dart';
import '../../practice/application/practice_controller.dart';

/// The five-tab frame around the app.
///
/// Backed by a `StatefulShellRoute`, so each tab keeps its own navigation
/// stack and scroll position — switching to Saved and back must not reset the
/// feed to the first card.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Review items falling due is the only thing in the app that becomes true
    // while the user is elsewhere. Without the badge the count was discoverable
    // only by opening the tab and looking.
    final dueCount = ref.watch(dueForReviewCountProvider).value ?? 0;
    final hapticsEnabled = ref.watch(
      userPreferencesProvider.select((p) => p.hapticsEnabled),
    );

    // Icons are the rounded set throughout, matching the geometry of every
    // other surface. The bar previously mixed `_outlined`, `_rounded` and bare
    // variants inside a single row.
    final destinations = <AppNavDestination>[
      const AppNavDestination(
        icon: Icons.bolt_outlined,
        selectedIcon: Icons.bolt_rounded,
        label: 'Home',
      ),
      const AppNavDestination(
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view_rounded,
        label: 'Explore',
      ),
      AppNavDestination(
        icon: Icons.fitness_center_outlined,
        selectedIcon: Icons.fitness_center_rounded,
        label: 'Practice',
        badgeCount: dueCount,
      ),
      const AppNavDestination(
        icon: Icons.bookmark_border_rounded,
        selectedIcon: Icons.bookmark_rounded,
        label: 'Saved',
      ),
      const AppNavDestination(
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
        label: 'Profile',
      ),
    ];

    return PopScope(
      // Android back on a non-home tab returns to Home rather than leaving the
      // app, which is what users expect from a bottom-nav app.
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: AppNavBar(
          currentIndex: navigationShell.currentIndex,
          destinations: destinations,
          hapticsEnabled: hapticsEnabled,
          onSelected: (index) => navigationShell.goBranch(
            index,
            // Tapping the active tab pops it back to its root.
            initialLocation: index == navigationShell.currentIndex,
          ),
        ),
      ),
    );
  }
}

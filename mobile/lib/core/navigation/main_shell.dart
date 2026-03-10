import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Top-level shell that hosts the two main app sections:
///   0 — Gym Timer   (fitness_center icon)
///   1 — Outdoor     (directions_run icon)
///
/// Each section maintains its own independent navigation stack via
/// [StatefulNavigationShell]. Full-screen routes such as /timer and /editor
/// are declared outside this shell in the router so they push on top of it
/// without showing the bottom navigation bar.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Re-tapping the active tab pops to the branch root (standard UX).
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Gym Timer',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_run_outlined),
            selectedIcon: Icon(Icons.directions_run),
            label: 'Outdoor',
          ),
        ],
      ),
    );
  }
}

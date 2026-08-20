import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'adaptive_shell.dart';

/// Layout below [kDesktopBreakpoint].
class MobileShell extends StatelessWidget {
  const MobileShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) =>
            goToBranch(navigationShell, index),
        destinations: kShellDestinations
            .map(
              (ShellDestination destination) => NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

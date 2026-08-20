import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'adaptive_shell.dart';

/// Layout at or above [kDesktopBreakpoint] — tablets and landscape phones.
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    required this.navigationShell,
    required this.extended,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  /// Labels next to the icons instead of below them.
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (int index) =>
                goToBranch(navigationShell, index),
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: kShellDestinations
                .map(
                  (ShellDestination destination) => NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
                )
                .toList(growable: false),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
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
    final List<String> labels = shellDestinationLabels(
      AppLocalizations.of(context)!,
    );
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
            destinations: <NavigationRailDestination>[
              for (int i = 0; i < kShellDestinations.length; i++)
                NavigationRailDestination(
                  icon: Icon(kShellDestinations[i].icon),
                  selectedIcon: Icon(kShellDestinations[i].selectedIcon),
                  label: Text(labels[i]),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

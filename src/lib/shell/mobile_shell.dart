import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import 'adaptive_shell.dart';

/// Layout below [kDesktopBreakpoint].
class MobileShell extends StatelessWidget {
  const MobileShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = shellDestinationLabels(
      AppLocalizations.of(context)!,
    );
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) =>
            goToBranch(navigationShell, index),
        destinations: <NavigationDestination>[
          for (int i = 0; i < kShellDestinations.length; i++)
            NavigationDestination(
              icon: Icon(kShellDestinations[i].icon),
              selectedIcon: Icon(kShellDestinations[i].selectedIcon),
              label: labels[i],
            ),
        ],
      ),
    );
  }
}

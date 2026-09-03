import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../features/disclaimer/disclaimer_screen.dart';
import '../l10n/app_localizations.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Below this width the app uses a bottom navigation bar, at or above it a
/// navigation rail. Relevant for tablets and landscape phones — v0.1 targets no
/// desktop platform.
const double kDesktopBreakpoint = 600;

/// Width above which the rail shows its labels.
const double kExtendedRailBreakpoint = 1200;

/// The four destinations, in branch order. The label is resolved at render
/// time from [shellDestinationLabels] — a `const` list cannot call
/// `AppLocalizations.of(context)`.
const List<ShellDestination> kShellDestinations = <ShellDestination>[
  ShellDestination(
    icon: Icons.qr_code_scanner_outlined,
    selectedIcon: Icons.qr_code_scanner,
  ),
  ShellDestination(
    icon: Icons.list_alt_outlined,
    selectedIcon: Icons.list_alt,
  ),
  ShellDestination(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
  ),
  ShellDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

class ShellDestination {
  const ShellDestination({required this.icon, required this.selectedIcon});

  final IconData icon;
  final IconData selectedIcon;
}

/// Labels for [kShellDestinations], in the same order.
List<String> shellDestinationLabels(AppLocalizations l10n) => <String>[
  l10n.shellScanLabel,
  l10n.shellAllergiesLabel,
  l10n.shellHistoryLabel,
  l10n.shellSettingsLabel,
];

/// Picks the layout by width, and gates the whole app behind the
/// not-a-medical-device disclaimer.
///
/// The disclaimer is a gate here rather than a route with a redirect: a
/// redirect would have to race the settings stream after acknowledgement, and
/// this way every tab and every deep link is covered by construction.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool acknowledged = ref
        .watch(currentSettingsProvider)
        .disclaimerAcknowledged;
    if (!acknowledged) {
      return const DisclaimerScreen();
    }

    final double width = MediaQuery.sizeOf(context).width;
    if (width >= kDesktopBreakpoint) {
      return DesktopShell(
        navigationShell: navigationShell,
        extended: width >= kExtendedRailBreakpoint,
      );
    }
    return MobileShell(navigationShell: navigationShell);
  }
}

/// Switching to an already-selected branch resets it to its root, which is what
/// tapping the current tab is expected to do.
void goToBranch(StatefulNavigationShell shell, int index) {
  shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

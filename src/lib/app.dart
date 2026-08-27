import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/utils/scan_capabilities.dart';
import 'features/allergies/allergies_screen.dart';
import 'features/allergies/group_edit_screen.dart';
import 'features/allergies/term_edit_screen.dart';
import 'features/history/history_screen.dart';
import 'features/result/product_edit_screen.dart';
import 'features/result/scan_details_edit_screen.dart';
import 'features/result/scan_result_screen.dart';
import 'features/scan/barcode_scan_screen.dart';
import 'features/scan/manual_entry_screen.dart';
import 'features/scan/scan_actions.dart';
import 'features/scan/scan_screen.dart';
import 'features/scan/text_capture_screen.dart';
import 'features/scan/text_review_screen.dart';
import 'features/settings/about_screen.dart';
import 'features/settings/backup_screen.dart';
import 'features/settings/logs_screen.dart';
import 'features/settings/privacy_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/sync_screen.dart';
import 'shell/adaptive_shell.dart';

/// Material 3 with an indigo seed, light and dark, driven by the settings row.
const Color kSeedColor = Colors.indigo;

/// The router is built once per capability set, so a camera route is not even
/// registered where the platform cannot serve it (R3.1, R3.2).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final ScanCapabilities capabilities = ref.watch(scanCapabilitiesProvider);

  return GoRouter(
    initialLocation: '/scan',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) => AdaptiveShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/scan',
                builder: (_, _) => const ScanScreen(),
                routes: <RouteBase>[
                  if (capabilities.canScanBarcode)
                    GoRoute(
                      path: 'barcode',
                      builder: (_, _) => const BarcodeScanScreen(),
                    ),
                  if (capabilities.canRecognizeText)
                    GoRoute(
                      path: 'text',
                      builder: (_, _) => const TextCaptureScreen(),
                    ),
                  GoRoute(
                    path: 'review',
                    builder: (BuildContext context, GoRouterState state) =>
                        TextReviewScreen(
                          initialText: state.extra as String? ?? '',
                        ),
                  ),
                  GoRoute(
                    path: 'manual',
                    builder: (_, _) => const ManualEntryScreen(),
                  ),
                  GoRoute(
                    path: 'result/:scanId',
                    builder: (BuildContext context, GoRouterState state) =>
                        ScanResultScreen(
                          scanId: state.pathParameters['scanId']!,
                          lookupProblem: state.extra as ScanLookupProblem?,
                        ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'product',
                        builder: (BuildContext context, GoRouterState state) =>
                            ProductEditScreen(
                              scanId: state.pathParameters['scanId']!,
                              barcode: state.extra as String? ?? '',
                            ),
                      ),
                      GoRoute(
                        path: 'details',
                        builder: (BuildContext context, GoRouterState state) =>
                            ScanDetailsEditScreen(
                              scanId: state.pathParameters['scanId']!,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/allergies',
                builder: (_, _) => const AllergiesScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'add',
                    builder: (_, _) => const TermEditScreen(),
                  ),
                  GoRoute(
                    path: ':termId/edit',
                    builder: (BuildContext context, GoRouterState state) =>
                        TermEditScreen(
                          termId: state.pathParameters['termId'],
                        ),
                  ),
                  GoRoute(
                    path: 'groups/add',
                    builder: (_, _) => const GroupEditScreen(),
                  ),
                  GoRoute(
                    path: 'groups/:groupId/edit',
                    builder: (BuildContext context, GoRouterState state) =>
                        GroupEditScreen(
                          groupId: state.pathParameters['groupId'],
                        ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/history',
                builder: (_, _) => const HistoryScreen(),
                routes: <RouteBase>[
                  // Same widget as a fresh result, on purpose — a stored record
                  // must look identical to what the user saw.
                  GoRoute(
                    path: ':scanId',
                    builder: (BuildContext context, GoRouterState state) =>
                        ScanResultScreen(
                          scanId: state.pathParameters['scanId']!,
                        ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'backup',
                    builder: (_, _) => const BackupScreen(),
                  ),
                  GoRoute(path: 'sync', builder: (_, _) => const SyncScreen()),
                  GoRoute(
                    path: 'about',
                    builder: (_, _) => const AboutScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    builder: (_, _) => const PrivacyScreen(),
                  ),
                  GoRoute(path: 'logs', builder: (_, _) => const LogsScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class AllergyScannerApp extends ConsumerWidget {
  const AllergyScannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'AllergyScanner',
      theme: _themeFor(Brightness.light),
      darkTheme: _themeFor(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }

  static ThemeData _themeFor(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kSeedColor,
        brightness: brightness,
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/scan.dart';
import '../../core/providers.dart';
import 'scan_actions.dart';

/// The three newest scans, shown on the Scan tab.
final StreamProvider<List<Scan>> recentScansProvider =
    StreamProvider<List<Scan>>(
      (ref) => ref.watch(scanDaoProvider).watchRecent(limit: 3),
    );

final Provider<ScanActions> scanActionsProvider = Provider<ScanActions>((ref) {
  return ScanActions(
    allergenTermDao: ref.watch(allergenTermDaoProvider),
    productDao: ref.watch(productDaoProvider),
    scanDao: ref.watch(scanDaoProvider),
    settingsDao: ref.watch(settingsDaoProvider),
    openFoodFacts: ref.watch(openFoodFactsServiceProvider),
    log: ref.watch(logServiceProvider),
    scanPhotos: ref.watch(scanPhotoServiceProvider),
  );
});

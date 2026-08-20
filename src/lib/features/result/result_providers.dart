import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/daos/product_dao.dart';
import '../../core/models/enums.dart';
import '../../core/models/product.dart';
import '../../core/models/scan.dart';
import '../../core/providers.dart';
import '../scan/scan_actions.dart';
import '../scan/scan_providers.dart';

/// One stream per scan — the same provider serves the fresh result and the
/// history entry, because it is the same widget (doc/ARCHITECTURE.md §5.11).
final StreamProviderFamily<ScanResult?, String> scanResultProvider =
    StreamProvider.family<ScanResult?, String>(
      (ref, String scanId) => ref.watch(scanDaoProvider).watchResult(scanId),
    );

final StreamProviderFamily<Product?, String> productProvider =
    StreamProvider.family<Product?, String>(
      (ref, String barcode) =>
          ref.watch(productDaoProvider).watchByBarcode(barcode),
    );

final Provider<ProductActions> productActionsProvider =
    Provider<ProductActions>((ref) {
      return ProductActions(
        productDao: ref.watch(productDaoProvider),
        scanActions: ref.watch(scanActionsProvider),
      );
    });

/// Write side for a locally corrected product.
class ProductActions {
  ProductActions({
    required ProductDao productDao,
    required ScanActions scanActions,
    DateTime Function()? now,
  }) : _productDao = productDao,
       _scanActions = scanActions,
       _now = now ?? DateTime.now;

  final ProductDao _productDao;
  final ScanActions _scanActions;
  final DateTime Function() _now;

  /// Saves the user's correction and re-runs the check for [scanId], so the
  /// result the user is looking at updates immediately.
  Future<void> saveCorrection({
    required String scanId,
    required String barcode,
    required Product? existing,
    String? productName,
    String? brands,
    String? quantity,
    String? ingredientsText,
  }) async {
    await _productDao.saveManualOverride(
      Product(
        barcode: barcode,
        productName: productName,
        brands: brands,
        quantity: quantity,
        ingredientsText: ingredientsText,
        ingredientsLanguage: existing?.ingredientsLanguage,
        imageUrl: existing?.imageUrl,
        allergensTags: existing?.allergensTags ?? const <String>[],
        tracesTags: existing?.tracesTags ?? const <String>[],
        // Provenance stays visible: source is unchanged, the override flag is
        // what marks the row as corrected (R4.6).
        source: existing?.source ?? ProductSource.manual,
        hasManualOverride: true,
        fetchedAt: existing?.fetchedAt,
        updatedAt: _now(),
      ),
    );
    await _scanActions.reevaluate(scanId);
  }
}

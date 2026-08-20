import 'package:drift/drift.dart';

import '../../models/product.dart';
import '../app_database.dart';
import '../tables/products_table.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.attachedDatabase);

  Stream<Product?> watchByBarcode(String barcode) {
    return (select(products)..where((t) => t.barcode.equals(barcode)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : toModel(row));
  }

  Future<Product?> findByBarcode(String barcode) async {
    final row = await (select(
      products,
    )..where((t) => t.barcode.equals(barcode))).getSingleOrNull();
    return row == null ? null : toModel(row);
  }

  /// Writes remote data, but never over a row the user corrected (R4.4).
  /// Returns false when the write was skipped for that reason.
  Future<bool> upsertFromRemote(Product product) async {
    final existing = await findByBarcode(product.barcode);
    if (existing != null && existing.hasManualOverride) return false;

    await into(products).insertOnConflictUpdate(
      _toCompanion(product, hasManualOverride: false),
    );
    return true;
  }

  /// The user's correction wins from now on.
  Future<void> saveManualOverride(Product product) {
    return into(products).insertOnConflictUpdate(
      _toCompanion(product, hasManualOverride: true),
    );
  }

  Future<void> deleteByBarcode(String barcode) {
    return (delete(products)..where((t) => t.barcode.equals(barcode))).go();
  }

  Future<List<Product>> getAll() async {
    final rows = await select(products).get();
    return rows.map(toModel).toList(growable: false);
  }

  ProductsCompanion _toCompanion(
    Product product, {
    required bool hasManualOverride,
  }) {
    return ProductsCompanion(
      barcode: Value(product.barcode),
      productName: Value(product.productName),
      brands: Value(product.brands),
      quantity: Value(product.quantity),
      ingredientsText: Value(product.ingredientsText),
      ingredientsLanguage: Value(product.ingredientsLanguage),
      allergensTags: Value(_joinTags(product.allergensTags)),
      tracesTags: Value(_joinTags(product.tracesTags)),
      imageUrl: Value(product.imageUrl),
      source: Value(product.source),
      hasManualOverride: Value(hasManualOverride),
      fetchedAt: Value(product.fetchedAt),
      updatedAt: Value(product.updatedAt),
    );
  }

  static String? _joinTags(List<String> tags) =>
      tags.isEmpty ? null : tags.join('\n');

  static List<String> _splitTags(String? value) {
    if (value == null || value.isEmpty) return const [];
    return value
        .split('\n')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  /// Also used by the backup service, which reads rows directly.
  static Product toModel(ProductRow row) {
    return Product(
      barcode: row.barcode,
      productName: row.productName,
      brands: row.brands,
      quantity: row.quantity,
      ingredientsText: row.ingredientsText,
      ingredientsLanguage: row.ingredientsLanguage,
      imageUrl: row.imageUrl,
      allergensTags: _splitTags(row.allergensTags),
      tracesTags: _splitTags(row.tracesTags),
      source: row.source,
      hasManualOverride: row.hasManualOverride,
      fetchedAt: row.fetchedAt,
      updatedAt: row.updatedAt,
    );
  }
}

import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:allergy_scanner/core/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = openTestDatabase());
  tearDown(() => database.close());

  test('stores and reads a product including its tag lists', () async {
    await database.productDao.upsertFromRemote(
      buildProduct(barcode: '4001234567890'),
    );

    final Product? found = await database.productDao.findByBarcode(
      '4001234567890',
    );
    expect(found, isNotNull);
    expect(found!.productName, 'Choco Bar');
    expect(found.allergensTags, <String>['en:nuts', 'en:milk']);
    expect(found.tracesTags, <String>['en:gluten']);
    expect(found.hasManualOverride, isFalse);
  });

  test('a remote fetch overwrites a row that was not corrected', () async {
    await database.productDao.upsertFromRemote(
      buildProduct(barcode: '1', productName: 'Old name'),
    );

    final bool written = await database.productDao.upsertFromRemote(
      buildProduct(barcode: '1', productName: 'New name'),
    );

    expect(written, isTrue);
    expect(
      (await database.productDao.findByBarcode('1'))!.productName,
      'New name',
    );
  });

  test('a remote fetch never overwrites a manual override', () async {
    await database.productDao.saveManualOverride(
      buildProduct(
        barcode: '1',
        productName: 'What the pack says',
        ingredientsText: 'hazelnuts',
      ),
    );

    final bool written = await database.productDao.upsertFromRemote(
      buildProduct(barcode: '1', productName: 'Crowd-sourced name'),
    );

    expect(written, isFalse);
    final Product kept = (await database.productDao.findByBarcode('1'))!;
    expect(kept.productName, 'What the pack says');
    expect(kept.hasManualOverride, isTrue);
  });

  test('saveManualOverride keeps the original source for provenance', () async {
    await database.productDao.upsertFromRemote(
      buildProduct(barcode: '1', source: ProductSource.openFoodFacts),
    );
    final Product remote = (await database.productDao.findByBarcode('1'))!;

    await database.productDao.saveManualOverride(
      remote.copyWith(productName: 'Corrected', hasManualOverride: true),
    );

    final Product corrected = (await database.productDao.findByBarcode('1'))!;
    expect(corrected.source, ProductSource.openFoodFacts);
    expect(corrected.hasManualOverride, isTrue);
  });

  test('a corrected product is never stale, a remote one expires', () async {
    final DateTime fetched = DateTime.utc(2026, 1, 1);
    final DateTime muchLater = DateTime.utc(2026, 6, 1);

    final Product remote = buildProduct(barcode: '1', fetchedAt: fetched);
    expect(remote.isStale(muchLater), isTrue);

    final Product corrected = remote.copyWith(hasManualOverride: true);
    expect(corrected.isStale(muchLater), isFalse);
  });

  test('watchByBarcode emits null for an unknown barcode', () async {
    expect(await database.productDao.watchByBarcode('nope').first, isNull);
  });
}

import 'dart:io';

import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:allergy_scanner/core/models/scan_input.dart';
import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:allergy_scanner/core/services/open_food_facts_service.dart';
import 'package:allergy_scanner/core/services/scan_photo_service.dart';
import 'package:allergy_scanner/features/scan/scan_actions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

import '../database/test_database.dart';

/// Regression coverage for the critical bug found while adding name/shop/
/// photo to history: `reevaluate` (used after a product correction) must
/// carry those fields forward, since `insertWithMatches`'s
/// `insertOnConflictUpdate` overwrites every column it is given a value
/// for. Without this, correcting a product on a scan that already has
/// details set would silently wipe them.
void main() {
  late AppDatabase database;
  late LogService log;
  late Directory photosDir;
  late ScanActions scanActions;

  setUp(() {
    database = openTestDatabase();
    log = LogService(
      File(path_helper.join(Directory.systemTemp.path, 'scan_actions_test.log')),
    );
    photosDir = Directory.systemTemp.createTempSync(
      'allergy_scanner_scan_actions_test_photos_',
    );
    scanActions = ScanActions(
      allergenTermDao: database.allergenTermDao,
      productDao: database.productDao,
      scanDao: database.scanDao,
      settingsDao: database.settingsDao,
      // reevaluate() never calls this for a text scan or when the barcode's
      // product is already cached — unreachable on purpose, so the test
      // fails loudly if that assumption ever stops holding.
      openFoodFacts: OpenFoodFactsService(
        dio: Dio(),
        log: log,
        baseUrl: 'http://127.0.0.1:1',
      ),
      log: log,
      scanPhotos: ScanPhotoService(photosDir, log: log),
      now: () => testTimestamp,
    );
  });

  tearDown(() {
    database.close();
    if (photosDir.existsSync()) photosDir.deleteSync(recursive: true);
  });

  test(
    'reevaluate carries name/shop/photoPath forward for a text scan',
    () async {
      await database.scanDao.insertWithMatches(
        scan: buildScan(
          id: 's1',
          name: 'My chocolate',
          shop: 'Migros',
          photoPath: 'scan_photos/s1.jpg',
        ),
        matches: const <ScanMatch>[],
      );

      await scanActions.reevaluate('s1');

      final ScanResult result = (await database.scanDao.findResult('s1'))!;
      expect(result.scan.name, 'My chocolate');
      expect(result.scan.shop, 'Migros');
      expect(result.scan.photoPath, 'scan_photos/s1.jpg');
    },
  );

  test('reevaluate leaves a scan with no details set as null', () async {
    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1'),
      matches: const <ScanMatch>[],
    );

    await scanActions.reevaluate('s1');

    final ScanResult result = (await database.scanDao.findResult('s1'))!;
    expect(result.scan.name, isNull);
    expect(result.scan.shop, isNull);
    expect(result.scan.photoPath, isNull);
  });

  test('evaluate (a brand-new scan) starts with no details', () async {
    final ScanOutcome outcome = await scanActions.evaluate(
      const TextInput(text: 'sugar, milk', mode: ScanInputMode.manualText),
    );

    final ScanResult result = (await database.scanDao.findResult(
      outcome.scanId,
    ))!;
    expect(result.scan.name, isNull);
    expect(result.scan.shop, isNull);
    expect(result.scan.photoPath, isNull);
  });
}

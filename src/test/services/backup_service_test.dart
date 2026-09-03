import 'dart:convert';
import 'dart:io';

import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:allergy_scanner/core/models/app_settings.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:allergy_scanner/core/services/backup_service.dart';
import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:allergy_scanner/core/services/scan_photo_service.dart';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

import '../database/test_database.dart';

void main() {
  late AppDatabase source;
  late LogService log;
  late Directory photosDir;
  late ScanPhotoService scanPhotos;

  setUp(() {
    source = openTestDatabase();
    log = LogService(
      File(
        path_helper.join(
          Directory.systemTemp.path,
          'allergy_scanner_backup_test.log',
        ),
      ),
    );
    photosDir = Directory.systemTemp.createTempSync(
      'allergy_scanner_backup_test_photos_',
    );
    scanPhotos = ScanPhotoService(photosDir, log: log);
  });

  tearDown(() {
    source.close();
    if (photosDir.existsSync()) photosDir.deleteSync(recursive: true);
  });

  BackupService serviceFor(AppDatabase database) => BackupService(
    database: database,
    log: log,
    scanPhotos: scanPhotos,
    now: () => testTimestamp,
  );

  Future<void> seed(AppDatabase database) async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 'term-1', term: 'Hazelnut', normalizedTerm: 'hazelnut'),
    );
    await database.productDao.upsertFromRemote(buildProduct(barcode: 'bc-1'));
    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1', barcode: 'bc-1'),
      matches: <ScanMatch>[
        buildMatch(id: 'm1', scanId: 's1', allergenTermId: 'term-1'),
      ],
    );
    await database.settingsDao.setAppLanguage('de');
    await database.settingsDao.setPreferredLanguage('de');
    await database.settingsDao.setWebdav(
      baseUrl: 'https://cloud.example.org/dav/',
      username: 'me',
    );
  }

  test('the archive contains a manifest and the data file', () async {
    await seed(source);
    final List<int> bytes = await serviceFor(source).exportToBytes();

    final Archive archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.find('data.json'), isNotNull);
    expect(archive.find('manifest.json'), isNotNull);

    final Map<String, Object?> manifest =
        jsonDecode(utf8.decode(archive.find('manifest.json')!.readBytes()!))
            as Map<String, Object?>;
    expect(manifest['app'], 'AllergyScanner');
    expect(manifest['schemaVersion'], source.schemaVersion);
  });

  test('no credential ends up in the archive', () async {
    await seed(source);
    final List<int> bytes = await serviceFor(source).exportToBytes();

    // The WebDAV password lives in the key store; an archive that carried it
    // would leak it into every share target (R4.9, R8.1).
    final String content = utf8.decode(
      ZipDecoder().decodeBytes(bytes).find('data.json')!.readBytes()!,
    );
    expect(content.toLowerCase(), isNot(contains('password')));
    expect(content, contains('webdavUsername'));
  });

  test('a round trip restores terms, products, scans and matches', () async {
    await seed(source);
    final List<int> bytes = await serviceFor(source).exportToBytes();

    final AppDatabase target = openTestDatabase();
    addTearDown(target.close);

    final ImportOutcome outcome = await serviceFor(
      target,
    ).importFromBytes(bytes);

    expect(outcome.skipped, 0);
    expect(outcome.imported, greaterThan(0));

    final AllergenTerm? term = await target.allergenTermDao.findById('term-1');
    expect(term?.term, 'Hazelnut');
    expect(term?.normalizedTerm, 'hazelnut');

    expect(
      (await target.productDao.findByBarcode('bc-1'))?.productName,
      'Choco Bar',
    );

    final ScanResult result = (await target.scanDao.findResult('s1'))!;
    expect(result.scan.evaluatedText, isNotEmpty);
    expect(result.matches.single.termSnapshot, 'hazelnut');
    expect(result.matches.single.allergenTermId, 'term-1');

    final AppSettings settings = await target.settingsDao.get();
    expect(settings.appLanguage, 'de');
    expect(settings.preferredIngredientsLanguage, 'de');
    expect(settings.webdavUsername, 'me');
  });

  test('a match whose scan is missing is skipped and counted', () async {
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': source.schemaVersion,
      'allergenTerms': const <Object?>[],
      'products': const <Object?>[],
      'scans': const <Object?>[],
      'scanMatches': <Object?>[
        <String, Object?>{
          'id': 'm1',
          'scanId': 'does-not-exist',
          'termSnapshot': 'hazelnut',
          'matchedText': 'hazelnut',
          'startOffset': 0,
          'endOffset': 8,
        },
      ],
    };

    final ImportOutcome outcome = await serviceFor(
      source,
    ).importFromBytes(_zip(payload));

    expect(outcome.imported, 0);
    expect(outcome.skipped, 1);
    expect(outcome.hasSkipped, isTrue);
  });

  test('a scan referencing an absent product keeps its snapshot', () async {
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': source.schemaVersion,
      'allergenTerms': const <Object?>[],
      'products': const <Object?>[],
      'scans': <Object?>[
        <String, Object?>{
          'id': 's9',
          'scannedAt': testTimestamp.toIso8601String(),
          'inputMode': 'barcode',
          'barcode': 'not-in-archive',
          'productNameSnapshot': 'Choco Bar',
          'evaluatedText': 'sugar, hazelnuts',
          'verdict': 'hit',
          'matchCount': 1,
        },
      ],
      'scanMatches': const <Object?>[],
    };

    final ImportOutcome outcome = await serviceFor(
      source,
    ).importFromBytes(_zip(payload));

    expect(outcome.skipped, 0);
    final ScanResult result = (await source.scanDao.findResult('s9'))!;
    // The dangling foreign key is dropped instead of failing the import.
    expect(result.scan.barcode, isNull);
    expect(result.scan.productNameSnapshot, 'Choco Bar');
  });

  test('export includes a photo entry only for scans that have one', () async {
    await seed(source);
    final File sourcePhoto = File(
      path_helper.join(Directory.systemTemp.path, 'probe_photo.jpg'),
    )..writeAsBytesSync(<int>[1, 2, 3, 4]);
    addTearDown(() => sourcePhoto.deleteSync());
    final String photoPath = await scanPhotos.attach(
      scanId: 's1',
      sourcePath: sourcePhoto.path,
    );
    await source.scanDao.updateDetails(
      scanId: 's1',
      photoPath: Value(photoPath),
    );

    final List<int> bytes = await serviceFor(source).exportToBytes();
    final Archive archive = ZipDecoder().decodeBytes(bytes);

    expect(archive.find(photoPath), isNotNull);
    expect(
      archive.files.where((ArchiveFile f) => f.name.startsWith('scan_photos/')),
      hasLength(1),
    );
  });

  test('a round trip restores an attached photo\'s bytes', () async {
    await seed(source);
    final File sourcePhoto = File(
      path_helper.join(Directory.systemTemp.path, 'probe_photo2.jpg'),
    )..writeAsBytesSync(<int>[9, 8, 7, 6, 5]);
    addTearDown(() => sourcePhoto.deleteSync());
    final String photoPath = await scanPhotos.attach(
      scanId: 's1',
      sourcePath: sourcePhoto.path,
    );
    await source.scanDao.updateDetails(
      scanId: 's1',
      photoPath: Value(photoPath),
    );

    final List<int> bytes = await serviceFor(source).exportToBytes();

    final AppDatabase target = openTestDatabase();
    addTearDown(target.close);
    final Directory targetPhotosDir = Directory.systemTemp.createTempSync(
      'allergy_scanner_backup_test_target_photos_',
    );
    addTearDown(() => targetPhotosDir.deleteSync(recursive: true));
    final ScanPhotoService targetScanPhotos = ScanPhotoService(
      targetPhotosDir,
      log: log,
    );
    final BackupService targetService = BackupService(
      database: target,
      log: log,
      scanPhotos: targetScanPhotos,
      now: () => testTimestamp,
    );

    await targetService.importFromBytes(bytes);

    final ScanResult result = (await target.scanDao.findResult('s1'))!;
    expect(result.scan.photoPath, photoPath);
    final File restored = await targetScanPhotos.resolve(photoPath);
    expect(await restored.readAsBytes(), <int>[9, 8, 7, 6, 5]);
  });

  test('a v1-shaped archive (no name/shop/photoPath, no photos) still imports', () async {
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': source.schemaVersion,
      'allergenTerms': const <Object?>[],
      'products': const <Object?>[],
      'scans': <Object?>[
        <String, Object?>{
          'id': 's9',
          'scannedAt': testTimestamp.toIso8601String(),
          'inputMode': 'barcode',
          'evaluatedText': 'sugar, hazelnuts',
          'verdict': 'hit',
          'matchCount': 1,
          // No 'name', 'shop' or 'photoPath' keys — exactly what a v1
          // archive, written before those fields existed, looks like.
        },
      ],
      'scanMatches': const <Object?>[],
    };
    final Archive archive = Archive()
      ..add(ArchiveFile.string('data.json', jsonEncode(payload)))
      ..add(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode(<String, Object?>{'backupFormatVersion': 1}),
        ),
      );

    final ImportOutcome outcome = await serviceFor(
      source,
    ).importFromBytes(ZipEncoder().encode(archive));

    expect(outcome.skipped, 0);
    final ScanResult result = (await source.scanDao.findResult('s9'))!;
    expect(result.scan.name, isNull);
    expect(result.scan.shop, isNull);
    expect(result.scan.photoPath, isNull);
  });

  test('an archive from a newer backup format is refused', () async {
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': source.schemaVersion,
      'allergenTerms': const <Object?>[],
    };
    final Archive archive = Archive()
      ..add(ArchiveFile.string('data.json', jsonEncode(payload)))
      ..add(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode(<String, Object?>{
            'backupFormatVersion': BackupService.backupFormatVersion + 1,
          }),
        ),
      );

    await expectLater(
      serviceFor(source).importFromBytes(ZipEncoder().encode(archive)),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('an archive from a newer schema is refused', () async {
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': source.schemaVersion + 1,
      'allergenTerms': const <Object?>[],
    };

    await expectLater(
      serviceFor(source).importFromBytes(_zip(payload)),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('a file that is not an archive is refused', () async {
    await expectLater(
      serviceFor(source).importFromBytes(utf8.encode('not a zip')),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('an archive without data.json is refused', () async {
    final Archive archive = Archive()
      ..add(ArchiveFile.string('manifest.json', '{}'));

    await expectLater(
      serviceFor(source).importFromBytes(ZipEncoder().encode(archive)),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('the archive name carries a sortable timestamp', () {
    final String name = BackupService.archiveFileName(
      DateTime.utc(2026, 8, 20, 14, 2, 3),
    );
    expect(name, startsWith('allergy_scanner_'));
    expect(name, endsWith('.zip'));
    expect(RegExp(r'allergy_scanner_\d{8}_\d{6}\.zip').hasMatch(name), isTrue);
  });
}

List<int> _zip(Map<String, Object?> payload) {
  final Archive archive = Archive()
    ..add(ArchiveFile.string('data.json', jsonEncode(payload)));
  return ZipEncoder().encode(archive);
}

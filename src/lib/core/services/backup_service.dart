import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as path_helper;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../database/app_database.dart';
import '../models/enums.dart';
import '../utils/formatters.dart';
import 'log_service.dart';
import 'scan_photo_service.dart';

/// What an import did. [skipped] counts rows that could not be attached — the
/// caller must surface it when it is greater than zero (R8.2).
class ImportOutcome {
  const ImportOutcome({required this.imported, required this.skipped});

  final int imported;
  final int skipped;

  bool get hasSkipped => skipped > 0;
}

/// Raised when an archive cannot be used. The message is user-facing.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Local ZIP export and import of everything the app stores.
///
/// The archive deliberately contains no credential: the WebDAV password lives
/// in the platform key store and is never serialised (R4.9, R8.1).
class BackupService {
  BackupService({
    required AppDatabase database,
    required LogService log,
    required ScanPhotoService scanPhotos,
    DateTime Function()? now,
  }) : _database = database,
       _log = log,
       _scanPhotos = scanPhotos,
       _now = now ?? DateTime.now;

  /// Version of the archive layout itself, independent of the schema
  /// version. v2 adds `name`/`shop`/`photoPath` to each scan row plus one
  /// archive entry per attached photo.
  static const int backupFormatVersion = 2;

  static const String _dataEntry = 'data.json';
  static const String _manifestEntry = 'manifest.json';

  final AppDatabase _database;
  final LogService _log;
  final ScanPhotoService _scanPhotos;
  final DateTime Function() _now;

  /// Builds the archive in memory.
  ///
  /// Separate from [exportToFile] so it can be tested without `path_provider`
  /// and so the WebDAV upload can reuse the exact same bytes.
  Future<List<int>> exportToBytes() async {
    final Map<String, Object?> payload = await _readAll();

    final Archive archive = Archive()
      ..add(ArchiveFile.string(_dataEntry, jsonEncode(payload)))
      ..add(
        ArchiveFile.string(
          _manifestEntry,
          jsonEncode(<String, Object?>{
            'app': 'AllergyScanner',
            'backupFormatVersion': backupFormatVersion,
            'schemaVersion': _database.schemaVersion,
            'exportedAt': _now().toUtc().toIso8601String(),
          }),
        ),
      );

    // One archive entry per attached photo, named by its own photoPath so
    // import can restore it to the exact same relative location — raw
    // bytes, not base64-in-JSON, to avoid ~33% bloat plus JSON-escaping
    // overhead on binary data.
    final List<Map<String, Object?>> scanRows =
        (payload['scans'] as List).cast<Map<String, Object?>>();
    for (final Map<String, Object?> row in scanRows) {
      final String? photoPath = row['photoPath'] as String?;
      if (photoPath == null) continue;
      final File file = await _scanPhotos.resolve(photoPath);
      if (!await file.exists()) continue;
      archive.add(ArchiveFile.bytes(photoPath, await file.readAsBytes()));
    }

    return ZipEncoder().encode(archive);
  }

  /// Writes the archive into the app documents directory and returns it.
  Future<File> exportToFile() async {
    final List<int> bytes = await exportToBytes();
    final Directory directory = await getApplicationDocumentsDirectory();
    final String name = archiveFileName(_now());
    final File target = File(path_helper.join(directory.path, name));
    await target.writeAsBytes(bytes, flush: true);

    _log.info('Exported backup $name (${bytes.length} bytes)');
    return target;
  }

  /// `allergy_scanner_YYYYMMDD_HHmmss.zip` — sortable, which is how the newest
  /// remote backup is found (R8.1).
  static String archiveFileName(DateTime at) =>
      '$kBackupFilePrefix${Formatters.fileTimestamp(at)}.zip';

  Future<ImportOutcome> importFromFile(File file) async {
    return importFromBytes(await file.readAsBytes());
  }

  /// Replaces the current content in one transaction.
  ///
  /// Throws [BackupFormatException] for an unusable archive; a partially
  /// applied import is impossible because everything runs inside the
  /// transaction.
  Future<ImportOutcome> importFromBytes(List<int> bytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (cause) {
      _log.warn('Backup import failed to decode: $cause');
      throw const BackupFormatException('This file is not a readable archive.');
    }

    final ArchiveFile? dataFile = archive.find(_dataEntry);
    if (dataFile == null) {
      throw const BackupFormatException(
        'The archive does not contain $_dataEntry.',
      );
    }

    final Map<String, Object?> payload;
    try {
      payload =
          jsonDecode(utf8.decode(dataFile.readBytes() ?? const <int>[]))
              as Map<String, Object?>;
    } on Object catch (cause) {
      _log.warn('Backup import failed to parse: $cause');
      throw const BackupFormatException('The archive content is not valid.');
    }

    final int archiveSchemaVersion = _asInt(payload['schemaVersion']) ?? 0;
    if (archiveSchemaVersion > _database.schemaVersion) {
      throw BackupFormatException(
        'This backup was written by a newer version of the app '
        '(schema $archiveSchemaVersion, this app supports '
        '${_database.schemaVersion}).',
      );
    }

    // Absent in a v1 archive (before this field existed), which is fine — a
    // pre-v2 backup never claims a version newer than this app supports.
    final ArchiveFile? manifestFile = archive.find(_manifestEntry);
    final int archiveBackupFormatVersion = manifestFile == null
        ? 1
        : _asInt(_tryDecodeManifest(manifestFile)?['backupFormatVersion']) ??
              1;
    if (archiveBackupFormatVersion > backupFormatVersion) {
      throw BackupFormatException(
        'This backup was written by a newer version of the app '
        '(archive format $archiveBackupFormatVersion, this app supports '
        '$backupFormatVersion).',
      );
    }

    final ImportOutcome outcome = await _applyPayload(payload);

    // A v1 archive has no photos/ entries, so this is a no-op for it.
    for (final ArchiveFile entry in archive.files) {
      if (!entry.name.startsWith('${ScanPhotoService.subdirectoryName}/')) {
        continue;
      }
      final List<int>? bytes = entry.readBytes();
      if (bytes == null) continue;
      await _scanPhotos.restoreFromBytes(photoPath: entry.name, bytes: bytes);
    }

    return outcome;
  }

  static Map<String, Object?>? _tryDecodeManifest(ArchiveFile manifestFile) {
    try {
      return jsonDecode(utf8.decode(manifestFile.readBytes() ?? const <int>[]))
          as Map<String, Object?>;
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>> _readAll() {
    // One transaction, so an export cannot capture a half-written scan.
    return _database.transaction(() async {
      final terms = await _database.select(_database.allergenTerms).get();
      final products = await _database.select(_database.products).get();
      final scans = await _database.select(_database.scans).get();
      final matches = await _database.select(_database.scanMatches).get();
      final settings = await _database.settingsDao.get();

      return <String, Object?>{
        'schemaVersion': _database.schemaVersion,
        'allergenTerms': terms
            .map(
              (row) => <String, Object?>{
                'id': row.id,
                'term': row.term,
                'normalizedTerm': row.normalizedTerm,
                'isActive': row.isActive,
                'note': row.note,
                'createdAt': row.createdAt.toUtc().toIso8601String(),
                'updatedAt': row.updatedAt.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
        'products': products
            .map(
              (row) => <String, Object?>{
                'barcode': row.barcode,
                'productName': row.productName,
                'brands': row.brands,
                'quantity': row.quantity,
                'ingredientsText': row.ingredientsText,
                'ingredientsLanguage': row.ingredientsLanguage,
                'allergensTags': row.allergensTags,
                'tracesTags': row.tracesTags,
                'imageUrl': row.imageUrl,
                'source': row.source.name,
                'hasManualOverride': row.hasManualOverride,
                'fetchedAt': row.fetchedAt?.toUtc().toIso8601String(),
                'updatedAt': row.updatedAt.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
        'scans': scans
            .map(
              (row) => <String, Object?>{
                'id': row.id,
                'scannedAt': row.scannedAt.toUtc().toIso8601String(),
                'inputMode': row.inputMode.name,
                'barcode': row.barcode,
                'productNameSnapshot': row.productNameSnapshot,
                'evaluatedText': row.evaluatedText,
                'verdict': row.verdict.name,
                'matchCount': row.matchCount,
                'name': row.name,
                'shop': row.shop,
                'photoPath': row.photoPath,
              },
            )
            .toList(growable: false),
        'scanMatches': matches
            .map(
              (row) => <String, Object?>{
                'id': row.id,
                'scanId': row.scanId,
                'allergenTermId': row.allergenTermId,
                'termSnapshot': row.termSnapshot,
                'matchedText': row.matchedText,
                'startOffset': row.startOffset,
                'endOffset': row.endOffset,
              },
            )
            .toList(growable: false),
        // Settings without any secret: the password stays in the key store.
        'settings': <String, Object?>{
          'themeMode': settings.themeMode.name,
          'preferredIngredientsLanguage':
              settings.preferredIngredientsLanguage,
          'remoteLookupEnabled': settings.remoteLookupEnabled,
          'disclaimerAcknowledgedAt': settings.disclaimerAcknowledgedAt
              ?.toUtc()
              .toIso8601String(),
          'webdavBaseUrl': settings.webdavBaseUrl,
          'webdavUsername': settings.webdavUsername,
        },
      };
    });
  }

  Future<ImportOutcome> _applyPayload(Map<String, Object?> payload) {
    return _database.transaction(() async {
      int imported = 0;
      int skipped = 0;

      final List<Map<String, Object?>> termRows = _asRows(
        payload['allergenTerms'],
      );
      final Set<String> termIds = <String>{};
      for (final Map<String, Object?> row in termRows) {
        final String? id = row['id'] as String?;
        final String? term = row['term'] as String?;
        final String? normalized = row['normalizedTerm'] as String?;
        if (id == null || term == null || normalized == null) {
          skipped++;
          continue;
        }
        termIds.add(id);
        await _database
            .into(_database.allergenTerms)
            .insertOnConflictUpdate(
              AllergenTermsCompanion(
                id: Value(id),
                term: Value(term),
                normalizedTerm: Value(normalized),
                isActive: Value(row['isActive'] as bool? ?? true),
                note: Value(row['note'] as String?),
                createdAt: Value(_asDate(row['createdAt']) ?? _now()),
                updatedAt: Value(_asDate(row['updatedAt']) ?? _now()),
              ),
            );
        imported++;
      }

      final Set<String> barcodes = <String>{};
      for (final Map<String, Object?> row in _asRows(payload['products'])) {
        final String? barcode = row['barcode'] as String?;
        if (barcode == null) {
          skipped++;
          continue;
        }
        barcodes.add(barcode);
        await _database
            .into(_database.products)
            .insertOnConflictUpdate(
              ProductsCompanion(
                barcode: Value(barcode),
                productName: Value(row['productName'] as String?),
                brands: Value(row['brands'] as String?),
                quantity: Value(row['quantity'] as String?),
                ingredientsText: Value(row['ingredientsText'] as String?),
                ingredientsLanguage: Value(
                  row['ingredientsLanguage'] as String?,
                ),
                allergensTags: Value(row['allergensTags'] as String?),
                tracesTags: Value(row['tracesTags'] as String?),
                imageUrl: Value(row['imageUrl'] as String?),
                source: Value(
                  _asEnum(
                    row['source'],
                    ProductSource.values,
                    ProductSource.openFoodFacts,
                  ),
                ),
                hasManualOverride: Value(
                  row['hasManualOverride'] as bool? ?? false,
                ),
                fetchedAt: Value(_asDate(row['fetchedAt'])),
                updatedAt: Value(_asDate(row['updatedAt']) ?? _now()),
              ),
            );
        imported++;
      }

      final Set<String> scanIds = <String>{};
      for (final Map<String, Object?> row in _asRows(payload['scans'])) {
        final String? id = row['id'] as String?;
        final String? evaluatedText = row['evaluatedText'] as String?;
        if (id == null || evaluatedText == null) {
          skipped++;
          continue;
        }
        final String? barcode = row['barcode'] as String?;
        scanIds.add(id);
        await _database
            .into(_database.scans)
            .insertOnConflictUpdate(
              ScansCompanion(
                id: Value(id),
                scannedAt: Value(_asDate(row['scannedAt']) ?? _now()),
                inputMode: Value(
                  _asEnum(
                    row['inputMode'],
                    ScanInputMode.values,
                    ScanInputMode.manualText,
                  ),
                ),
                // Drop a reference to a product that is not in the archive,
                // rather than failing the whole import on a foreign key.
                barcode: Value(
                  barcode != null && barcodes.contains(barcode)
                      ? barcode
                      : null,
                ),
                productNameSnapshot: Value(
                  row['productNameSnapshot'] as String?,
                ),
                evaluatedText: Value(evaluatedText),
                verdict: Value(
                  _asEnum(
                    row['verdict'],
                    ScanVerdict.values,
                    ScanVerdict.unknown,
                  ),
                ),
                matchCount: Value(_asInt(row['matchCount']) ?? 0),
                // Absent in a v1 archive; a plain map lookup already reads
                // that as null, so no version branch is needed here.
                name: Value(row['name'] as String?),
                shop: Value(row['shop'] as String?),
                photoPath: Value(row['photoPath'] as String?),
              ),
            );
        imported++;
      }

      for (final Map<String, Object?> row in _asRows(payload['scanMatches'])) {
        final String? id = row['id'] as String?;
        final String? scanId = row['scanId'] as String?;
        final String? termSnapshot = row['termSnapshot'] as String?;
        if (id == null ||
            scanId == null ||
            termSnapshot == null ||
            !scanIds.contains(scanId)) {
          skipped++;
          continue;
        }
        final String? termId = row['allergenTermId'] as String?;
        await _database
            .into(_database.scanMatches)
            .insertOnConflictUpdate(
              ScanMatchesCompanion(
                id: Value(id),
                scanId: Value(scanId),
                allergenTermId: Value(
                  termId != null && termIds.contains(termId) ? termId : null,
                ),
                termSnapshot: Value(termSnapshot),
                matchedText: Value(row['matchedText'] as String? ?? ''),
                startOffset: Value(_asInt(row['startOffset']) ?? 0),
                endOffset: Value(_asInt(row['endOffset']) ?? 0),
              ),
            );
        imported++;
      }

      final Object? settings = payload['settings'];
      if (settings is Map) {
        final Map<String, Object?> values = settings.cast<String, Object?>();
        await _database.settingsDao.setPreferredLanguage(
          values['preferredIngredientsLanguage'] as String? ?? 'en',
        );
        await _database.settingsDao.setRemoteLookupEnabled(
          values['remoteLookupEnabled'] as bool? ?? true,
        );
        await _database.settingsDao.setWebdav(
          baseUrl: values['webdavBaseUrl'] as String?,
          username: values['webdavUsername'] as String?,
        );
      }

      _log.info('Imported backup: $imported rows, $skipped skipped');
      return ImportOutcome(imported: imported, skipped: skipped);
    });
  }

  static List<Map<String, Object?>> _asRows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((row) => row.cast<String, Object?>())
        .toList(growable: false);
  }

  static DateTime? _asDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static T _asEnum<T extends Enum>(Object? value, List<T> values, T fallback) {
    if (value is! String) return fallback;
    for (final T entry in values) {
      if (entry.name == value) return entry;
    }
    return fallback;
  }
}

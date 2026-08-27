import 'package:drift/drift.dart';

import '../../models/enums.dart';
import '../../models/scan.dart';
import '../app_database.dart';
import '../tables/products_table.dart';
import '../tables/scan_matches_table.dart';
import '../tables/scans_table.dart';
import 'product_dao.dart';

part 'scan_dao.g.dart';

@DriftAccessor(tables: [Scans, ScanMatches, Products])
class ScanDao extends DatabaseAccessor<AppDatabase> with _$ScanDaoMixin {
  ScanDao(super.attachedDatabase);

  Stream<List<Scan>> watchRecent({int limit = 3}) {
    final query = select(scans)
      ..orderBy([
        (t) => OrderingTerm(expression: t.scannedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch().map(
      (rows) => rows.map(_toScan).toList(growable: false),
    );
  }

  Stream<List<Scan>> watchHistory({ScanVerdict? verdict}) {
    final query = select(scans)
      ..orderBy([
        (t) => OrderingTerm(expression: t.scannedAt, mode: OrderingMode.desc),
      ]);
    if (verdict != null) {
      query.where((t) => t.verdict.equalsValue(verdict));
    }
    return query.watch().map(
      (rows) => rows.map(_toScan).toList(growable: false),
    );
  }

  /// One left-joined query, so the result view has scan, matches and product in
  /// a single stream event rather than three that can arrive out of order.
  Stream<ScanResult?> watchResult(String scanId) {
    final query = select(scans).join([
      leftOuterJoin(scanMatches, scanMatches.scanId.equalsExp(scans.id)),
      leftOuterJoin(products, products.barcode.equalsExp(scans.barcode)),
    ])..where(scans.id.equals(scanId));

    return query.watch().map((rows) {
      if (rows.isEmpty) return null;

      final ScanRow scanRow = rows.first.readTable(scans);
      final ProductRow? productRow = rows.first.readTableOrNull(products);

      final List<ScanMatch> matches = rows
          .map((row) => row.readTableOrNull(scanMatches))
          .where((row) => row != null)
          .map((row) => _toMatch(row!))
          .toList(growable: false)
        ..sort((a, b) => a.startOffset.compareTo(b.startOffset));

      return ScanResult(
        scan: _toScan(scanRow),
        matches: matches,
        product: productRow == null ? null : ProductDao.toModel(productRow),
      );
    });
  }

  Future<ScanResult?> findResult(String scanId) => watchResult(scanId).first;

  /// Column-scoped write for the fields set after a scan already exists
  /// (name, shop, photo) — mirrors SettingsDao's column-scoped write. Never
  /// touches evaluatedText, verdict or matches, so R4.7's snapshot guarantee
  /// is untouched.
  Future<void> updateDetails({
    required String scanId,
    Value<String?> name = const Value.absent(),
    Value<String?> shop = const Value.absent(),
    Value<String?> photoPath = const Value.absent(),
  }) {
    return (update(scans)..where((t) => t.id.equals(scanId))).write(
      ScansCompanion(name: name, shop: shop, photoPath: photoPath),
    );
  }

  /// Writes the scan and its matches together, then prunes — one transaction,
  /// so a crash cannot leave a scan without its matches (R7.7, R4.8).
  ///
  /// Returns the pruned rows' non-null photo paths, so the caller — which
  /// owns file I/O, this DAO does not — can delete the orphaned files.
  Future<({String scanId, List<String> prunedPhotoPaths})> insertWithMatches({
    required Scan scan,
    required List<ScanMatch> matches,
    int historyLimit = 500,
  }) async {
    late final List<String> prunedPhotoPaths;
    await transaction(() async {
      await into(scans).insertOnConflictUpdate(
        ScansCompanion(
          id: Value(scan.id),
          scannedAt: Value(scan.scannedAt),
          inputMode: Value(scan.inputMode),
          barcode: Value(scan.barcode),
          productNameSnapshot: Value(scan.productNameSnapshot),
          evaluatedText: Value(scan.evaluatedText),
          verdict: Value(scan.verdict),
          matchCount: Value(scan.matchCount),
          name: Value(scan.name),
          shop: Value(scan.shop),
          photoPath: Value(scan.photoPath),
        ),
      );

      // A re-evaluation reuses the scan id, so old matches must go first.
      await (delete(scanMatches)..where((t) => t.scanId.equals(scan.id))).go();

      for (final ScanMatch match in matches) {
        await into(scanMatches).insert(
          ScanMatchesCompanion(
            id: Value(match.id),
            scanId: Value(match.scanId),
            allergenTermId: Value(match.allergenTermId),
            termSnapshot: Value(match.termSnapshot),
            matchedText: Value(match.matchedText),
            startOffset: Value(match.startOffset),
            endOffset: Value(match.endOffset),
          ),
        );
      }

      prunedPhotoPaths = await _pruneToLimit(historyLimit);
    });
    return (scanId: scan.id, prunedPhotoPaths: prunedPhotoPaths);
  }

  /// Returns the deleted row (so its `photoPath` can be cleaned up), or
  /// `null` if no scan with that id existed.
  Future<Scan?> deleteById(String id) async {
    final List<ScanRow> rows = await (select(
      scans,
    )..where((t) => t.id.equals(id))).get();
    if (rows.isEmpty) return null;
    await (delete(scans)..where((t) => t.id.equals(id))).go();
    return _toScan(rows.first);
  }

  /// Returns every deleted row.
  Future<List<Scan>> deleteAll() async {
    final List<ScanRow> rows = await select(scans).get();
    await delete(scans).go();
    return rows.map(_toScan).toList(growable: false);
  }

  Future<List<Scan>> getAll() async {
    final rows = await select(scans).get();
    return rows.map(_toScan).toList(growable: false);
  }

  Future<List<ScanMatch>> getAllMatches() async {
    final rows = await select(scanMatches).get();
    return rows.map(_toMatch).toList(growable: false);
  }

  /// Keeps the newest [limit] scans; cascade removes their matches. Returns
  /// the pruned rows' non-null photo paths.
  Future<List<String>> _pruneToLimit(int limit) async {
    final List<String> keep =
        await (select(scans)
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.scannedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit))
            .map((row) => row.id)
            .get();
    if (keep.isEmpty) return const [];

    final List<ScanRow> pruned = await (select(
      scans,
    )..where((t) => t.id.isNotIn(keep))).get();
    await (delete(scans)..where((t) => t.id.isNotIn(keep))).go();
    return pruned
        .map((ScanRow row) => row.photoPath)
        .whereType<String>()
        .toList(growable: false);
  }

  static Scan _toScan(ScanRow row) {
    return Scan(
      id: row.id,
      scannedAt: row.scannedAt,
      inputMode: row.inputMode,
      barcode: row.barcode,
      productNameSnapshot: row.productNameSnapshot,
      evaluatedText: row.evaluatedText,
      verdict: row.verdict,
      matchCount: row.matchCount,
      name: row.name,
      shop: row.shop,
      photoPath: row.photoPath,
    );
  }

  static ScanMatch _toMatch(ScanMatchRow row) {
    return ScanMatch(
      id: row.id,
      scanId: row.scanId,
      allergenTermId: row.allergenTermId,
      termSnapshot: row.termSnapshot,
      matchedText: row.matchedText,
      startOffset: row.startOffset,
      endOffset: row.endOffset,
    );
  }
}

import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = openTestDatabase());
  tearDown(() => database.close());

  Future<void> seedTermAndProduct() async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 'term-1', term: 'Hazelnut', normalizedTerm: 'hazelnut'),
    );
    await database.productDao.upsertFromRemote(buildProduct(barcode: 'bc-1'));
  }

  test('writes a scan together with its matches', () async {
    await seedTermAndProduct();

    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1', barcode: 'bc-1'),
      matches: <ScanMatch>[
        buildMatch(id: 'm1', scanId: 's1', allergenTermId: 'term-1'),
      ],
    );

    final ScanResult result = (await database.scanDao.findResult('s1'))!;
    expect(result.scan.verdict, ScanVerdict.hit);
    expect(result.matches, hasLength(1));
    expect(result.matches.single.termSnapshot, 'hazelnut');
    expect(result.product?.productName, 'Choco Bar');
  });

  test('deleting a term keeps the match and clears its reference', () async {
    await seedTermAndProduct();
    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1', barcode: 'bc-1'),
      matches: <ScanMatch>[
        buildMatch(id: 'm1', scanId: 's1', allergenTermId: 'term-1'),
      ],
    );

    await database.allergenTermDao.deleteById('term-1');

    final ScanResult result = (await database.scanDao.findResult('s1'))!;
    expect(result.matches, hasLength(1));
    expect(result.matches.single.allergenTermId, isNull);
    // The snapshot is what makes the history still readable (R4.7).
    expect(result.matches.single.termSnapshot, 'hazelnut');
  });

  test('deleting a product keeps the scan and clears its barcode', () async {
    await seedTermAndProduct();
    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1', barcode: 'bc-1'),
      matches: const <ScanMatch>[],
    );

    await database.productDao.deleteByBarcode('bc-1');

    final ScanResult result = (await database.scanDao.findResult('s1'))!;
    expect(result.scan.barcode, isNull);
    expect(result.scan.productNameSnapshot, 'Choco Bar');
    expect(result.scan.evaluatedText, isNotEmpty);
  });

  test('deleting a scan cascades to its matches', () async {
    await seedTermAndProduct();
    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1', barcode: 'bc-1'),
      matches: <ScanMatch>[
        buildMatch(id: 'm1', scanId: 's1', allergenTermId: 'term-1'),
      ],
    );

    await database.scanDao.deleteById('s1');

    expect(await database.scanDao.findResult('s1'), isNull);
    expect(await database.scanDao.getAllMatches(), isEmpty);
  });

  test('re-evaluating the same scan id replaces its matches', () async {
    await seedTermAndProduct();
    await database.scanDao.insertWithMatches(
      scan: buildScan(id: 's1', barcode: 'bc-1', matchCount: 1),
      matches: <ScanMatch>[
        buildMatch(id: 'm1', scanId: 's1', allergenTermId: 'term-1'),
      ],
    );

    await database.scanDao.insertWithMatches(
      scan: buildScan(
        id: 's1',
        barcode: 'bc-1',
        verdict: ScanVerdict.noMatch,
        matchCount: 0,
      ),
      matches: const <ScanMatch>[],
    );

    final ScanResult result = (await database.scanDao.findResult('s1'))!;
    expect(result.scan.verdict, ScanVerdict.noMatch);
    expect(result.matches, isEmpty);
    expect(await database.scanDao.getAllMatches(), isEmpty);
  });

  test('history is pruned to the limit, newest kept', () async {
    for (int index = 0; index < 5; index++) {
      await database.scanDao.insertWithMatches(
        scan: buildScan(
          id: 's$index',
          scannedAt: DateTime.utc(2026, 8, 20, 10 + index),
        ),
        matches: const <ScanMatch>[],
        historyLimit: 3,
      );
    }

    final List<Scan> remaining = await database.scanDao.getAll();
    expect(remaining, hasLength(3));
    expect(
      remaining.map((Scan scan) => scan.id).toSet(),
      <String>{'s2', 's3', 's4'},
    );
  });

  test('watchHistory filters by verdict, newest first', () async {
    await database.scanDao.insertWithMatches(
      scan: buildScan(
        id: 's1',
        scannedAt: DateTime.utc(2026, 8, 20, 9),
        verdict: ScanVerdict.hit,
      ),
      matches: const <ScanMatch>[],
    );
    await database.scanDao.insertWithMatches(
      scan: buildScan(
        id: 's2',
        scannedAt: DateTime.utc(2026, 8, 20, 10),
        verdict: ScanVerdict.noMatch,
        matchCount: 0,
      ),
      matches: const <ScanMatch>[],
    );

    final List<Scan> all = await database.scanDao.watchHistory().first;
    expect(all.map((Scan scan) => scan.id).toList(), <String>['s2', 's1']);

    final List<Scan> hits = await database.scanDao
        .watchHistory(verdict: ScanVerdict.hit)
        .first;
    expect(hits.single.id, 's1');
  });

  test('watchRecent returns at most the requested number', () async {
    for (int index = 0; index < 4; index++) {
      await database.scanDao.insertWithMatches(
        scan: buildScan(
          id: 's$index',
          scannedAt: DateTime.utc(2026, 8, 20, 10 + index),
        ),
        matches: const <ScanMatch>[],
      );
    }

    final List<Scan> recent = await database.scanDao
        .watchRecent(limit: 3)
        .first;
    expect(recent, hasLength(3));
    expect(recent.first.id, 's3');
  });

  test('a text scan has no product and stays readable', () async {
    await database.scanDao.insertWithMatches(
      scan: buildScan(
        id: 's1',
        inputMode: ScanInputMode.ocr,
        evaluatedText: 'sugar, soy lecithin',
        verdict: ScanVerdict.noMatch,
        matchCount: 0,
      ),
      matches: const <ScanMatch>[],
    );

    final ScanResult result = (await database.scanDao.findResult('s1'))!;
    expect(result.product, isNull);
    expect(result.scan.inputMode, ScanInputMode.ocr);
    expect(result.scan.evaluatedText, 'sugar, soy lecithin');
  });
}

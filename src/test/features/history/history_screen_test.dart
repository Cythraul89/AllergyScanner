import 'package:allergy_scanner/core/models/enums.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:allergy_scanner/features/history/history_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure function tests — no widget pump needed (§4, R7.12).
void main() {
  Scan scan({
    required String id,
    required DateTime scannedAt,
    String? shop,
  }) => Scan(
    id: id,
    scannedAt: scannedAt,
    inputMode: ScanInputMode.barcode,
    evaluatedText: 'sugar',
    verdict: ScanVerdict.noMatch,
    matchCount: 0,
    shop: shop,
  );

  group('withShopGroups', () {
    test('groups are ordered by their most recent scan', () {
      final DateTime t1 = DateTime.utc(2026, 1, 1);
      final DateTime t2 = DateTime.utc(2026, 1, 2);
      final List<Object> rows = withShopGroups(<Scan>[
        scan(id: 's1', scannedAt: t2, shop: 'Migros'),
        scan(id: 's2', scannedAt: t1, shop: 'Lidl'),
      ], ungroupedLabel: 'Ungrouped');
      // Migros scanned more recently, so its header comes first.
      final int migrosHeaderIndex = rows.indexWhere(
        (Object r) => r is ShopHeader && r.label == 'Migros',
      );
      final int lidlHeaderIndex = rows.indexWhere(
        (Object r) => r is ShopHeader && r.label == 'Lidl',
      );
      expect(migrosHeaderIndex, isNot(-1));
      expect(lidlHeaderIndex, isNot(-1));
      expect(migrosHeaderIndex, lessThan(lidlHeaderIndex));
    });

    test('a null or whitespace-only shop lands under Ungrouped', () {
      final DateTime t = DateTime.utc(2026, 1, 1);
      final List<Object> rows = withShopGroups(<Scan>[
        scan(id: 's1', scannedAt: t),
        scan(id: 's2', scannedAt: t, shop: '   '),
      ], ungroupedLabel: 'Ungrouped');
      final Iterable<Scan> scans = rows.whereType<Scan>();
      expect(scans.map((Scan s) => s.id), <String>['s1', 's2']);
      expect(
        rows.whereType<ShopHeader>().where((h) => h.label == 'Ungrouped'),
        hasLength(1),
      );
    });

    test('day headers still interleave within a shop group', () {
      final DateTime day1 = DateTime.utc(2026, 1, 1);
      final DateTime day2 = DateTime.utc(2026, 1, 2);
      final List<Object> rows = withShopGroups(<Scan>[
        scan(id: 's1', scannedAt: day2, shop: 'Migros'),
        scan(id: 's2', scannedAt: day1, shop: 'Migros'),
      ], ungroupedLabel: 'Ungrouped');
      // 1 shop header + 2 day headers + 2 scans.
      expect(rows, hasLength(5));
      expect(rows.whereType<Scan>(), hasLength(2));
    });
  });

  group('withDayHeaders', () {
    test('one header per distinct day, scans keep their order', () {
      final DateTime day1 = DateTime.utc(2026, 1, 1, 9);
      final DateTime day1Later = DateTime.utc(2026, 1, 1, 15);
      final DateTime day2 = DateTime.utc(2026, 1, 2, 9);
      final List<Object> rows = withDayHeaders(<Scan>[
        scan(id: 's1', scannedAt: day1),
        scan(id: 's2', scannedAt: day1Later),
        scan(id: 's3', scannedAt: day2),
      ]);
      // day1 header, s1, s2, day2 header, s3 — one header per day change.
      expect(rows.whereType<String>(), hasLength(2));
      expect(rows.whereType<Scan>(), hasLength(3));
    });
  });
}

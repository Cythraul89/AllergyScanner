import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:allergy_scanner/core/models/scan.dart';
import 'package:allergy_scanner/features/result/scan_result_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure function test — no widget pump needed (§11 item 1's display-only
/// grouping in the result view).
void main() {
  final DateTime ts = DateTime.utc(2026, 1, 1);

  ScanMatch match({
    required String id,
    required int startOffset,
    String? allergenTermId,
    String termSnapshot = 'hazelnut',
  }) => ScanMatch(
    id: id,
    scanId: 'scan-1',
    allergenTermId: allergenTermId,
    termSnapshot: termSnapshot,
    matchedText: termSnapshot,
    startOffset: startOffset,
    endOffset: startOffset + termSnapshot.length,
  );

  AllergenTerm term({required String id, String? groupId}) => AllergenTerm(
    id: id,
    term: id,
    normalizedTerm: id,
    isActive: true,
    groupId: groupId,
    createdAt: ts,
    updatedAt: ts,
  );

  test('matches with no term id render standalone', () {
    final List<List<ScanMatch>> buckets = bucketMatchesByGroup(
      <ScanMatch>[match(id: 'm1', startOffset: 0)],
      const <AllergenTerm>[],
    );
    expect(buckets, hasLength(1));
    expect(buckets.single, hasLength(1));
  });

  test('matches whose term is ungrouped render standalone', () {
    final List<List<ScanMatch>> buckets = bucketMatchesByGroup(
      <ScanMatch>[match(id: 'm1', startOffset: 0, allergenTermId: 't1')],
      <AllergenTerm>[term(id: 't1')],
    );
    expect(buckets, hasLength(1));
    expect(buckets.single, hasLength(1));
  });

  test('matches whose terms share a group are bucketed together', () {
    final List<List<ScanMatch>> buckets = bucketMatchesByGroup(
      <ScanMatch>[
        match(id: 'm1', startOffset: 0, allergenTermId: 't1'),
        match(id: 'm2', startOffset: 20, allergenTermId: 't2'),
      ],
      <AllergenTerm>[
        term(id: 't1', groupId: 'g1'),
        term(id: 't2', groupId: 'g1'),
      ],
    );
    expect(buckets, hasLength(1));
    expect(buckets.single.map((ScanMatch m) => m.id), <String>['m1', 'm2']);
  });

  test('a deleted term (allergenTermId null after setNull) renders standalone', () {
    final List<List<ScanMatch>> buckets = bucketMatchesByGroup(
      <ScanMatch>[match(id: 'm1', startOffset: 0)],
      <AllergenTerm>[term(id: 't1', groupId: 'g1')],
    );
    expect(buckets, hasLength(1));
  });

  test('buckets are ordered by their first match\'s offset', () {
    final List<List<ScanMatch>> buckets = bucketMatchesByGroup(
      <ScanMatch>[
        match(id: 'later', startOffset: 50, allergenTermId: 't3'),
        match(id: 'earlier', startOffset: 5, allergenTermId: 't1'),
      ],
      <AllergenTerm>[term(id: 't1'), term(id: 't3')],
    );
    expect(
      buckets.map((List<ScanMatch> b) => b.first.id),
      <String>['earlier', 'later'],
    );
  });
}

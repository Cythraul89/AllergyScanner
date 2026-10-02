import 'package:allergy_scanner/core/models/allergen_group.dart';
import 'package:allergy_scanner/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../database/test_database.dart';

/// `termColorsByGroup` is what turns a group's colour into the highlight drawn
/// over a matched allergen (R7.16), in both the scan preview and the result
/// view.
void main() {
  AllergenGroupWithTerms group({
    required String id,
    required String label,
    Color? color,
    required List<String> termIds,
  }) {
    return AllergenGroupWithTerms(
      group: AllergenGroup(
        id: id,
        label: label,
        color: color,
        createdAt: testTimestamp,
        updatedAt: testTimestamp,
      ),
      terms: termIds
          .map(
            (String termId) => buildTerm(
              id: termId,
              term: termId,
              normalizedTerm: termId,
              groupId: id,
            ),
          )
          .toList(growable: false),
    );
  }

  test('every member of a coloured group maps to that colour', () {
    final Map<String, Color> colors = termColorsByGroup(<AllergenGroupWithTerms>[
      group(
        id: 'g1',
        label: 'Hazelnut',
        color: Colors.red,
        termIds: <String>['t1', 't2', 't3'],
      ),
    ]);

    expect(colors, <String, Color>{
      't1': Colors.red,
      't2': Colors.red,
      't3': Colors.red,
    });
  });

  test('a group with no colour contributes nothing, so the theme wins', () {
    final Map<String, Color> colors = termColorsByGroup(<AllergenGroupWithTerms>[
      group(id: 'g1', label: 'Hazelnut', termIds: <String>['t1']),
    ]);

    expect(colors, isEmpty);
    expect(colors['t1'], isNull);
  });

  test('two groups keep their own colours', () {
    final Map<String, Color> colors = termColorsByGroup(<AllergenGroupWithTerms>[
      group(id: 'g1', label: 'Hazelnut', color: Colors.red, termIds: <String>['t1']),
      group(id: 'g2', label: 'Milk', color: Colors.blue, termIds: <String>['t2']),
      group(id: 'g3', label: 'Soy', termIds: <String>['t3']),
    ]);

    expect(colors['t1'], Colors.red);
    expect(colors['t2'], Colors.blue);
    expect(colors['t3'], isNull);
  });

  test('an empty group list yields an empty map', () {
    expect(termColorsByGroup(const <AllergenGroupWithTerms>[]), isEmpty);
  });
}

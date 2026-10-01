import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/allergen_group.dart';
import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = openTestDatabase());
  tearDown(() => database.close());

  AllergenGroup group({
    String id = 'group-1',
    String label = 'Hazelnut',
    Color? color,
    GroupCriticality? criticality,
  }) => AllergenGroup(
    id: id,
    label: label,
    color: color,
    criticality: criticality,
    createdAt: testTimestamp,
    updatedAt: testTimestamp,
  );

  test('AllergenGroupWithTerms.isActive is true for a group with no members yet', () {
    expect(
      AllergenGroupWithTerms(group: group(), terms: const []).isActive,
      isTrue,
    );
  });

  test('AllergenGroupWithTerms.isActive is true only when every member is active', () {
    final AllergenTerm active = buildTerm(
      id: 't1',
      term: 'Milk',
      normalizedTerm: 'milk',
    );
    final AllergenTerm inactive = buildTerm(
      id: 't2',
      term: 'Lait',
      normalizedTerm: 'lait',
      isActive: false,
    );
    expect(
      AllergenGroupWithTerms(group: group(), terms: [active]).isActive,
      isTrue,
    );
    expect(
      AllergenGroupWithTerms(group: group(), terms: [active, inactive]).isActive,
      isFalse,
    );
  });

  test('inserts and finds a group by id', () async {
    await database.allergenGroupDao.insertGroup(group());
    final AllergenGroup? found = await database.allergenGroupDao.findById(
      'group-1',
    );
    expect(found?.label, 'Hazelnut');
  });

  test('insertGroup stores color and criticality', () async {
    await database.allergenGroupDao.insertGroup(
      group(color: Colors.red, criticality: GroupCriticality.high),
    );
    final AllergenGroup? found = await database.allergenGroupDao.findById(
      'group-1',
    );
    expect(found?.color?.toARGB32(), Colors.red.toARGB32());
    expect(found?.criticality, GroupCriticality.high);
  });

  test('a group with no color/criticality round-trips as null', () async {
    await database.allergenGroupDao.insertGroup(group());
    final AllergenGroup? found = await database.allergenGroupDao.findById(
      'group-1',
    );
    expect(found?.color, isNull);
    expect(found?.criticality, isNull);
  });

  test('setAppearance is column-scoped and can clear both fields', () async {
    await database.allergenGroupDao.insertGroup(group());
    final DateTime later = testTimestamp.add(const Duration(days: 1));

    await database.allergenGroupDao.setAppearance(
      id: 'group-1',
      color: const Value(Colors.blue),
      criticality: const Value(GroupCriticality.medium),
      updatedAt: later,
    );
    AllergenGroup? found = await database.allergenGroupDao.findById(
      'group-1',
    );
    expect(found?.label, 'Hazelnut');
    expect(found?.color?.toARGB32(), Colors.blue.toARGB32());
    expect(found?.criticality, GroupCriticality.medium);
    expect(found?.updatedAt.toUtc(), later);

    await database.allergenGroupDao.setAppearance(
      id: 'group-1',
      color: const Value(null),
      criticality: const Value(null),
      updatedAt: later,
    );
    found = await database.allergenGroupDao.findById('group-1');
    expect(found?.color, isNull);
    expect(found?.criticality, isNull);
  });

  test('updateLabel is column-scoped', () async {
    await database.allergenGroupDao.insertGroup(group());
    final DateTime later = testTimestamp.add(const Duration(days: 1));
    await database.allergenGroupDao.updateLabel(
      id: 'group-1',
      label: 'Haselnuss',
      updatedAt: later,
    );
    final AllergenGroup? found = await database.allergenGroupDao.findById(
      'group-1',
    );
    expect(found?.label, 'Haselnuss');
    // Drift returns DateTimeColumn values in local time; DateTime.== also
    // compares the UTC/local flag, so normalise before comparing an instant.
    expect(found?.updatedAt.toUtc(), later);
    expect(found?.createdAt.toUtc(), testTimestamp);
  });

  test('deleting a group ungroups its members rather than deleting them', () async {
    await database.allergenGroupDao.insertGroup(group());
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 'term-1',
        term: 'Hazelnut',
        normalizedTerm: 'hazelnut',
        groupId: 'group-1',
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 'term-2',
        term: 'Haselnuss',
        normalizedTerm: 'haselnuss',
        groupId: 'group-1',
      ),
    );

    await database.allergenGroupDao.deleteById('group-1');

    final AllergenTerm? term1 = await database.allergenTermDao.findById(
      'term-1',
    );
    final AllergenTerm? term2 = await database.allergenTermDao.findById(
      'term-2',
    );
    expect(term1, isNotNull);
    expect(term1?.groupId, isNull);
    expect(term2, isNotNull);
    expect(term2?.groupId, isNull);
  });

  test('watchAllWithTerms buckets and sorts members per group', () async {
    await database.allergenGroupDao.insertGroup(group());
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 'term-2',
        term: 'Noisette',
        normalizedTerm: 'noisette',
        groupId: 'group-1',
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 'term-1',
        term: 'Hazelnut',
        normalizedTerm: 'hazelnut',
        groupId: 'group-1',
      ),
    );
    // Ungrouped term must never appear in a group's member list.
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 'term-3', term: 'Milk', normalizedTerm: 'milk'),
    );

    final List<AllergenGroupWithTerms> groups = await database
        .allergenGroupDao
        .watchAllWithTerms()
        .first;

    expect(groups, hasLength(1));
    expect(groups.single.group.label, 'Hazelnut');
    expect(
      groups.single.terms.map((t) => t.normalizedTerm),
      <String>['hazelnut', 'noisette'],
    );
  });

  test('watchAllWithTerms includes a group with no members', () async {
    await database.allergenGroupDao.insertGroup(group());
    final List<AllergenGroupWithTerms> groups = await database
        .allergenGroupDao
        .watchAllWithTerms()
        .first;
    expect(groups, hasLength(1));
    expect(groups.single.terms, isEmpty);
  });

  test('watchUngrouped excludes terms assigned to a group', () async {
    await database.allergenGroupDao.insertGroup(group());
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 'term-1',
        term: 'Hazelnut',
        normalizedTerm: 'hazelnut',
        groupId: 'group-1',
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 'term-2', term: 'Milk', normalizedTerm: 'milk'),
    );

    final List<AllergenTerm> ungrouped = await database.allergenTermDao
        .watchUngrouped()
        .first;

    expect(ungrouped.map((t) => t.id), <String>['term-2']);
  });

  test('setGroup assigns and then clears a term\'s group', () async {
    await database.allergenGroupDao.insertGroup(group());
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 'term-1', term: 'Hazelnut', normalizedTerm: 'hazelnut'),
    );

    await database.allergenTermDao.setGroup(
      id: 'term-1',
      groupId: 'group-1',
      updatedAt: testTimestamp,
    );
    AllergenTerm? term = await database.allergenTermDao.findById('term-1');
    expect(term?.groupId, 'group-1');

    await database.allergenTermDao.setGroup(
      id: 'term-1',
      groupId: null,
      updatedAt: testTimestamp,
    );
    term = await database.allergenTermDao.findById('term-1');
    expect(term?.groupId, isNull);
  });
}

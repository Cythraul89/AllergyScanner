import 'dart:io';

import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/allergen_group.dart';
import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:allergy_scanner/core/models/enums.dart';
import 'package:allergy_scanner/core/services/allergy_list_json_service.dart';
import 'package:allergy_scanner/core/services/log_service.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_helper;

import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late LogService log;

  setUp(() {
    database = openTestDatabase();
    log = LogService(
      File(
        path_helper.join(
          Directory.systemTemp.path,
          'allergy_scanner_allergy_list_test.log',
        ),
      ),
    );
  });

  tearDown(() => database.close());

  AllergyListJsonService serviceFor(AppDatabase db) => AllergyListJsonService(
    database: db,
    log: log,
    now: () => testTimestamp,
  );

  test('round-trips a group (with color/criticality) and an ungrouped term', () async {
    await database.allergenGroupDao.insertGroup(
      AllergenGroup(
        id: 'g1',
        label: 'Hazelnut',
        color: Colors.red,
        criticality: GroupCriticality.high,
        createdAt: testTimestamp,
        updatedAt: testTimestamp,
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 't1',
        term: 'Hazelnut',
        normalizedTerm: 'hazelnut',
        groupId: 'g1',
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't2', term: 'Milk', normalizedTerm: 'milk'),
    );

    final String json = await serviceFor(database).exportToJson();

    final AppDatabase target = openTestDatabase();
    addTearDown(target.close);
    final AllergyListImportOutcome outcome = await serviceFor(
      target,
    ).importFromJson(json);

    expect(outcome.groupsCreated, 1);
    expect(outcome.termsAdded, 2);
    expect(outcome.termsSkipped, 0);

    final List<AllergenGroupWithTerms> groups = await target.allergenGroupDao
        .watchAllWithTerms()
        .first;
    expect(groups, hasLength(1));
    expect(groups.single.group.label, 'Hazelnut');
    expect(groups.single.group.color?.toARGB32(), Colors.red.toARGB32());
    expect(groups.single.group.criticality, GroupCriticality.high);
    expect(groups.single.terms.single.term, 'Hazelnut');

    final List<AllergenTerm> ungrouped = await target.allergenTermDao
        .watchUngrouped()
        .first;
    expect(ungrouped.single.term, 'Milk');
  });

  test(
    'merges into an existing group matched by label, keeping its color/criticality',
    () async {
      await database.allergenGroupDao.insertGroup(
        AllergenGroup(
          id: 'existing',
          label: '  Hazelnut  ',
          color: Colors.green,
          criticality: GroupCriticality.low,
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        ),
      );

      const String json = '''
      {
        "allergyListFormatVersion": 1,
        "groups": [
          {
            "label": "hazelnut",
            "color": 4294901760,
            "criticality": "high",
            "terms": [{"term": "Noisette", "isActive": true}]
          }
        ],
        "ungroupedTerms": []
      }
      ''';

      final AllergyListImportOutcome outcome = await serviceFor(
        database,
      ).importFromJson(json);

      expect(outcome.groupsCreated, 0);
      expect(outcome.termsAdded, 1);

      final List<AllergenGroupWithTerms> groups = await database
          .allergenGroupDao
          .watchAllWithTerms()
          .first;
      expect(groups, hasLength(1));
      expect(groups.single.group.id, 'existing');
      // Never overwritten by the import — merge is additive only.
      expect(groups.single.group.color?.toARGB32(), Colors.green.toARGB32());
      expect(groups.single.group.criticality, GroupCriticality.low);
      expect(groups.single.terms.single.term, 'Noisette');
    },
  );

  test('skips a term that already exists anywhere on the list', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk'),
    );

    const String json = '''
    {
      "allergyListFormatVersion": 1,
      "groups": [],
      "ungroupedTerms": [{"term": "Milk"}, {"term": "Soy"}]
    }
    ''';

    final AllergyListImportOutcome outcome = await serviceFor(
      database,
    ).importFromJson(json);

    expect(outcome.termsAdded, 1);
    expect(outcome.termsSkipped, 1);
    expect(outcome.hasSkipped, isTrue);
  });

  test('never touches pre-existing, unrelated data', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Soy', normalizedTerm: 'soy'),
    );

    const String json = '''
    {
      "allergyListFormatVersion": 1,
      "groups": [],
      "ungroupedTerms": [{"term": "Milk"}]
    }
    ''';

    await serviceFor(database).importFromJson(json);

    final AllergenTerm? untouched = await database.allergenTermDao.findById(
      't1',
    );
    expect(untouched, isNotNull);
    expect(untouched!.term, 'Soy');
  });

  // ── Regression tests for the four import defects found in review ────────

  test(
    'a group with an unusable label still imports its terms, ungrouped',
    () async {
      const String json = '''
      {
        "allergyListFormatVersion": 1,
        "groups": [
          {"label": "   ", "terms": [{"term": "Hazelnut"}, {"term": "Walnut"}]}
        ]
      }
      ''';

      final AllergyListImportOutcome outcome = await serviceFor(
        database,
      ).importFromJson(json);

      // The allergens must survive the bad header, not be silently dropped.
      expect(outcome.termsAdded, 2);
      expect(outcome.groupsRejected, 1);
      expect(outcome.termsSkipped, 0);
      final List<AllergenTerm> ungrouped = await database.allergenTermDao
          .watchUngrouped()
          .first;
      expect(
        ungrouped.map((AllergenTerm t) => t.term),
        containsAll(<String>['Hazelnut', 'Walnut']),
      );
    },
  );

  test('a term imported into a group adopts the group\'s active state', () async {
    await database.allergenGroupDao.insertGroup(
      AllergenGroup(
        id: 'g1',
        label: 'Hazelnut',
        createdAt: testTimestamp,
        updatedAt: testTimestamp,
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 't1',
        term: 'Hazelnut',
        normalizedTerm: 'hazelnut',
        groupId: 'g1',
        isActive: false,
      ),
    );

    // The file says active; the group on this device is switched off.
    const String json = '''
    {
      "allergyListFormatVersion": 1,
      "groups": [
        {"label": "Hazelnut", "terms": [{"term": "Noisette", "isActive": true}]}
      ]
    }
    ''';
    await serviceFor(database).importFromJson(json);

    final List<AllergenGroupWithTerms> groups = await database
        .allergenGroupDao
        .getAllWithTerms();
    // A group is one substance: never partially active.
    expect(groups.single.terms.every((AllergenTerm t) => !t.isActive), isTrue);
    expect(groups.single.isActive, isFalse);
  });

  test('a too-short term is reported as rejected, never as a duplicate', () async {
    const String json = '''
    {"allergyListFormatVersion": 1, "ungroupedTerms": [{"term": "Ei"}]}
    ''';

    final AllergyListImportOutcome outcome = await serviceFor(
      database,
    ).importFromJson(json);

    expect(outcome.termsAdded, 0);
    expect(outcome.termsSkipped, 0, reason: 'not a duplicate');
    expect(outcome.termsRejected, 1);
  });

  test('ill-typed fields are rejected, not thrown, and nothing is half-written',
      () async {
    final String json =
        '{"allergyListFormatVersion": 1, "ungroupedTerms": ['
        '{"term": "Hazelnut"}, {"term": 42}, {"term": "${'x' * 300}"}, '
        '{"term": "Walnut", "isActive": "yes", "note": 7}]}';

    final AllergyListImportOutcome outcome = await serviceFor(
      database,
    ).importFromJson(json);

    expect(outcome.termsAdded, 2);
    expect(outcome.termsRejected, 2);
    final List<AllergenTerm> all = await database.allergenTermDao
        .watchUngrouped()
        .first;
    expect(all.map((AllergenTerm t) => t.term), <String>['Hazelnut', 'Walnut']);
    // A non-bool isActive falls back to the default rather than throwing.
    expect(all.every((AllergenTerm t) => t.isActive), isTrue);
  });

  test('a group whose terms are all duplicates leaves no empty group', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk'),
    );

    const String json = '''
    {
      "allergyListFormatVersion": 1,
      "groups": [{"label": "Dairy", "terms": [{"term": "Milk"}]}]
    }
    ''';
    final AllergyListImportOutcome outcome = await serviceFor(
      database,
    ).importFromJson(json);

    expect(outcome.groupsCreated, 0);
    expect(outcome.termsSkipped, 1);
    expect(await database.allergenGroupDao.getAllWithTerms(), isEmpty);
  });

  test('a genuinely empty group still round-trips', () async {
    const String json = '''
    {"allergyListFormatVersion": 1, "groups": [{"label": "Dairy", "terms": []}]}
    ''';
    final AllergyListImportOutcome outcome = await serviceFor(
      database,
    ).importFromJson(json);

    expect(outcome.groupsCreated, 1);
    final List<AllergenGroupWithTerms> groups = await database
        .allergenGroupDao
        .getAllWithTerms();
    expect(groups.single.group.label, 'Dairy');
    expect(groups.single.terms, isEmpty);
  });

  test('a JSON object with neither list is refused', () async {
    expect(
      () => serviceFor(database).importFromJson('{"name": "package.json"}'),
      throwsA(
        isA<AllergyListFormatException>().having(
          (e) => e.problem,
          'problem',
          isA<AllergyListContentInvalid>(),
        ),
      ),
    );
  });

  test('throws AllergyListContentInvalid for text that is not JSON', () async {
    expect(
      () => serviceFor(database).importFromJson('not json'),
      throwsA(
        isA<AllergyListFormatException>().having(
          (e) => e.problem,
          'problem',
          isA<AllergyListContentInvalid>(),
        ),
      ),
    );
  });

  test('throws AllergyListFormatTooNew for a newer file format', () async {
    const String json = '''
    {"allergyListFormatVersion": 99, "groups": [], "ungroupedTerms": []}
    ''';
    expect(
      () => serviceFor(database).importFromJson(json),
      throwsA(
        isA<AllergyListFormatException>().having(
          (e) => e.problem,
          'problem',
          isA<AllergyListFormatTooNew>(),
        ),
      ),
    );
  });
}

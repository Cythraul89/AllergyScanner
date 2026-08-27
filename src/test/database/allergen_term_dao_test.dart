import 'package:allergy_scanner/core/database/app_database.dart';
import 'package:allergy_scanner/core/models/allergen_group.dart';
import 'package:allergy_scanner/core/models/allergen_term.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = openTestDatabase());
  tearDown(() => database.close());

  test('inserts and reads a term', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Hazelnut', normalizedTerm: 'hazelnut'),
    );

    final AllergenTerm? found = await database.allergenTermDao.findById('t1');
    expect(found, isNotNull);
    expect(found!.term, 'Hazelnut');
    expect(found.isActive, isTrue);
  });

  test('finds a term by its normalised form', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Sésame', normalizedTerm: 'sesame'),
    );

    final AllergenTerm? found = await database.allergenTermDao
        .findByNormalizedTerm('sesame');
    expect(found?.id, 't1');
  });

  test('rejects a second term with the same normalised form', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk'),
    );

    // The unique index is what makes the duplicate check reliable (R4.1).
    await expectLater(
      database.allergenTermDao.insertTerm(
        buildTerm(id: 't2', term: 'MILK', normalizedTerm: 'milk'),
      ),
      throwsA(anything),
    );
  });

  test('watchActive excludes deactivated terms', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk'),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 't2',
        term: 'Celery',
        normalizedTerm: 'celery',
        isActive: false,
      ),
    );

    expect(
      await database.allergenTermDao.getActive(),
      hasLength(1),
    );
    expect(
      (await database.allergenTermDao.watchActive().first).single.id,
      't1',
    );
  });

  test('updateTerm rewrites the normalised column with the term', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk'),
    );

    await database.allergenTermDao.updateTerm(
      id: 't1',
      term: 'Nüsse',
      normalizedTerm: 'nusse',
      note: 'severe',
      updatedAt: testTimestamp,
    );

    final AllergenTerm updated =
        (await database.allergenTermDao.findById('t1'))!;
    expect(updated.term, 'Nüsse');
    expect(updated.normalizedTerm, 'nusse');
    expect(updated.note, 'severe');
  });

  test('setActive touches only the active flag', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 't1',
        term: 'Milk',
        normalizedTerm: 'milk',
        note: 'keep me',
      ),
    );

    await database.allergenTermDao.setActive(
      id: 't1',
      isActive: false,
      updatedAt: testTimestamp,
    );

    final AllergenTerm updated =
        (await database.allergenTermDao.findById('t1'))!;
    expect(updated.isActive, isFalse);
    expect(updated.note, 'keep me');
    expect(updated.term, 'Milk');
  });

  test('watchAll lists active terms before inactive ones', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(
        id: 't1',
        term: 'Almond',
        normalizedTerm: 'almond',
        isActive: false,
      ),
    );
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't2', term: 'Zucchini', normalizedTerm: 'zucchini'),
    );

    final List<AllergenTerm> all =
        await database.allergenTermDao.watchAll().first;
    expect(all.map((AllergenTerm term) => term.id).toList(), <String>[
      't2',
      't1',
    ]);
  });

  test(
    'setActiveForGroup cascades to every member and leaves other terms alone',
    () async {
      await database.allergenGroupDao.insertGroup(
        AllergenGroup(
          id: 'g1',
          label: 'Milk',
          createdAt: testTimestamp,
          updatedAt: testTimestamp,
        ),
      );
      await database.allergenTermDao.insertTerm(
        buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk', groupId: 'g1'),
      );
      await database.allergenTermDao.insertTerm(
        buildTerm(id: 't2', term: 'Lait', normalizedTerm: 'lait', groupId: 'g1'),
      );
      await database.allergenTermDao.insertTerm(
        buildTerm(id: 't3', term: 'Celery', normalizedTerm: 'celery'),
      );

      await database.allergenTermDao.setActiveForGroup(
        groupId: 'g1',
        isActive: false,
        updatedAt: testTimestamp,
      );

      expect((await database.allergenTermDao.findById('t1'))!.isActive, isFalse);
      expect((await database.allergenTermDao.findById('t2'))!.isActive, isFalse);
      expect((await database.allergenTermDao.findById('t3'))!.isActive, isTrue);
    },
  );

  test('deleteById removes the term', () async {
    await database.allergenTermDao.insertTerm(
      buildTerm(id: 't1', term: 'Milk', normalizedTerm: 'milk'),
    );
    await database.allergenTermDao.deleteById('t1');
    expect(await database.allergenTermDao.findById('t1'), isNull);
  });
}

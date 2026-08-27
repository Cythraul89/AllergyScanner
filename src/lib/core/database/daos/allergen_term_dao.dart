import 'package:drift/drift.dart';

import '../../models/allergen_term.dart';
import '../app_database.dart';
import '../tables/allergen_terms_table.dart';

part 'allergen_term_dao.g.dart';

@DriftAccessor(tables: [AllergenTerms])
class AllergenTermDao extends DatabaseAccessor<AppDatabase>
    with _$AllergenTermDaoMixin {
  AllergenTermDao(super.attachedDatabase);

  /// Active terms first, then alphabetical — the order the Allergies screen shows.
  Stream<List<AllergenTerm>> watchAll() {
    final query = select(allergenTerms)
      ..orderBy([
        (t) => OrderingTerm(expression: t.isActive, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.normalizedTerm),
      ]);
    return query.watch().map(
      (rows) => rows.map(toModel).toList(growable: false),
    );
  }

  Stream<List<AllergenTerm>> watchActive() {
    final query = select(allergenTerms)
      ..where((t) => t.isActive.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.normalizedTerm)]);
    return query.watch().map(
      (rows) => rows.map(toModel).toList(growable: false),
    );
  }

  Future<List<AllergenTerm>> getActive() async {
    final query = select(allergenTerms)
      ..where((t) => t.isActive.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.normalizedTerm)]);
    final rows = await query.get();
    return rows.map(toModel).toList(growable: false);
  }

  Future<AllergenTerm?> findById(String id) async {
    final row = await (select(
      allergenTerms,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : toModel(row);
  }

  /// Used for the duplicate check before an insert (R4.1).
  Future<AllergenTerm?> findByNormalizedTerm(String normalizedTerm) async {
    final row = await (select(allergenTerms)
          ..where((t) => t.normalizedTerm.equals(normalizedTerm)))
        .getSingleOrNull();
    return row == null ? null : toModel(row);
  }

  Future<void> insertTerm(AllergenTerm term) {
    return into(allergenTerms).insert(
      AllergenTermsCompanion.insert(
        id: term.id,
        term: term.term,
        normalizedTerm: term.normalizedTerm,
        isActive: Value(term.isActive),
        note: Value(term.note),
        groupId: Value(term.groupId),
        createdAt: term.createdAt,
        updatedAt: term.updatedAt,
      ),
    );
  }

  /// Partial write: touches only term, normalised form, note and the timestamp.
  Future<void> updateTerm({
    required String id,
    required String term,
    required String normalizedTerm,
    required DateTime updatedAt,
    String? note,
  }) {
    return (update(allergenTerms)..where((t) => t.id.equals(id))).write(
      AllergenTermsCompanion(
        term: Value(term),
        normalizedTerm: Value(normalizedTerm),
        note: Value(note),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> setActive({
    required String id,
    required bool isActive,
    required DateTime updatedAt,
  }) {
    return (update(allergenTerms)..where((t) => t.id.equals(id))).write(
      AllergenTermsCompanion(
        isActive: Value(isActive),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> deleteById(String id) {
    return (delete(allergenTerms)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<AllergenTerm>> watchUngrouped() {
    final query = select(allergenTerms)
      ..where((t) => t.groupId.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.normalizedTerm)]);
    return query.watch().map((rows) => rows.map(toModel).toList(growable: false));
  }

  /// Assigns or clears (`groupId: null`) a term's group. Column-scoped like
  /// setActive — never routed through a full-object save.
  Future<void> setGroup({
    required String id,
    required String? groupId,
    required DateTime updatedAt,
  }) {
    return (update(allergenTerms)..where((t) => t.id.equals(id))).write(
      AllergenTermsCompanion(
        groupId: Value(groupId),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  static AllergenTerm toModel(AllergenTermRow row) {
    return AllergenTerm(
      id: row.id,
      term: row.term,
      normalizedTerm: row.normalizedTerm,
      isActive: row.isActive,
      note: row.note,
      groupId: row.groupId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}

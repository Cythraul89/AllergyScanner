import 'package:drift/drift.dart';

import '../../models/allergen_group.dart';
import '../../models/allergen_term.dart';
import '../app_database.dart';
import '../tables/allergen_groups_table.dart';
import '../tables/allergen_terms_table.dart';
import 'allergen_term_dao.dart';

part 'allergen_group_dao.g.dart';

@DriftAccessor(tables: [AllergenGroups, AllergenTerms])
class AllergenGroupDao extends DatabaseAccessor<AppDatabase>
    with _$AllergenGroupDaoMixin {
  AllergenGroupDao(super.attachedDatabase);

  /// One left-joined query, so the grouped Allergies screen has every group
  /// and its members in a single stream event rather than N+1 streams that
  /// can arrive out of order — same reasoning as ScanDao.watchResult.
  Stream<List<AllergenGroupWithTerms>> watchAllWithTerms() {
    final query = select(allergenGroups).join([
      leftOuterJoin(
        allergenTerms,
        allergenTerms.groupId.equalsExp(allergenGroups.id),
      ),
    ]);

    return query.watch().map((rows) {
      final Map<String, AllergenGroupRow> groupRows = {};
      final Map<String, List<AllergenTerm>> termsByGroup = {};
      for (final row in rows) {
        final AllergenGroupRow groupRow = row.readTable(allergenGroups);
        groupRows[groupRow.id] = groupRow;
        final AllergenTermRow? termRow = row.readTableOrNull(allergenTerms);
        if (termRow != null) {
          (termsByGroup[groupRow.id] ??= <AllergenTerm>[]).add(
            AllergenTermDao.toModel(termRow),
          );
        }
      }
      final List<AllergenGroupWithTerms> result = groupRows.values.map((
        AllergenGroupRow g,
      ) {
        final List<AllergenTerm> terms =
            (termsByGroup[g.id] ?? const <AllergenTerm>[]).toList()
              ..sort((a, b) => a.normalizedTerm.compareTo(b.normalizedTerm));
        return AllergenGroupWithTerms(group: _toGroup(g), terms: terms);
      }).toList(growable: false);
      result.sort((a, b) => a.group.label.compareTo(b.group.label));
      return result;
    });
  }

  Future<AllergenGroup?> findById(String id) async {
    final row = await (select(
      allergenGroups,
    )..where((g) => g.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toGroup(row);
  }

  Future<void> insertGroup(AllergenGroup group) {
    return into(allergenGroups).insert(
      AllergenGroupsCompanion.insert(
        id: group.id,
        label: group.label,
        createdAt: group.createdAt,
        updatedAt: group.updatedAt,
      ),
    );
  }

  /// Column-scoped: only the label and timestamp change.
  Future<void> updateLabel({
    required String id,
    required String label,
    required DateTime updatedAt,
  }) {
    return (update(allergenGroups)..where((g) => g.id.equals(id))).write(
      AllergenGroupsCompanion(label: Value(label), updatedAt: Value(updatedAt)),
    );
  }

  /// Member terms are kept, ungrouped (FK setNull) — a group is an
  /// organisational label, not a container the way a scan owns its matches.
  Future<void> deleteById(String id) {
    return (delete(allergenGroups)..where((g) => g.id.equals(id))).go();
  }

  static AllergenGroup _toGroup(AllergenGroupRow row) => AllergenGroup(
    id: row.id,
    label: row.label,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

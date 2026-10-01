import 'package:drift/drift.dart';

import '../../models/enums.dart';

/// A set of allergen terms meaning the same substance in different
/// languages/spellings (REQUIREMENTS §11 item 1).
@DataClassName('AllergenGroupRow')
class AllergenGroups extends Table {
  TextColumn get id => text()();

  /// Display name shown as the group header, e.g. "Hazelnut". Not matched
  /// against anything and not required to be unique — matching stays
  /// per-term (§5.3), unchanged by grouping.
  TextColumn get label => text().withLength(min: 1, max: 200)();

  /// User-picked ARGB value for the group's identification dot, or `null` for
  /// none. Purely visual — never read by the matcher.
  IntColumn get color => integer().nullable()();

  /// User-assigned severity tag, or `null` for none (R7.16).
  IntColumn get criticality => intEnum<GroupCriticality>().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
